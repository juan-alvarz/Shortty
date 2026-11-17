//! The editor window (the macOS Classic layout): one toolbar with everything, tool options floating at the top
//! right of the picture, recent captures along the bottom. One window serves every capture.

pub mod annotation;
mod arrow;
mod canvas;
mod draw;
mod effects;
mod icons;
mod model;
mod strip;
mod text;

use crate::geometry::{Point, Rect};
use crate::{history, output, settings::Settings};
use adw::prelude::*;
use annotation::{Annotation, Rgb, Tool};
use arrow::ArrowStyle;
use canvas::RulerAxes;
use effects::{AreaShape, RedactStyle};
use gtk::{gdk, gio, glib};
use icons::Icon;
use model::{Model, PALETTE};
use std::cell::{Cell, RefCell};
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::{Duration, Instant};
use text::TextStyle;

/// The tools in toolbar order, with their keys (the macOS `EditorWindowController.toolKeys`).
const TOOLS: [(Tool, Icon, &str, &str); 12] = [
    (Tool::Select, Icon::Cursor, "Select", "V"),
    (Tool::Pencil, Icon::Pencil, "Pencil", "P"),
    (Tool::Arrow, Icon::Arrow, "Arrow", "A"),
    (Tool::Text, Icon::Text, "Text", "T"),
    (Tool::Rectangle, Icon::Rectangle, "Rectangle", "R"),
    (Tool::Ellipse, Icon::Ellipse, "Ellipse", "O"),
    (Tool::Step, Icon::Step, "Numbered steps", "N"),
    (Tool::Magnifier, Icon::Magnifier, "Magnifier", "M"),
    (Tool::Blur, Icon::Blur, "Blur", "B"),
    (Tool::Spotlight, Icon::Spotlight, "Spotlight", "S"),
    (Tool::Crop, Icon::Crop, "Crop", "C"),
    (Tool::Ruler, Icon::Ruler, "Ruler", "U"),
];

pub struct Editor {
    window: adw::ApplicationWindow,
    model: RefCell<Model>,
    area: gtk::DrawingArea,
    scrolled: gtk::ScrolledWindow,
    drag: RefCell<canvas::Drag>,
    frozen: Cell<Option<Rect>>,
    /// The color an export fills the grown canvas with.
    edge: Cell<Rgb>,
    /// Typing into text goes through the input method, so dead keys and accents work.
    im: gtk::IMMulticontext,
    tools: Vec<(Tool, gtk::ToggleButton)>,
    keycaps: Vec<gtk::Label>,
    swatch: gtk::DrawingArea,
    options: gtk::Box,
    width: gtk::Scale,
    width_label: gtk::Label,
    arrow_styles: gtk::DropDown,
    text_styles: gtk::DropDown,
    redact_styles: gtk::DropDown,
    area_shapes: gtk::DropDown,
    hint: gtk::Label,
    reset_crop: gtk::Button,
    apply_crop: gtk::Button,
    /// Ruler: the image point under the pointer, and which runs to show.
    ruler_point: Cell<Option<Point>>,
    ruler_axes: Cell<RulerAxes>,
    size_label: gtk::Label,
    zoom_label: gtk::Label,
    strip: Rc<strip::Strip>,
    /// Set while widgets are updated from the model, so their signals don't write back.
    syncing: Cell<bool>,
    last_escape: Cell<Option<Instant>>,
    pointer: Cell<(f64, f64)>,
    save_timer: RefCell<Option<glib::SourceId>>,
    /// A thickness slider being dragged: the list before it moved, recorded as one undo step once it rests.
    slider: RefCell<Option<(Vec<Annotation>, glib::SourceId)>>,
}

thread_local! {
    static EDITOR: RefCell<Option<Rc<Editor>>> = const { RefCell::new(None) };
}

/// Opens a picture in the editor. A history capture keeps its edits next to it; anything else is edited as a copy.
pub fn open(path: &Path) {
    let image = match draw::load(path) {
        Ok(image) => image,
        Err(error) => return output::notify_failure("Open", &error),
    };
    let source = path.starts_with(history::folder()).then(|| path.to_path_buf());
    let model = Model::new(image, source);
    match EDITOR.with_borrow(|e| e.clone()) {
        Some(editor) => editor.load(model),
        None => {
            let editor = Editor::build(model);
            EDITOR.with_borrow_mut(|e| *e = Some(editor.clone()));
            editor.load_view();
        }
    }
}

/// Reopen Last Capture: the newest capture with its edits.
pub fn reopen_last() {
    match history::captures().first() {
        Some(latest) => open(latest),
        None => output::notify_failure("Reopen", "There are no captures yet."),
    }
}

impl Editor {
    fn build(model: Model) -> Rc<Editor> {
        install_css();
        let area = gtk::DrawingArea::builder().hexpand(true).vexpand(true).focusable(true).build();
        let scrolled = gtk::ScrolledWindow::builder().child(&area).hexpand(true).vexpand(true).build();

        // Toolbar: the app, Copy and Save, the tools, the color; image size and zoom on the right.
        let header = adw::HeaderBar::builder().title_widget(&gtk::Box::new(gtk::Orientation::Horizontal, 0)).build();
        let svg = glib::Bytes::from_static(include_bytes!("../../../Design/AppIcon.svg"));
        if let Ok(texture) = gdk::Texture::from_bytes(&svg) {
            let logo = gtk::Image::from_paintable(Some(&texture));
            logo.set_pixel_size(24);
            logo.set_margin_end(6);
            header.pack_start(&logo);
        }
        let copy = icon_button(Icon::Copy, "Copy (Ctrl+C)");
        let save = icon_button(Icon::Save, "Save (Ctrl+S)");
        header.pack_start(&copy);
        header.pack_start(&save);
        header.pack_start(&separator());
        let mut tools = Vec::new();
        let mut keycaps = Vec::new();
        for (tool, icon, title, key) in TOOLS {
            let keycap = gtk::Label::builder()
                .label(key)
                .css_classes(["keycap"])
                .halign(gtk::Align::End)
                .valign(gtk::Align::End)
                .visible(false)
                .build();
            let content = gtk::Overlay::builder().child(&icons::widget(icon, 18)).build();
            content.add_overlay(&keycap);
            let button = gtk::ToggleButton::builder()
                .child(&content)
                .tooltip_text(format!("{title} ({key})"))
                .focus_on_click(false)
                .css_classes(["tool"])
                .build();
            if let Some((_, first)) = tools.first() {
                button.set_group(Some(first));
            }
            if matches!(tool, Tool::Magnifier | Tool::Crop) {
                header.pack_start(&separator()); // drawing | effects | crop and measure
            }
            header.pack_start(&button);
            tools.push((tool, button));
            keycaps.push(keycap);
        }
        header.pack_start(&separator());
        let swatch =
            gtk::DrawingArea::builder().content_width(16).content_height(16).halign(gtk::Align::Center).valign(gtk::Align::Center).build();
        let color_button =
            gtk::MenuButton::builder().child(&swatch).tooltip_text("Color").css_classes(["tool", "swatch"]).focus_on_click(false).build();
        header.pack_start(&color_button);

        let size_label = gtk::Label::new(None);
        let zoom_label = gtk::Label::new(None);
        for (label, caption) in [(&zoom_label, "Zoom"), (&size_label, "Image size")] {
            let column = gtk::Box::new(gtk::Orientation::Vertical, 0);
            label.add_css_class("stat");
            label.set_halign(gtk::Align::End);
            column.append(label);
            column.append(&gtk::Label::builder().label(caption).css_classes(["stat-caption"]).halign(gtk::Align::End).build());
            header.pack_end(&column);
        }

        // Tool options, floating at the top right of the picture.
        let arrow_styles = gtk::DropDown::from_strings(&ArrowStyle::ALL.map(ArrowStyle::title));
        let text_styles = gtk::DropDown::from_strings(&TextStyle::ALL.map(TextStyle::title));
        let redact_styles = gtk::DropDown::from_strings(&RedactStyle::OFFERED.map(RedactStyle::title));
        let area_shapes = gtk::DropDown::from_strings(&AreaShape::ALL.map(AreaShape::title));
        let hint = gtk::Label::builder().css_classes(["hint"]).build();
        let reset_crop = gtk::Button::builder().label("Reset").focus_on_click(false).build();
        let apply_crop = gtk::Button::builder().label("Crop").css_classes(["suggested-action"]).focus_on_click(false).build();
        let width = gtk::Scale::builder().orientation(gtk::Orientation::Horizontal).width_request(120).draw_value(false).build();
        let width_label = gtk::Label::builder().css_classes(["stat"]).width_chars(5).xalign(1.0).build();
        let options = gtk::Box::builder()
            .spacing(8)
            .css_classes(["options"])
            .halign(gtk::Align::End)
            .valign(gtk::Align::Start)
            .margin_top(12)
            .margin_end(12)
            .build();
        options.append(&arrow_styles);
        options.append(&text_styles);
        options.append(&redact_styles);
        options.append(&area_shapes);
        options.append(&hint);
        options.append(&reset_crop);
        options.append(&apply_crop);
        options.append(&width);
        options.append(&width_label);
        let overlay = gtk::Overlay::builder().child(&scrolled).build();
        overlay.add_overlay(&options);

        let strip = strip::Strip::new(
            Rc::new(|path: PathBuf| open(&path)),
            Rc::new(|| {
                if let Some(editor) = EDITOR.with_borrow(|e| e.clone()) {
                    editor.captures_removed();
                }
            }),
        );
        let view = adw::ToolbarView::new();
        view.add_top_bar(&header);
        view.set_content(Some(&overlay));
        view.add_bottom_bar(&strip.root);

        let (w, h) = (model.image.width() as f64, model.image.height() as f64);
        let factor =
            gdk::Display::default().and_then(|d| d.monitors().item(0)).and_downcast::<gdk::Monitor>().map_or(1, |m| m.scale_factor())
                as f64;
        let window = adw::ApplicationWindow::builder()
            .title("Shortty")
            .content(&view)
            .default_width((w / factor + 80.0).clamp(760.0, 1500.0) as i32)
            .default_height((h / factor + 170.0).clamp(520.0, 1000.0) as i32)
            .css_classes(["shortty-editor"])
            .build();
        window.set_application(gio::Application::default().and_downcast_ref::<gtk::Application>());

        let im = gtk::IMMulticontext::new();
        im.set_client_widget(Some(&area));
        let editor = Rc::new(Editor {
            window,
            model: RefCell::new(model),
            area,
            scrolled,
            drag: RefCell::new(canvas::Drag::None),
            frozen: Cell::new(None),
            edge: Cell::new(Rgb(0, 0, 0)),
            im,
            tools,
            keycaps,
            swatch,
            options,
            width,
            width_label,
            arrow_styles,
            text_styles,
            redact_styles,
            area_shapes,
            hint,
            reset_crop,
            apply_crop,
            ruler_point: Cell::new(None),
            ruler_axes: Cell::new(RulerAxes::Both),
            size_label,
            zoom_label,
            strip,
            syncing: Cell::new(false),
            last_escape: Cell::new(None),
            pointer: Cell::new((0.0, 0.0)),
            save_timer: RefCell::new(None),
            slider: RefCell::new(None),
        });
        color_button.set_popover(Some(&editor.color_popover(&color_button)));
        editor.connect(&copy, &save);
        editor
    }

    /// Wires the widgets to the model. Closures hold the editor weakly; the window owns them.
    fn connect(self: &Rc<Self>, copy: &gtk::Button, save: &gtk::Button) {
        let weak = Rc::downgrade(self);
        let with = move |f: &dyn Fn(&Rc<Editor>)| {
            if let Some(editor) = weak.upgrade() {
                f(&editor)
            }
        };
        let with = Rc::new(with);
        macro_rules! on {
            ($body:expr) => {{
                let with = with.clone();
                move |_: &_| with(&$body)
            }};
        }
        copy.connect_clicked(on!(|e: &Rc<Editor>| e.copy()));
        save.connect_clicked(on!(|e: &Rc<Editor>| e.save()));
        for (tool, button) in &self.tools {
            let (tool, with) = (*tool, with.clone());
            button.connect_toggled(move |button| {
                if button.is_active() {
                    with(&|e: &Rc<Editor>| {
                        if !e.syncing.get() {
                            e.model.borrow_mut().set_tool(tool);
                            e.changed();
                        }
                    })
                }
            });
        }
        self.swatch.set_draw_func({
            let with = with.clone();
            move |_, cr, w, h| {
                with(&|e: &Rc<Editor>| {
                    let (r, g, b) = e.model.borrow().color.floats();
                    cr.arc(w as f64 / 2.0, h as f64 / 2.0, w.min(h) as f64 / 2.0 - 1.0, 0.0, std::f64::consts::TAU);
                    cr.set_source_rgb(r, g, b);
                    let _ = cr.fill_preserve();
                    cr.set_source_rgba(1.0, 1.0, 1.0, 0.35);
                    cr.set_line_width(1.0);
                    let _ = cr.stroke();
                })
            }
        });
        self.arrow_styles.connect_selected_notify(on!(|e: &Rc<Editor>| {
            if !e.syncing.get() {
                let style = ArrowStyle::ALL[e.arrow_styles.selected() as usize];
                e.model.borrow_mut().set_arrow_style(style);
                e.changed();
            }
        }));
        self.text_styles.connect_selected_notify(on!(|e: &Rc<Editor>| {
            if !e.syncing.get() {
                let style = TextStyle::ALL[e.text_styles.selected() as usize];
                e.model.borrow_mut().set_text_style(style);
                e.changed();
            }
        }));
        self.width.connect_value_changed(on!(|e: &Rc<Editor>| e.width_moved()));
        self.redact_styles.connect_selected_notify(on!(|e: &Rc<Editor>| {
            if !e.syncing.get() {
                let style = RedactStyle::OFFERED[e.redact_styles.selected() as usize];
                e.model.borrow_mut().set_redact_style(style);
                e.changed();
            }
        }));
        self.area_shapes.connect_selected_notify(on!(|e: &Rc<Editor>| {
            if !e.syncing.get() {
                let shape = AreaShape::ALL[e.area_shapes.selected() as usize];
                let kind = e.options_tool();
                e.model.borrow_mut().set_area_shape(kind.unwrap_or(Tool::Spotlight), shape);
                e.changed();
            }
        }));
        self.reset_crop.connect_clicked(on!(|e: &Rc<Editor>| {
            e.model.borrow_mut().reset_crop();
            e.relayout();
            e.changed();
        }));
        self.apply_crop.connect_clicked(on!(|e: &Rc<Editor>| e.apply_crop()));

        // The canvas: drawing, the mouse, zoom.
        self.area.set_draw_func({
            let with = with.clone();
            move |_, cr, w, h| with(&|e: &Rc<Editor>| e.draw(cr, w as f64, h as f64))
        });
        self.area.connect_resize({
            let with = with.clone();
            move |_, _, _| with(&|e: &Rc<Editor>| e.refresh())
        });
        let drag = gtk::GestureDrag::new();
        drag.connect_drag_begin({
            let with = with.clone();
            move |_, x, y| with(&|e: &Rc<Editor>| e.press(x, y))
        });
        drag.connect_drag_update({
            let with = with.clone();
            move |gesture, dx, dy| {
                let state = gesture.current_event_state();
                let Some((x, y)) = gesture.start_point() else { return };
                let (shift, ctrl) = (state.contains(gdk::ModifierType::SHIFT_MASK), state.contains(gdk::ModifierType::CONTROL_MASK));
                with(&|e: &Rc<Editor>| e.drag_to(x + dx, y + dy, shift, ctrl))
            }
        });
        drag.connect_drag_end({
            let with = with.clone();
            move |_, _, _| with(&|e: &Rc<Editor>| e.release())
        });
        self.area.add_controller(drag);
        let clicks = gtk::GestureClick::new();
        clicks.connect_pressed({
            let with = with.clone();
            move |_, n, x, y| {
                if n == 2 {
                    with(&|e: &Rc<Editor>| e.double_click(x, y))
                }
            }
        });
        self.area.add_controller(clicks);
        let motion = gtk::EventControllerMotion::new();
        motion.connect_motion({
            let with = with.clone();
            move |_, x, y| {
                with(&|e: &Rc<Editor>| {
                    e.pointer.set((x, y));
                    e.hover(x, y);
                })
            }
        });
        motion.connect_leave({
            let with = with.clone();
            move |_| {
                with(&|e: &Rc<Editor>| {
                    e.ruler_point.set(None);
                    e.area.queue_draw();
                })
            }
        });
        self.area.add_controller(motion);
        // Ctrl + scroll zooms around the pointer; plain scrolling pans.
        let scroll = gtk::EventControllerScroll::new(gtk::EventControllerScrollFlags::VERTICAL);
        scroll.set_propagation_phase(gtk::PropagationPhase::Capture);
        scroll.connect_scroll({
            let with = with.clone();
            move |controller, _, dy| {
                if !controller.current_event_state().contains(gdk::ModifierType::CONTROL_MASK) {
                    return glib::Propagation::Proceed;
                }
                with(&|e: &Rc<Editor>| e.zoom_by(1.1f64.powf(-dy), Some(e.pointer.get())));
                glib::Propagation::Stop
            }
        });
        self.scrolled.add_controller(scroll);
        let pinch = gtk::GestureZoom::new();
        let pinch_start = Rc::new(Cell::new(1.0));
        pinch.connect_begin({
            let (with, pinch_start) = (with.clone(), pinch_start.clone());
            move |_, _| with(&|e: &Rc<Editor>| pinch_start.set(e.effective_zoom()))
        });
        pinch.connect_scale_changed({
            let with = with.clone();
            move |_, scale| with(&|e: &Rc<Editor>| e.set_zoom(Some(pinch_start.get() * scale), Some(e.pointer.get())))
        });
        self.area.add_controller(pinch);

        // Typing: the input method hands over finished text (accents included).
        self.im.connect_commit({
            let with = with.clone();
            move |_, typed| {
                with(&|e: &Rc<Editor>| {
                    let text = e.model.borrow().editing_text();
                    if let Some(text) = text {
                        e.model.borrow_mut().set_text(&(text + typed));
                        e.area.queue_draw();
                    }
                })
            }
        });

        // Keys go through the window first, so shortcuts work wherever focus is.
        let keys = gtk::EventControllerKey::new();
        keys.set_propagation_phase(gtk::PropagationPhase::Capture);
        keys.connect_key_pressed({
            let with = with.clone();
            move |controller, key, _, state| {
                let Some(editor) = with_editor(&with) else { return glib::Propagation::Proceed };
                editor.key(controller, key, state)
            }
        });
        keys.connect_key_released({
            let with = with.clone();
            move |_, key, _, _| {
                if matches!(key, gdk::Key::Control_L | gdk::Key::Control_R) {
                    with(&|e: &Rc<Editor>| e.keycaps.iter().for_each(|k| k.set_visible(false)));
                }
                if matches!(key, gdk::Key::_1 | gdk::Key::_2) {
                    with(&|e: &Rc<Editor>| {
                        e.ruler_axes.set(RulerAxes::Both);
                        e.area.queue_draw();
                    });
                }
            }
        });
        self.window.add_controller(keys);
        self.window.connect_close_request({
            let with = with.clone();
            move |_| {
                with(&|e: &Rc<Editor>| e.closing());
                glib::Propagation::Proceed
            }
        });
    }

    /// Shows a new model in the open window, saving the previous capture's edits.
    fn load(self: &Rc<Self>, mut model: Model) {
        self.end_editing();
        {
            let old = self.model.borrow();
            old.save_edits();
            model.take_choices(&old);
        }
        *self.model.borrow_mut() = model;
        *self.drag.borrow_mut() = canvas::Drag::None;
        self.frozen.set(None);
        self.load_view();
    }

    fn load_view(&self) {
        self.edge.set(draw::edge_color_of(&self.model.borrow().image));
        self.strip.reload(self.model.borrow().source.as_deref());
        self.relayout();
        self.refresh();
        self.window.present();
        self.area.grab_focus();
    }

    /// Captures were deleted from the strip. If the open one went too, the newest left opens, or the editor closes.
    fn captures_removed(self: &Rc<Self>) {
        let gone = self.model.borrow().source.as_ref().is_some_and(|s| !s.exists());
        if !gone {
            return self.strip.reload(self.model.borrow().source.as_deref());
        }
        self.model.borrow_mut().source = None; // nothing left to save its edits next to
        match history::captures().first() {
            Some(newest) => open(newest),
            None => self.window.close(),
        }
    }

    /// After any change: update the chrome, redraw, and save the edits soon.
    pub fn changed(self: &Rc<Self>) {
        self.refresh();
        self.area.queue_draw();
        if let Some(timer) = self.save_timer.take() {
            timer.remove();
        }
        let weak = Rc::downgrade(self);
        *self.save_timer.borrow_mut() = Some(glib::timeout_add_local_once(Duration::from_millis(500), move || {
            if let Some(editor) = weak.upgrade() {
                editor.save_timer.take();
                editor.model.borrow().save_edits();
                editor.strip.reload(editor.model.borrow().source.as_deref());
            }
        }));
    }

    /// Puts the model's state into the widgets.
    fn refresh(&self) {
        self.syncing.set(true);
        let m = self.model.borrow();
        for (tool, button) in &self.tools {
            button.set_active(*tool == m.tool);
        }
        self.swatch.queue_draw();
        // Options follow what's selected, else the tool.
        drop(m);
        let kind = self.options_tool();
        let m = self.model.borrow();
        self.options.set_visible(kind.is_some());
        if let Some(kind) = kind {
            self.arrow_styles.set_visible(kind == Tool::Arrow);
            self.text_styles.set_visible(kind == Tool::Text);
            self.redact_styles.set_visible(kind == Tool::Blur);
            self.area_shapes.set_visible(matches!(kind, Tool::Spotlight | Tool::Magnifier));
            self.arrow_styles.set_selected(ArrowStyle::ALL.iter().position(|s| *s == m.arrow_style).unwrap_or(0) as u32);
            self.text_styles.set_selected(TextStyle::ALL.iter().position(|s| *s == m.text_style).unwrap_or(0) as u32);
            self.redact_styles.set_selected(RedactStyle::OFFERED.iter().position(|s| *s == m.redact_style).unwrap_or(0) as u32);
            let area = if kind == Tool::Spotlight { m.spotlight_shape } else { m.magnifier_shape };
            self.area_shapes.set_selected(AreaShape::ALL.iter().position(|s| *s == area).unwrap_or(0) as u32);
            // Crop has buttons, the ruler a hint; erase has nothing to adjust.
            let hint = match kind {
                Tool::Crop if m.crop_box.is_none() => {
                    Some(if m.crop.is_none() { "Drag to choose the area" } else { "Drag a new area, or reset" })
                }
                Tool::Ruler => Some("Point at something to measure it · hold 1 or 2 for one direction"),
                _ => None,
            };
            self.hint.set_visible(hint.is_some());
            self.hint.set_text(hint.unwrap_or(""));
            self.reset_crop.set_visible(kind == Tool::Crop && m.crop.is_some());
            self.apply_crop.set_visible(kind == Tool::Crop && m.crop_box.is_some());
            let slider = !matches!(kind, Tool::Crop | Tool::Ruler) && (kind != Tool::Blur || m.redact_style.uses_strength());
            self.width.set_visible(slider);
            self.width_label.set_visible(slider);
            let (low, high) = Model::width_range(kind);
            self.width.set_range(low, high);
            let width = m.selected().map_or(m.width(kind), |a| a.width);
            self.width.set_value(width);
            let unit = if kind == Tool::Spotlight { "%" } else { " px" };
            self.width_label.set_text(&format!("{}{unit}", width.round()));
            self.width.set_tooltip_text(Some(match kind {
                Tool::Text => "Text size",
                Tool::Blur => "Blur strength",
                Tool::Spotlight => "Dim",
                Tool::Step => "Size",
                _ => "Thickness",
            }));
        }
        let c = m.content_rect();
        drop(m);
        self.size_label.set_text(&format!("{}×{}px", c.width, c.height));
        self.zoom_label.set_text(&format!("{}%", (self.effective_zoom() * 100.0).round()));
        self.syncing.set(false);
    }

    /// Whose options show: what's selected, else the tool (none for Select).
    fn options_tool(&self) -> Option<Tool> {
        let m = self.model.borrow();
        m.selected().map(Annotation::tool).or((m.tool != Tool::Select).then_some(m.tool))
    }

    fn apply_crop(self: &Rc<Self>) {
        self.model.borrow_mut().apply_crop();
        self.relayout();
        self.changed();
    }

    fn width_moved(self: &Rc<Self>) {
        if self.syncing.get() {
            return;
        }
        let value = self.width.value().round();
        let before = self.model.borrow().annotations.clone();
        self.model.borrow_mut().set_width(value, false);
        let unit = if self.options_tool() == Some(Tool::Spotlight) { "%" } else { " px" };
        self.width_label.set_text(&format!("{value}{unit}"));
        self.area.queue_draw();
        // One undo step once the slider rests, from where it started.
        let started = self.slider.take().map_or(before, |(before, timer)| {
            timer.remove();
            before
        });
        let weak = Rc::downgrade(self);
        let timer = glib::timeout_add_local_once(Duration::from_millis(400), move || {
            let Some(editor) = weak.upgrade() else { return };
            if let Some((before, _)) = editor.slider.take() {
                let changed = editor.model.borrow().annotations != before;
                if changed {
                    editor.model.borrow_mut().record_change(before);
                }
                editor.changed();
            }
        });
        *self.slider.borrow_mut() = Some((started, timer));
    }

    fn color_popover(self: &Rc<Self>, button: &gtk::MenuButton) -> gtk::Popover {
        let grid = gtk::Grid::builder().row_spacing(6).column_spacing(6).build();
        for (i, color) in PALETTE.into_iter().enumerate() {
            let dot = gtk::DrawingArea::builder().content_width(22).content_height(22).build();
            dot.set_draw_func(move |_, cr, w, h| {
                let (r, g, b) = color.floats();
                cr.arc(w as f64 / 2.0, h as f64 / 2.0, w as f64 / 2.0 - 1.0, 0.0, std::f64::consts::TAU);
                cr.set_source_rgb(r, g, b);
                let _ = cr.fill_preserve();
                cr.set_source_rgba(1.0, 1.0, 1.0, 0.25);
                cr.set_line_width(1.0);
                let _ = cr.stroke();
            });
            let pick = gtk::Button::builder().child(&dot).css_classes(["flat", "dot"]).tooltip_text(color.hex()).build();
            let (weak, menu) = (Rc::downgrade(self), button.clone());
            pick.connect_clicked(move |_| {
                if let Some(e) = weak.upgrade() {
                    e.set_color(color);
                    menu.popdown();
                }
            });
            grid.attach(&pick, (i % 5) as i32, (i / 5) as i32, 1, 1);
        }
        let hex = gtk::Entry::builder().placeholder_text("#RRGGBB").max_length(7).width_chars(8).build();
        let weak = Rc::downgrade(self);
        hex.connect_activate(move |entry| {
            if let (Some(e), Some(color)) = (weak.upgrade(), Rgb::parse(&entry.text())) {
                e.set_color(color);
            }
        });
        let dropper = gtk::Button::builder()
            .child(&icons::widget(Icon::Eyedropper, 18))
            .tooltip_text("Pick a color from the screen")
            .css_classes(["flat"])
            .build();
        let (weak, menu) = (Rc::downgrade(self), button.clone());
        dropper.connect_clicked(move |_| {
            menu.popdown();
            let weak = weak.clone();
            glib::spawn_future_local(async move {
                // hyprpicker freezes the screen and prints the picked color.
                let picked = crate::capture::run(&["hyprpicker", "-f", "hex"]).await;
                if let (Some(e), Some(color)) = (weak.upgrade(), picked.ok().and_then(|hex| Rgb::parse(&hex))) {
                    e.set_color(color);
                }
            });
        });
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        row.append(&hex);
        row.append(&dropper);
        let content = gtk::Box::builder()
            .orientation(gtk::Orientation::Vertical)
            .spacing(10)
            .margin_top(6)
            .margin_bottom(6)
            .margin_start(6)
            .margin_end(6)
            .build();
        content.append(&grid);
        content.append(&row);
        let popover = gtk::Popover::builder().child(&content).build();
        let (weak, entry) = (Rc::downgrade(self), hex.clone());
        popover.connect_show(move |_| {
            if let Some(e) = weak.upgrade() {
                entry.set_text(&e.model.borrow().color.hex());
            }
        });
        popover
    }

    fn set_color(self: &Rc<Self>, color: Rgb) {
        self.model.borrow_mut().set_color(color);
        self.changed();
    }

    // MARK: Keyboard

    fn key(self: &Rc<Self>, controller: &gtk::EventControllerKey, key: gdk::Key, state: gdk::ModifierType) -> glib::Propagation {
        use glib::Propagation::{Proceed, Stop};
        let ctrl = state.contains(gdk::ModifierType::CONTROL_MASK);
        let shift = state.contains(gdk::ModifierType::SHIFT_MASK);
        if matches!(key, gdk::Key::Control_L | gdk::Key::Control_R) {
            // Holding Ctrl shows each tool's key on its button.
            self.keycaps.iter().for_each(|k| k.set_visible(true));
            return Proceed;
        }
        // Typing: letters go to the text; shortcuts with Ctrl still work.
        if self.model.borrow().editing.is_some() && !ctrl {
            match key {
                gdk::Key::Escape => self.end_editing(),
                gdk::Key::BackSpace => {
                    let text = self.model.borrow().editing_text().unwrap_or_default();
                    let mut chars = text.chars();
                    chars.next_back();
                    self.model.borrow_mut().set_text(chars.as_str());
                }
                gdk::Key::Return | gdk::Key::KP_Enter => {
                    let text = self.model.borrow().editing_text().unwrap_or_default();
                    self.model.borrow_mut().set_text(&(text + "\n"));
                }
                _ => {
                    if let Some(event) = controller.current_event() {
                        self.im.filter_keypress(&event);
                    }
                }
            }
            self.changed();
            return Stop;
        }
        // A text field (the color's hex) keeps its keys.
        if gtk::prelude::GtkWindowExt::focus(&self.window).is_some_and(|w| w.is::<gtk::Text>()) {
            return Proceed;
        }
        let lower = key.to_lower();
        if ctrl {
            match lower {
                gdk::Key::z if shift => self.model.borrow_mut().redo(),
                gdk::Key::z => self.model.borrow_mut().undo(),
                gdk::Key::y => self.model.borrow_mut().redo(),
                gdk::Key::c => self.copy(),
                gdk::Key::s => self.save(),
                gdk::Key::d => self.model.borrow_mut().duplicate_picked(),
                gdk::Key::bracketright => self.model.borrow_mut().reorder_picked(true),
                gdk::Key::bracketleft => self.model.borrow_mut().reorder_picked(false),
                gdk::Key::plus | gdk::Key::equal | gdk::Key::KP_Add => self.zoom_by(1.25, None),
                gdk::Key::minus | gdk::Key::KP_Subtract => self.zoom_by(0.8, None),
                gdk::Key::_0 | gdk::Key::KP_0 => self.set_zoom(None, None),
                gdk::Key::w => self.window.close(),
                _ => return Proceed,
            }
            self.relayout();
            self.changed();
            return Stop;
        }
        if state.contains(gdk::ModifierType::ALT_MASK) {
            return Proceed;
        }
        let step = if shift { 10.0 } else { 1.0 };
        match lower {
            gdk::Key::Return | gdk::Key::KP_Enter => self.apply_crop(),
            // Ruler: 1 and 2 pick one direction while held.
            gdk::Key::_1 | gdk::Key::_2 if self.model.borrow().tool == Tool::Ruler => {
                self.ruler_axes.set(if lower == gdk::Key::_1 { RulerAxes::Horizontal } else { RulerAxes::Vertical });
                self.area.queue_draw();
                return Stop;
            }
            gdk::Key::Escape => {
                // Back to Select; on Select, deselect; twice quickly closes the editor.
                let (tool, picked) = (self.model.borrow().tool, !self.model.borrow().picked().is_empty());
                let twice = self.last_escape.get().is_some_and(|t| t.elapsed() < Duration::from_millis(400));
                if tool != Tool::Select {
                    self.model.borrow_mut().set_tool(Tool::Select);
                } else if picked {
                    self.model.borrow_mut().select(None);
                } else if twice {
                    self.window.close();
                    return Stop;
                }
                self.last_escape.set(Some(Instant::now()));
            }
            gdk::Key::Delete | gdk::Key::BackSpace => self.model.borrow_mut().delete_picked(),
            gdk::Key::Left => self.model.borrow_mut().nudge_picked(-step, 0.0),
            gdk::Key::Right => self.model.borrow_mut().nudge_picked(step, 0.0),
            gdk::Key::Up => self.model.borrow_mut().nudge_picked(0.0, -step),
            gdk::Key::Down => self.model.borrow_mut().nudge_picked(0.0, step),
            _ => {
                let name = lower.name().map(|n| n.to_uppercase());
                let Some((tool, ..)) = TOOLS.iter().find(|(.., k)| name.as_deref() == Some(*k)) else { return Proceed };
                self.model.borrow_mut().set_tool(*tool);
            }
        }
        self.relayout();
        self.changed();
        Stop
    }

    // MARK: Zoom

    /// Screen pixels per image pixel (1 = 100%).
    fn effective_zoom(&self) -> f64 {
        self.scale() * self.area.scale_factor() as f64
    }

    fn zoom_by(&self, factor: f64, anchor: Option<(f64, f64)>) {
        self.set_zoom(Some(self.effective_zoom() * factor), anchor);
    }

    /// Zooms keeping the image point under `anchor` (view points; the visible middle when None) in place.
    fn set_zoom(&self, zoom: Option<f64>, anchor: Option<(f64, f64)>) {
        let (h, v) = (self.scrolled.hadjustment(), self.scrolled.vadjustment());
        let anchor = anchor.unwrap_or((h.value() + h.page_size() / 2.0, v.value() + v.page_size() / 2.0));
        let (in_view_x, in_view_y) = (anchor.0 - h.value(), anchor.1 - v.value());
        let point = self.to_image(anchor.0, anchor.1);
        self.model.borrow_mut().zoom = zoom.map(|z| z.clamp(0.05, 8.0));
        self.relayout();
        self.refresh();
        let weak = self.area.downgrade();
        let editor = EDITOR.with_borrow(|e| e.clone());
        glib::idle_add_local_once(move || {
            let (Some(_), Some(editor)) = (weak.upgrade(), editor) else { return };
            let (x, y) = editor.to_view(point);
            editor.scrolled.hadjustment().set_value(x - in_view_x);
            editor.scrolled.vadjustment().set_value(y - in_view_y);
        });
    }

    // MARK: Output

    /// Copy: the picture with its edits to the clipboard, then the editor closes.
    fn copy(self: &Rc<Self>) {
        self.end_editing();
        let file = glib::user_cache_dir().join("shortty/Copy/capture.png");
        let _ = std::fs::create_dir_all(file.parent().unwrap());
        if let Err(error) = draw::save_png(&self.model.borrow().rendered(), &file) {
            return output::notify_failure("Copy", &error);
        }
        self.window.close();
        glib::spawn_future_local(async move {
            match output::copy(&file).await {
                Ok(()) => output::notify("Copied", "The picture is on the clipboard.", None),
                Err(error) => output::notify_failure("Copy", &error),
            }
        });
    }

    /// Save: `shortty-<timestamp>-image.png` in the save folder, then the editor closes.
    fn save(self: &Rc<Self>) {
        self.end_editing();
        let folder = Settings::load().save_folder;
        let file = folder.join(format!("shortty-{}-image.png", glib::DateTime::now_local().unwrap().format("%Y%m%d-%H%M%S").unwrap()));
        let saved = std::fs::create_dir_all(&folder)
            .map_err(|e| e.to_string())
            .and_then(|_| draw::save_png(&self.model.borrow().rendered(), &file));
        match saved {
            Ok(()) => {
                self.window.close();
                let shown = file.strip_prefix(glib::home_dir()).map_or(file.display().to_string(), |p| format!("~/{}", p.display()));
                output::notify("Saved", &shown, Some(&file));
            }
            Err(error) => output::notify_failure("Save", &error),
        }
    }

    /// The window is going away: keep the edits; the next capture builds a new one.
    fn closing(&self) {
        self.end_editing();
        if let Some(timer) = self.save_timer.take() {
            timer.remove();
        }
        self.model.borrow().save_edits();
        EDITOR.with_borrow_mut(|e| *e = None);
    }
}

fn with_editor(with: &Rc<impl Fn(&dyn Fn(&Rc<Editor>))>) -> Option<Rc<Editor>> {
    let found = RefCell::new(None);
    with(&|e: &Rc<Editor>| *found.borrow_mut() = Some(e.clone()));
    found.into_inner()
}

fn icon_button(icon: Icon, tooltip: &str) -> gtk::Button {
    gtk::Button::builder().child(&icons::widget(icon, 18)).tooltip_text(tooltip).focus_on_click(false).css_classes(["tool"]).build()
}

fn separator() -> gtk::Separator {
    gtk::Separator::builder().orientation(gtk::Orientation::Vertical).margin_start(6).margin_end(6).margin_top(8).margin_bottom(8).build()
}

/// The macOS editor's dark chrome (`Theme.chrome`), whatever the system theme.
fn install_css() {
    thread_local!(static DONE: Cell<bool> = const { Cell::new(false) });
    if DONE.replace(true) {
        return;
    }
    let css = gtk::CssProvider::new();
    css.load_from_string(
        "window.shortty-editor, window.shortty-editor headerbar { background: #2A2A2E; color: rgba(255,255,255,0.85); box-shadow: none; }
         window.shortty-editor headerbar { min-height: 40px; border-bottom: 1px solid rgba(0,0,0,0.35); }
         .shortty-editor .tool { min-width: 28px; min-height: 28px; padding: 0; margin: 0 1px; border-radius: 7px; background: none; box-shadow: none; }
         .shortty-editor .swatch > button { min-width: 28px; min-height: 28px; padding: 0; background: none; box-shadow: none; border-radius: 7px; }
         .shortty-editor .swatch > button:hover { background: rgba(255,255,255,0.08); }
         .shortty-editor .tool:hover { background: rgba(255,255,255,0.08); }
         .shortty-editor .tool:checked { background: rgba(255,255,255,0.16); }
         .shortty-editor .keycap { font-size: 8px; font-weight: 800; color: white; background: rgba(0,0,0,0.75); border-radius: 3px; padding: 0 2px; margin: -4px -6px; }
         .shortty-editor .stat { font-weight: 600; font-size: 11px; font-feature-settings: 'tnum'; }
         .shortty-editor .stat-caption { font-size: 9px; opacity: 0.55; }
         .shortty-editor headerbar > windowhandle > box > box.end > box { margin-left: 14px; }
         .shortty-editor .options { background: rgba(30,30,33,0.94); border-radius: 10px; padding: 6px 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.4); }
         .shortty-editor .strip { background: #232326; border-top: 1px solid rgba(0,0,0,0.35); }
         .shortty-editor .strip-header { font-size: 12px; font-weight: 600; padding: 4px 10px; border-radius: 0; }
         .shortty-editor .strip-header .chevron { transition: transform 150ms; }
         .shortty-editor .strip-header.open .chevron { transform: rotate(180deg); }
         .shortty-editor .thumb-button { padding: 2px; }
         .shortty-editor .thumb-date { font-size: 10px; opacity: 0.6; }
         .shortty-editor .thumb-close { min-width: 18px; min-height: 18px; padding: 0; margin: 4px; border-radius: 9px; background: rgba(0,0,0,0.75); color: white; }
         .shortty-editor .dot { padding: 2px; min-width: 0; min-height: 0; }
         .shortty-editor .hint { font-size: 12px; opacity: 0.85; }",
    );
    gtk::style_context_add_provider_for_display(&gdk::Display::default().unwrap(), &css, gtk::STYLE_PROVIDER_PRIORITY_APPLICATION);
}

#[cfg(test)]
mod tests {
    use super::*;
    use gtk::cairo;

    fn press_drag_release(editor: &Rc<Editor>, from: Point, to: Point, shift: bool) {
        let (x, y) = editor.to_view(from);
        let (x1, y1) = editor.to_view(to);
        editor.press(x, y);
        editor.drag_to((x + x1) / 2.0, (y + y1) / 2.0, false, false);
        editor.drag_to(x1, y1, shift, false);
        editor.hover(x1, y1);
        editor.release();
    }

    fn draw(editor: &Rc<Editor>) {
        let surface = cairo::ImageSurface::create(cairo::Format::ARgb32, 800, 600).unwrap();
        editor.draw(&cairo::Context::new(&surface).unwrap(), 800.0, 600.0);
    }

    /// Drives the real editor like a mouse would: every tool draws, then shapes are moved, resized, cropped and
    /// measured. A borrow taken twice aborts the app, so this runs each path once (needs a display; skipped without).
    #[test]
    fn every_tool_works_in_the_real_editor() {
        if gtk::init().is_err() {
            return;
        }
        let image = cairo::ImageSurface::create(cairo::Format::ARgb32, 400, 300).unwrap();
        let editor = Editor::build(Model::new(image, None));
        EDITOR.with_borrow_mut(|e| *e = Some(editor.clone()));
        let p = Point::new;
        let drawing = [Tool::Pencil, Tool::Arrow, Tool::Rectangle, Tool::Ellipse, Tool::Step, Tool::Magnifier, Tool::Blur, Tool::Spotlight];
        for (i, tool) in drawing.into_iter().enumerate() {
            editor.model.borrow_mut().set_tool(tool);
            let y = 20.0 + i as f64 * 30.0;
            press_drag_release(&editor, p(20.0, y), p(90.0, y + 25.0), i % 2 == 0);
            draw(&editor);
        }
        assert_eq!(editor.model.borrow().annotations.len(), drawing.len(), "one annotation per drawing tool");

        // Text: click, type, finish; Select: move, resize by a handle, drag-select.
        editor.model.borrow_mut().set_tool(Tool::Text);
        press_drag_release(&editor, p(200.0, 200.0), p(200.0, 200.0), false);
        editor.im.emit_by_name::<()>("commit", &[&"Hola ñá"]);
        draw(&editor);
        editor.end_editing();
        assert_eq!(editor.model.borrow().annotations.len(), drawing.len() + 1);
        editor.model.borrow_mut().set_tool(Tool::Select);
        press_drag_release(&editor, p(25.0, 80.0), p(45.0, 90.0), true); // the rectangle's edge
        let corner = editor.model.borrow().selected().map(|a| p(a.bounds().max_x(), a.bounds().max_y()));
        if let Some(corner) = corner {
            press_drag_release(&editor, corner, p(corner.x + 30.0, corner.y + 20.0), true);
        }
        press_drag_release(&editor, p(-20.0, -20.0), p(390.0, 290.0), false);
        draw(&editor);
        editor.model.borrow_mut().duplicate_picked();
        editor.model.borrow_mut().undo();

        // Crop: drag a box, move it, apply; Ruler: measure.
        editor.model.borrow_mut().set_tool(Tool::Crop);
        press_drag_release(&editor, p(10.0, 10.0), p(200.0, 150.0), false);
        press_drag_release(&editor, p(100.0, 100.0), p(120.0, 110.0), false);
        draw(&editor);
        editor.apply_crop();
        assert!(editor.model.borrow().crop.is_some());
        editor.model.borrow_mut().set_tool(Tool::Ruler);
        let (x, y) = editor.to_view(p(50.0, 50.0));
        editor.hover(x, y);
        draw(&editor);
        editor.model.borrow_mut().undo();
        assert!(editor.model.borrow().crop.is_none());
        EDITOR.with_borrow_mut(|e| *e = None);
    }
}
