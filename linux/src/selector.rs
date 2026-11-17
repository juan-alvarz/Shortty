use crate::{
    capture,
    geometry::{self, Rect},
};
use gtk::{cairo, gdk, glib, pango, prelude::*};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use std::{
    cell::{Cell, RefCell},
    rc::Rc,
};

type Finish = Rc<dyn Fn(Option<Picked>)>;

/// An area dragged over one output's frozen picture.
pub struct Picked {
    pub monitor: gdk::Monitor,
    shot: gdk::Texture,
    /// In the output's logical points, from its top-left corner.
    rect: Rect,
    /// The output's size in logical points (the overlay covers it).
    view: (f64, f64),
}

impl Picked {
    /// The area's pixels from the frozen picture.
    pub fn cropped(&self) -> gdk::Texture {
        crop(&self.shot, self.rect.pixels(self.view, (self.shot.width() as u32, self.shot.height() as u32)))
    }

    /// The area in the layout's logical coordinates, as `grim -g` takes it, to capture it again later (lazy shots).
    pub fn rect_in_layout(&self) -> Rect {
        let g = self.monitor.geometry();
        Rect::new(g.x() as f64 + self.rect.x, g.y() as f64 + self.rect.y, self.rect.width, self.rect.height)
    }

    pub fn rect(&self) -> Rect {
        self.rect
    }
}

/// Shared by every output's overlay: Space switches all of them between dragging an area and clicking a window.
struct Mode {
    windows: Cell<bool>,
    /// The windows on screen, topmost first, in the layout's coordinates.
    on_screen: Vec<Rect>,
    areas: RefCell<Vec<gtk::DrawingArea>>,
}

/// Freezes every output, then lets the user drag an area on any of them, or click a window (`windows`, or after
/// Space). None when cancelled with Esc.
pub async fn select(cursor: bool, color: (f64, f64, f64), windows: bool) -> Result<Option<Picked>, String> {
    let display = gdk::Display::default().ok_or("no display")?;
    let monitors: Vec<gdk::Monitor> = display.monitors().iter::<gdk::Monitor>().flatten().collect();
    let mut shots = Vec::new();
    for monitor in &monitors {
        let name = monitor.connector().ok_or("monitor without an output name")?;
        let file = std::env::temp_dir().join(format!("shortty-{name}.png"));
        capture::grim(&["-o", &name], &file, cursor).await?;
        let shot = gdk::Texture::from_filename(&file).map_err(|e| e.to_string());
        let _ = std::fs::remove_file(&file);
        shots.push(shot?);
    }
    let clients = capture::run(&["hyprctl", "-j", "clients"]).await.unwrap_or_default();
    let outputs = capture::run(&["hyprctl", "-j", "monitors"]).await.unwrap_or_default();
    let mode =
        Rc::new(Mode { windows: Cell::new(windows), on_screen: geometry::visible_windows(&clients, &outputs), areas: RefCell::default() });

    let (sender, receiver) = futures_channel::oneshot::channel();
    let sender = RefCell::new(Some(sender));
    let overlays: Rc<RefCell<Vec<gtk::Window>>> = Default::default();
    let finish: Finish = Rc::new({
        let overlays = overlays.clone();
        move |result| {
            overlays.take().iter().for_each(|w| w.destroy());
            if let Some(sender) = sender.take() {
                let _ = sender.send(result);
            }
        }
    });
    for (monitor, shot) in monitors.iter().zip(shots) {
        overlays.borrow_mut().push(overlay(monitor, shot, color, mode.clone(), finish.clone()));
    }
    Ok(receiver.await.ok().flatten())
}

/// One output's frozen picture, full screen above everything, dimmed outside the selection or the window.
fn overlay(monitor: &gdk::Monitor, shot: gdk::Texture, color: (f64, f64, f64), mode: Rc<Mode>, finish: Finish) -> gtk::Window {
    let window = gtk::Window::new();
    window.init_layer_shell();
    window.set_layer(Layer::Overlay);
    window.set_monitor(Some(monitor));
    for edge in [Edge::Left, Edge::Right, Edge::Top, Edge::Bottom] {
        window.set_anchor(edge, true);
    }
    window.set_exclusive_zone(-1);
    window.set_keyboard_mode(KeyboardMode::Exclusive);
    window.set_namespace(Some("shortty-selector"));

    let picture = gtk::Picture::for_paintable(&shot);
    picture.set_content_fit(gtk::ContentFit::Fill);
    picture.set_can_shrink(true);
    let area = gtk::DrawingArea::new();
    area.set_cursor_from_name(Some("crosshair"));
    let stack = gtk::Overlay::new();
    stack.set_child(Some(&picture));
    stack.add_overlay(&area);
    window.set_child(Some(&stack));
    mode.areas.borrow_mut().push(area.clone());

    // In this output's points: the dragged area, or the window under the pointer.
    let selection: Rc<Cell<Option<Rect>>> = Default::default();
    let image = (shot.width() as u32, shot.height() as u32);
    let origin = monitor.geometry();
    area.set_draw_func({
        let (selection, mode) = (selection.clone(), mode.clone());
        move |area, cr, w, h| draw(area, cr, (w as f64, h as f64), selection.get(), image, color, mode.windows.get())
    });
    let pick = {
        let (monitor, selection, area, finish) = (monitor.clone(), selection.clone(), area.clone(), finish.clone());
        move || {
            if let Some(rect) = selection.get().filter(|r| r.width >= 4.0 && r.height >= 4.0) {
                let view = (area.width() as f64, area.height() as f64);
                finish(Some(Picked { monitor: monitor.clone(), shot: shot.clone(), rect, view }));
            } else {
                selection.set(None);
                area.queue_draw(); // a click or a tiny drag: back to the hint
            }
        }
    };

    let drag = gtk::GestureDrag::new();
    drag.connect_drag_update({
        let (selection, area, mode) = (selection.clone(), area.clone(), mode.clone());
        move |gesture, dx, dy| {
            let Some((x, y)) = gesture.start_point().filter(|_| !mode.windows.get()) else { return };
            selection.set(Some(Rect::spanning((x, y), (x + dx, y + dy), area.width() as f64, area.height() as f64)));
            area.queue_draw();
        }
    });
    drag.connect_drag_end({
        let pick = pick.clone();
        move |_, _, _| pick()
    });
    area.add_controller(drag);

    // Window mode: the window under the pointer lights up; a click takes it.
    let motion = gtk::EventControllerMotion::new();
    let hover = Rc::new({
        let (selection, area, mode) = (selection.clone(), area.clone(), mode.clone());
        move |x: f64, y: f64| {
            if !mode.windows.get() {
                return;
            }
            let p = geometry::Point::new(x + origin.x() as f64, y + origin.y() as f64);
            let view = Rect::new(0.0, 0.0, area.width() as f64, area.height() as f64);
            let under = mode
                .on_screen
                .iter()
                .find(|w| w.contains(p))
                .and_then(|w| Rect::new(w.x - origin.x() as f64, w.y - origin.y() as f64, w.width, w.height).intersection(view));
            if under != selection.get() {
                selection.set(under);
                area.queue_draw();
            }
        }
    });
    // Enter comes as the overlay appears under the pointer, so the window there lights up before any movement.
    motion.connect_enter({
        let hover = hover.clone();
        move |_, x, y| hover(x, y)
    });
    motion.connect_motion(move |_, x, y| hover(x, y));
    area.add_controller(motion);
    let click = gtk::GestureClick::new();
    click.connect_released({
        let mode = mode.clone();
        move |_, _, _, _| {
            if mode.windows.get() {
                pick()
            }
        }
    });
    area.add_controller(click);

    let keys = gtk::EventControllerKey::new();
    keys.connect_key_pressed(move |_, key, _, _| match key {
        gdk::Key::Escape => {
            finish(None);
            glib::Propagation::Stop
        }
        gdk::Key::space => {
            // Every output switches; what was picked starts over.
            mode.windows.set(!mode.windows.get());
            selection.set(None);
            for area in mode.areas.borrow().iter() {
                area.queue_draw();
            }
            glib::Propagation::Stop
        }
        _ => glib::Propagation::Proceed,
    });
    window.add_controller(keys);
    window.present();
    window
}

fn draw(
    area: &gtk::DrawingArea,
    cr: &cairo::Context,
    (w, h): (f64, f64),
    selection: Option<Rect>,
    image: (u32, u32),
    color: (f64, f64, f64),
    windows: bool,
) {
    cr.rectangle(0.0, 0.0, w, h);
    if let Some(r) = selection {
        cr.rectangle(r.x, r.y, r.width, r.height);
        cr.set_fill_rule(cairo::FillRule::EvenOdd);
    }
    cr.set_source_rgba(0.0, 0.0, 0.0, 0.35);
    let _ = cr.fill();

    let Some(r) = selection else {
        let hint =
            if windows { "Click a window. Space for an area, Esc cancels." } else { "Drag over an area. Space for a window, Esc cancels." };
        return pill(area, cr, hint, |pw, ph| ((w - pw) / 2.0, (h - ph) / 2.0));
    };
    if windows {
        cr.set_source_rgba(color.0, color.1, color.2, 0.12);
        cr.rectangle(r.x, r.y, r.width, r.height);
        let _ = cr.fill();
    }
    cr.set_source_rgb(color.0, color.1, color.2);
    cr.set_line_width(if windows { 3.0 } else { 1.5 });
    cr.rectangle(r.x - 0.75, r.y - 0.75, r.width + 1.5, r.height + 1.5);
    let _ = cr.stroke();
    let (_, _, pw, ph) = r.pixels((w, h), image);
    pill(area, cr, &format!("{pw} × {ph}"), |size_w, size_h| {
        // Under the bottom-right corner, or inside it when there's no room.
        let below = r.y + r.height + 6.0;
        let y = if below + size_h <= h { below } else { r.y + r.height - size_h - 6.0 };
        ((r.x + r.width - size_w).max(0.0), y)
    });
}

/// White text in GTK's font on a dark capsule, placed by `place(width, height)`.
fn pill(area: &gtk::DrawingArea, cr: &cairo::Context, text: &str, place: impl Fn(f64, f64) -> (f64, f64)) {
    let layout = area.create_pango_layout(Some(text));
    layout.set_font_description(Some(&pango::FontDescription::from_string("Bold 10")));
    let (text_width, text_height) = layout.pixel_size();
    let (width, height) = (text_width as f64 + 18.0, 24.0);
    let (x, y) = place(width, height);
    let radius = height / 2.0;
    cr.new_sub_path();
    cr.arc(x + width - radius, y + radius, radius, -std::f64::consts::FRAC_PI_2, std::f64::consts::FRAC_PI_2);
    cr.arc(x + radius, y + radius, radius, std::f64::consts::FRAC_PI_2, 3.0 * std::f64::consts::FRAC_PI_2);
    cr.close_path();
    cr.set_source_rgba(0.0, 0.0, 0.0, 0.72);
    let _ = cr.fill();
    cr.set_source_rgb(1.0, 1.0, 1.0);
    cr.move_to(x + 9.0, y + (height - text_height as f64) / 2.0);
    pangocairo::functions::show_layout(cr, &layout);
}

/// The `(x, y, width, height)` pixels of a frozen output as a texture of their own.
fn crop(shot: &gdk::Texture, (x, y, w, h): (u32, u32, u32, u32)) -> gdk::Texture {
    let stride = shot.width() as usize * 4;
    let mut data = vec![0; stride * shot.height() as usize];
    shot.download(&mut data, stride); // Cairo's ARGB32: B, G, R, A on little-endian
    let mut cropped = Vec::with_capacity((w * h * 4) as usize);
    for row in y..y + h {
        let start = row as usize * stride + x as usize * 4;
        cropped.extend_from_slice(&data[start..start + w as usize * 4]);
    }
    let bytes = glib::Bytes::from_owned(cropped);
    gdk::MemoryTexture::new(w as i32, h as i32, gdk::MemoryFormat::B8g8r8a8Premultiplied, &bytes, w as usize * 4).upcast()
}
