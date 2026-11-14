//! The picture: zoom, drawing it with the annotations and handles, and the mouse (pick, draw, move, resize, crop,
//! measure).

use super::annotation::{Annotation, Shape, Tool, drag_rect};
use super::arrow::Curve;
use super::effects::{self, magnifier_target};
use super::text::{self, TextStyle};
use super::{Editor, draw};
use crate::geometry::{Point, Rect};
use crate::settings::ACCENT;
use gtk::{cairo, gdk, pango, prelude::*};
use std::rc::Rc;

/// Space around the picture, in view points.
const MARGIN: f64 = 24.0;
/// How close a click must be to a line or handle, in view points.
const REACH: f64 = 6.0;
const HANDLE: f64 = 8.0;
/// The box handles' corners: top-left, top-right, bottom-right, bottom-left.
const CORNERS: [usize; 4] = [0, 2, 4, 6];

/// What a mouse drag is doing.
pub enum Drag {
    None,
    /// A new shape from `start`; `before` is the list without it, for one undo step.
    Drawing {
        id: u64,
        start: Point,
        before: Vec<Annotation>,
    },
    Moving {
        start: Point,
        originals: Vec<Annotation>,
        before: Vec<Annotation>,
    },
    /// One lens of a magnifier: the enlarged copy (`target`) or the area it shows.
    MovingLens {
        original: Annotation,
        target: bool,
        start: Point,
        before: Vec<Annotation>,
    },
    Resizing {
        handle: Handle,
        original: Annotation,
        before: Vec<Annotation>,
    },
    RubberBand {
        start: Point,
        current: Point,
    },
    Cropping {
        start: Point,
    },
    CropResize {
        crop: Rect,
        handle: usize,
    },
    CropMove {
        crop: Rect,
        start: Point,
    },
}

#[derive(Clone, Copy, PartialEq)]
pub enum Handle {
    /// 0 top-left, then clockwise: top, top-right, right, bottom-right, bottom, bottom-left, left.
    Box(usize),
    ArrowStart,
    ArrowEnd,
    ArrowMiddle,
    TextPointer,
    StepTip,
    MagnifierSource(usize),
    MagnifierTarget(usize),
}

/// Which runs the ruler shows: holding 1 or 2 picks one.
#[derive(Clone, Copy, PartialEq)]
pub enum RulerAxes {
    Both,
    Horizontal,
    Vertical,
}

impl Editor {
    /// What's shown: the crop, or the image plus anything drawn past its edges. Kept still while a drag or typing
    /// is going on, so nothing jumps under the pointer.
    pub fn canvas(&self) -> Rect {
        self.frozen.get().unwrap_or_else(|| self.model.borrow().content_rect())
    }

    /// View points per image pixel.
    pub fn scale(&self) -> f64 {
        let factor = self.area.scale_factor() as f64;
        if let Some(zoom) = self.model.borrow().zoom {
            return zoom / factor;
        }
        let c = self.canvas();
        let (w, h) = (self.scrolled.width() as f64, self.scrolled.height() as f64);
        ((w - 2.0 * MARGIN) / c.width).min((h - 2.0 * MARGIN) / c.height).min(1.0 / factor).max(0.02)
    }

    /// Where the canvas's top-left corner sits in the view.
    fn origin(&self) -> (f64, f64) {
        let (c, s) = (self.canvas(), self.scale());
        let (w, h) = (self.area.width() as f64, self.area.height() as f64);
        (((w - c.width * s) / 2.0).max(MARGIN), ((h - c.height * s) / 2.0).max(MARGIN))
    }

    pub fn to_image(&self, x: f64, y: f64) -> Point {
        let (c, s, (ox, oy)) = (self.canvas(), self.scale(), self.origin());
        Point::new((x - ox) / s + c.x, (y - oy) / s + c.y)
    }

    pub fn to_view(&self, p: Point) -> (f64, f64) {
        let (c, s, (ox, oy)) = (self.canvas(), self.scale(), self.origin());
        ((p.x - c.x) * s + ox, (p.y - c.y) * s + oy)
    }

    fn view_rect(&self, r: Rect) -> Rect {
        let (x0, y0) = self.to_view(r.origin());
        let (x1, y1) = self.to_view(Point::new(r.max_x(), r.max_y()));
        Rect::new(x0, y0, x1 - x0, y1 - y0)
    }

    /// Sizes the drawing area: the window's size when fitting, the zoomed canvas otherwise (then it scrolls).
    pub fn relayout(&self) {
        let zoomed = self.model.borrow().zoom.is_some();
        let (c, s) = (self.canvas(), self.scale());
        let size = |v: f64| if zoomed { (v * s + 2.0 * MARGIN).ceil() as i32 } else { 0 };
        self.area.set_content_width(size(c.width));
        self.area.set_content_height(size(c.height));
        self.area.queue_draw();
    }

    pub fn draw(&self, cr: &cairo::Context, width: f64, height: f64) {
        checkerboard(cr, width, height);
        let (c, s, (ox, oy)) = (self.canvas(), self.scale(), self.origin());
        let m = self.model.borrow();
        cr.save().ok();
        cr.translate(ox, oy);
        cr.scale(s, s);
        cr.translate(-c.x, -c.y);
        cr.rectangle(c.x, c.y, c.width, c.height);
        cr.clip();
        let image = Rect::new(0.0, 0.0, m.image.width() as f64, m.image.height() as f64);
        if !image.contains_rect(c) {
            let (r, g, b) = self.edge.get().floats(); // what an export fills the grown area with
            cr.set_source_rgb(r, g, b);
            let _ = cr.paint();
        }
        let _ = cr.set_source_surface(&m.image, 0.0, 0.0);
        let sharp = s * self.area.scale_factor() as f64 >= 1.0; // zoomed in: show the pixels
        cr.source().set_filter(if sharp { cairo::Filter::Nearest } else { cairo::Filter::Good });
        cr.rectangle(0.0, 0.0, image.width, image.height);
        let _ = cr.fill();
        draw::annotations(cr, &m.image, m.content_rect(), &m.annotations, m.editing);
        cr.restore().ok();

        // Selection, in view points so handles keep their size at any zoom.
        for a in m.annotations.iter().filter(|a| m.group.contains(&a.id)) {
            outline(cr, self.view_rect(a.bounds()));
        }
        if let Some(a) = m.selected() {
            if a.uses_box_handles() || matches!(a.shape, Shape::Text { .. } | Shape::Step { .. }) {
                outline(cr, self.view_rect(if let Some(t) = a.text_box() { t.frame } else { a.bounds() }));
            }
            let square = a.uses_box_handles() || matches!(a.shape, Shape::Magnifier { .. });
            for (_, p) in handles(a) {
                handle(cr, self.to_view(p), square);
            }
        }
        let (ar, ag, ab) = ACCENT;
        if let Drag::RubberBand { start, current } = *self.drag.borrow() {
            let r = self.view_rect(Rect::between(start, current));
            cr.rectangle(r.x, r.y, r.width, r.height);
            cr.set_source_rgba(ar, ag, ab, 0.12);
            let _ = cr.fill_preserve();
            cr.set_source_rgb(ar, ag, ab);
            cr.set_line_width(1.0);
            let _ = cr.stroke();
        }
        if let (Tool::Crop, Some(crop)) = (m.tool, m.crop_box) {
            self.draw_crop_box(cr, crop, width, height);
        }
        if let (Tool::Ruler, Some(p)) = (m.tool, self.ruler_point.get()) {
            drop(m);
            return self.draw_ruler(cr, p);
        }
        // The caret after the last letter of the text being typed.
        let Some(a) = m.editing.and_then(|id| m.index(id)).map(|i| &m.annotations[i]) else { return };
        let (Some(t), Shape::Text { style, .. }) = (a.text_box(), &a.shape) else { return };
        let (top, bottom) = t.caret();
        let ((x, y0), (_, y1)) = (self.to_view(top), self.to_view(bottom));
        let (r, g, b) = text::text_color(*style, a.color).floats();
        cr.set_source_rgb(r, g, b);
        cr.set_line_width(2.0);
        cr.move_to(x.round(), y0);
        cr.line_to(x.round(), y1);
        let _ = cr.stroke();
    }

    /// Crop tool: everything outside the box dimmed, a dashed outline, handles and the resulting size.
    fn draw_crop_box(&self, cr: &cairo::Context, crop: Rect, width: f64, height: f64) {
        let r = self.view_rect(crop);
        cr.rectangle(0.0, 0.0, width, height);
        cr.rectangle(r.x, r.y, r.width, r.height);
        cr.set_fill_rule(cairo::FillRule::EvenOdd);
        cr.set_source_rgba(0.0, 0.0, 0.0, 0.5);
        let _ = cr.fill();
        cr.set_fill_rule(cairo::FillRule::Winding);
        cr.set_source_rgb(1.0, 1.0, 1.0);
        cr.set_line_width(1.0);
        cr.set_dash(&[6.0, 4.0], 0.0);
        cr.rectangle(r.x.round() + 0.5, r.y.round() + 0.5, r.width.round(), r.height.round());
        let _ = cr.stroke();
        cr.set_dash(&[], 0.0);
        for (_, p) in box_handles(crop) {
            handle(cr, self.to_view(p), true);
        }
        let label = format!("{} × {}", crop.width.round(), crop.height.round());
        pill(cr, &self.area, &label, |w, _| (r.max_x() - w, r.max_y() + 10.0));
    }

    /// Ruler: lines along the runs of same-colored pixels through the pointer, and their lengths beside it.
    fn draw_ruler(&self, cr: &cairo::Context, p: Point) {
        let m = self.model.borrow();
        let image = &m.image;
        let (w, h, stride) = (image.width() as usize, image.height() as usize, image.stride() as usize);
        let axes = self.ruler_axes.get();
        let (mut across, mut down) = (None, None);
        let _ = image.with_data(|pixels| {
            if axes != RulerAxes::Vertical {
                across = effects::ruler_run(pixels, w, h, stride, p, true);
            }
            if axes != RulerAxes::Horizontal {
                down = effects::ruler_run(pixels, w, h, stride, p, false);
            }
        });
        if across.is_none() && down.is_none() {
            return;
        }
        let center = Point::new(p.x.floor() + 0.5, p.y.floor() + 0.5);
        let (ar, ag, ab) = ACCENT;
        cr.set_source_rgb(ar, ag, ab);
        cr.set_line_width(1.0);
        let tick = 4.0;
        if let Some((low, high)) = across {
            let ((x0, y), (x1, _)) = (self.to_view(Point::new(low as f64, center.y)), self.to_view(Point::new(high as f64, center.y)));
            cr.move_to(x0, y);
            cr.line_to(x1, y);
            for x in [x0, x1] {
                cr.move_to(x, y - tick);
                cr.line_to(x, y + tick);
            }
        }
        if let Some((low, high)) = down {
            let ((x, y0), (_, y1)) = (self.to_view(Point::new(center.x, low as f64)), self.to_view(Point::new(center.x, high as f64)));
            cr.move_to(x, y0);
            cr.line_to(x, y1);
            for y in [y0, y1] {
                cr.move_to(x - tick, y);
                cr.line_to(x + tick, y);
            }
        }
        let _ = cr.stroke();
        let label = [across, down].iter().flatten().map(|(low, high)| (high - low).to_string()).collect::<Vec<_>>().join(" × ") + " px";
        let (x, y) = self.to_view(center);
        pill(cr, &self.area, &label, |_, _| (x + 10.0, y + 10.0));
    }

    /// The selected annotation's handle under a view point.
    fn handle_at(&self, x: f64, y: f64) -> Option<Handle> {
        let m = self.model.borrow();
        let a = m.selected()?;
        handles(a).into_iter().find_map(|(handle, p)| {
            let (hx, hy) = self.to_view(p);
            ((hx - x).abs() <= HANDLE && (hy - y).abs() <= HANDLE).then_some(handle)
        })
    }

    /// The topmost annotation under an image point.
    fn hit(&self, p: Point) -> Option<u64> {
        let tolerance = REACH / self.scale();
        self.model.borrow().annotations.iter().rev().find(|a| a.contains(p, tolerance)).map(|a| a.id)
    }

    fn hit_tool(&self, p: Point) -> Option<(u64, Tool)> {
        let id = self.hit(p)?;
        let m = self.model.borrow();
        Some((id, m.annotations[m.index(id)?].tool()))
    }

    // MARK: Mouse

    pub fn press(self: &Rc<Self>, x: f64, y: f64) {
        self.area.grab_focus();
        let p = self.to_image(x, y);
        let editing = self.model.borrow().editing;
        if let Some(id) = editing {
            let inside = {
                let m = self.model.borrow();
                m.index(id).and_then(|i| m.annotations[i].text_box()).is_some_and(|t| t.frame.contains(p))
            };
            if inside {
                return; // keep typing (the caret stays at the end)
            }
            self.end_editing();
        }
        let tool = self.model.borrow().tool;
        if tool == Tool::Ruler {
            return; // the ruler only measures
        }
        if tool == Tool::Crop {
            let drag = self.crop_drag(x, y, p);
            return self.start_drag(drag);
        }
        let before = self.model.borrow().annotations.clone();
        if let Some(handle) = self.handle_at(x, y) {
            let original = self.model.borrow().selected().unwrap().clone();
            return self.start_drag(Drag::Resizing { handle, original, before });
        }
        let hit = self.hit_tool(p);
        let selected = self.model.borrow().selection;
        // An existing step or text, or the effect just drawn (it stays selected): dragging moves it instead of adding another.
        let moves_existing = hit.is_some_and(|(id, kind)| {
            kind == tool
                && (matches!(kind, Tool::Step) || Some(id) == selected && matches!(kind, Tool::Magnifier | Tool::Blur | Tool::Spotlight))
        });
        match tool {
            Tool::Select => match hit {
                Some((id, _)) => {
                    let in_group = self.model.borrow().group.contains(&id);
                    if !in_group {
                        self.model.borrow_mut().select(Some(id));
                    }
                    self.start_move(p, before);
                }
                None => {
                    self.model.borrow_mut().select(None);
                    self.start_drag(Drag::RubberBand { start: p, current: p });
                }
            },
            _ if moves_existing => {
                self.model.borrow_mut().select(hit.map(|(id, _)| id));
                self.start_move(p, before);
            }
            Tool::Text => match hit.filter(|(_, kind)| *kind == Tool::Text) {
                Some((id, _)) => self.begin_editing(id),
                None => {
                    let id = self.new_text(p);
                    self.start_drag(Drag::Drawing { id, start: p, before });
                }
            },
            _ => {
                let m = self.model.borrow();
                let r = Rect::new(p.x, p.y, 0.0, 0.0);
                let shape = match tool {
                    Tool::Pencil => Shape::Stroke { points: vec![p] },
                    Tool::Arrow => Shape::Arrow { start: p, end: p, bend: 0.0, style: m.arrow_style },
                    Tool::Rectangle => Shape::Rectangle { rect: r },
                    Tool::Ellipse => Shape::Ellipse { rect: r },
                    Tool::Blur => Shape::Redact { rect: r, style: m.redact_style, text_boxes: vec![] },
                    Tool::Spotlight => Shape::Spotlight { rect: r, shape: m.spotlight_shape },
                    Tool::Magnifier => Shape::Magnifier { source: r, target: r, shape: m.magnifier_shape },
                    _ => Shape::Step { center: p, tip: None }, // dragging before letting go pulls out a pointer
                };
                let annotation = Annotation::new(shape, m.color, m.width(tool));
                drop(m);
                let id = annotation.id;
                let mut m = self.model.borrow_mut();
                m.select(None);
                m.annotations.push(annotation);
                drop(m);
                self.start_drag(Drag::Drawing { id, start: p, before });
            }
        }
        self.changed();
    }

    /// Moving what's picked; a magnifier moves only the lens under the pointer.
    fn start_move(&self, p: Point, before: Vec<Annotation>) {
        let picked = self.model.borrow().picked();
        let original = self.model.borrow().selected().cloned();
        if let Some(original) = original.filter(|a| a.tool() == Tool::Magnifier) {
            let Shape::Magnifier { target, .. } = original.shape else { unreachable!() };
            let target = target.standardized().contains(p);
            return self.start_drag(Drag::MovingLens { original, target, start: p, before });
        }
        let originals = before.iter().filter(|a| picked.contains(&a.id)).cloned().collect();
        self.start_drag(Drag::Moving { start: p, originals, before });
    }

    /// Crop tool: grab a handle of the box, move the box, or drag out a new one.
    fn crop_drag(&self, x: f64, y: f64, p: Point) -> Drag {
        if let Some(crop) = self.model.borrow().crop_box.map(Rect::standardized) {
            let near = box_handles(crop).into_iter().find(|(_, h)| {
                let (hx, hy) = self.to_view(*h);
                (hx - x).abs() <= HANDLE && (hy - y).abs() <= HANDLE
            });
            if let Some((handle, _)) = near {
                return Drag::CropResize { crop, handle };
            }
            if crop.contains(p) {
                return Drag::CropMove { crop, start: p };
            }
        }
        Drag::Cropping { start: p }
    }

    fn start_drag(&self, drag: Drag) {
        self.frozen.set(Some(self.canvas()));
        *self.drag.borrow_mut() = drag;
        self.area.queue_draw();
    }

    pub fn drag_to(&self, x: f64, y: f64, shift: bool, ctrl: bool) {
        let p = self.to_image(x, y);
        // Read before the model is borrowed for writing: `scale` reads it too, and a second borrow aborts.
        let scale = self.scale();
        let mut drag = self.drag.borrow_mut();
        let mut m = self.model.borrow_mut();
        let content = m.content_rect();
        let bounds = Rect::new(0.0, 0.0, m.image.width() as f64, m.image.height() as f64);
        match &mut *drag {
            Drag::None => return,
            Drag::RubberBand { current, .. } => *current = p,
            Drag::Cropping { start } => m.crop_box = drag_rect(*start, p, shift).intersection(content),
            Drag::CropResize { crop, handle } => m.crop_box = resize_box(*crop, *handle, p, shift).standardized().intersection(content),
            Drag::CropMove { crop, start } => {
                // Slide the box, kept inside the picture.
                let mut moved = Rect::new(crop.x + p.x - start.x, crop.y + p.y - start.y, crop.width, crop.height);
                moved.x = moved.x.min(content.max_x() - moved.width).max(content.x);
                moved.y = moved.y.min(content.max_y() - moved.height).max(content.y);
                m.crop_box = Some(moved);
            }
            Drag::Drawing { id, start, .. } => {
                let (id, start) = (*id, *start);
                let Some(i) = m.index(id) else { return };
                let min_step = 0.5 / scale;
                let width = m.annotations[i].width;
                match &mut m.annotations[i].shape {
                    Shape::Stroke { points } => {
                        if shift {
                            // Shift: a straight line; with Ctrl too, in 45° steps.
                            *points = vec![start, if ctrl { snap45(start, p) } else { p }];
                        } else if points.last().is_none_or(|last| last.distance(p) >= min_step) {
                            points.push(p);
                        }
                    }
                    Shape::Arrow { end, .. } => *end = if shift { snap45(start, p) } else { p },
                    Shape::Rectangle { rect } | Shape::Ellipse { rect } => *rect = drag_rect(start, p, shift),
                    Shape::Redact { rect, .. } | Shape::Spotlight { rect, .. } => *rect = drag_rect(start, p, shift),
                    Shape::Magnifier { source, target, .. } => {
                        *source = drag_rect(start, p, shift);
                        *target = magnifier_target(*source, bounds);
                    }
                    // Only a real drag aims it; a click keeps the default corner pointer.
                    Shape::Step { center, tip } => *tip = (p.distance(*center) > width / 2.0).then_some(p),
                    Shape::Text { pointer, style, .. } => {
                        // Dragging from where the text goes aims a callout at what it points to.
                        if *style == TextStyle::Callout && start.distance(p) * scale > 8.0 {
                            *pointer = p;
                        }
                    }
                }
            }
            Drag::Moving { start, originals, .. } => {
                let (dx, dy) = lock_axis(p.x - start.x, p.y - start.y, shift);
                for original in originals.iter() {
                    if let Some(i) = m.index(original.id) {
                        m.annotations[i] = original.moved(dx, dy);
                    }
                }
            }
            Drag::MovingLens { original, target: moving_target, start, .. } => {
                let (dx, dy) = lock_axis(p.x - start.x, p.y - start.y, shift);
                let Some(i) = m.index(original.id) else { return };
                if let Shape::Magnifier { source, target, shape } = original.shape {
                    let shift_rect = |r: Rect| Rect::new(r.x + dx, r.y + dy, r.width, r.height);
                    let (source, target) = if *moving_target { (source, shift_rect(target)) } else { (shift_rect(source), target) };
                    m.annotations[i].shape = Shape::Magnifier { source, target, shape };
                }
            }
            Drag::Resizing { handle, original, .. } => {
                let Some(i) = m.index(original.id) else { return };
                m.annotations[i] = resized(original, *handle, p, shift);
            }
        }
        drop(m);
        drop(drag);
        self.area.queue_draw();
    }

    pub fn release(self: &Rc<Self>) {
        let drag = std::mem::replace(&mut *self.drag.borrow_mut(), Drag::None);
        let mut m = self.model.borrow_mut();
        match drag {
            Drag::None => {}
            Drag::Cropping { .. } | Drag::CropResize { .. } | Drag::CropMove { .. } => {
                if m.crop_box.is_some_and(|b| b.width < 4.0 || b.height < 4.0) {
                    m.crop_box = None;
                }
            }
            Drag::Drawing { id, before, .. } => {
                if m.editing == Some(id) {
                    // New text: typing goes on; its undo step is recorded when typing ends.
                } else if m.index(id).is_some_and(|i| m.annotations[i].is_degenerate()) {
                    m.annotations.retain(|a| a.id != id);
                } else {
                    m.record_change(before);
                    // Shapes, arrows, steps and effects stay selected to adjust right away; pencil lines don't.
                    let pencil = m.index(id).is_some_and(|i| m.annotations[i].tool() == Tool::Pencil);
                    m.select(if pencil { None } else { Some(id) });
                }
            }
            Drag::Moving { before, .. } | Drag::MovingLens { before, .. } | Drag::Resizing { before, .. } => {
                if m.annotations != before {
                    m.record_change(before);
                }
            }
            Drag::RubberBand { start, current } => {
                let area = Rect::between(start, current);
                let inside: Vec<u64> = m.annotations.iter().filter(|a| area.contains_rect(a.bounds())).map(|a| a.id).collect();
                if !inside.is_empty() {
                    m.pick(inside);
                }
            }
        }
        drop(m);
        if self.model.borrow().editing.is_none() {
            self.frozen.set(None);
        }
        self.relayout();
        self.changed();
    }

    /// Select tool: double-click text to edit it, or empty space to start new text.
    pub fn double_click(self: &Rc<Self>, x: f64, y: f64) {
        if self.model.borrow().tool != Tool::Select {
            return;
        }
        let p = self.to_image(x, y);
        match self.hit_tool(p) {
            Some((id, Tool::Text)) => self.begin_editing(id),
            None => {
                *self.drag.borrow_mut() = Drag::None;
                self.new_text(p);
            }
            Some(_) => {}
        }
        self.changed();
    }

    /// New text with the caret where the click was, typing into it right away.
    fn new_text(self: &Rc<Self>, p: Point) -> u64 {
        let mut m = self.model.borrow_mut();
        let (size, style, color) = (m.width(Tool::Text), m.text_style, m.color);
        let (px, py) = text::padding(style, size);
        let origin = Point::new(p.x - px, p.y - py - size * 0.6);
        let empty = text::TextBox::new(origin, "", style, origin, size, color).frame;
        let shape = Shape::Text { origin, string: String::new(), style, pointer: text::default_pointer(empty, size) };
        let annotation = Annotation::new(shape, color, size);
        let id = annotation.id;
        m.start_text(annotation);
        drop(m);
        self.frozen.set(Some(self.canvas()));
        self.im.focus_in();
        id
    }

    pub fn begin_editing(&self, id: u64) {
        self.model.borrow_mut().begin_editing(id);
        self.frozen.set(Some(self.canvas()));
        self.im.focus_in();
        self.area.queue_draw();
    }

    pub fn end_editing(&self) {
        if self.model.borrow().editing.is_none() {
            return;
        }
        self.im.focus_out();
        self.im.reset();
        self.model.borrow_mut().end_editing();
        self.frozen.set(None);
        self.relayout();
    }

    /// The pointer's look, and the ruler's measuring point.
    pub fn hover(&self, x: f64, y: f64) {
        let tool = self.model.borrow().tool;
        if tool == Tool::Ruler {
            self.ruler_point.set(Some(self.to_image(x, y)));
            self.area.queue_draw();
        }
        let name = if self.handle_at(x, y).is_some() {
            "move"
        } else {
            match tool {
                Tool::Select if self.hit(self.to_image(x, y)).is_some() => "move",
                Tool::Select => "default",
                Tool::Text => "text",
                _ => "crosshair",
            }
        };
        self.area.set_cursor(gdk::Cursor::from_name(name, None).as_ref());
    }
}

/// Where an annotation's handles are, in image pixels.
fn handles(a: &Annotation) -> Vec<(Handle, Point)> {
    match &a.shape {
        Shape::Arrow { start, end, bend, .. } => {
            vec![(Handle::ArrowStart, *start), (Handle::ArrowEnd, *end), (Handle::ArrowMiddle, Curve::new(*start, *end, *bend).middle())]
        }
        Shape::Text { style: TextStyle::Callout, pointer, .. } => vec![(Handle::TextPointer, *pointer)],
        Shape::Text { .. } => vec![],
        Shape::Step { center, .. } => vec![(Handle::StepTip, a.step_tip().unwrap_or(center.offset(a.width * 0.4, a.width * 0.4)))],
        Shape::Magnifier { source, target, .. } => {
            let corners = |r: Rect, lens: fn(usize) -> Handle| {
                box_handles(r.standardized()).into_iter().filter(|(i, _)| CORNERS.contains(i)).map(move |(i, p)| (lens(i), p))
            };
            corners(*source, Handle::MagnifierSource).chain(corners(*target, Handle::MagnifierTarget)).collect()
        }
        _ => box_handles(a.bounds()).into_iter().map(|(i, p)| (Handle::Box(i), p)).collect(),
    }
}

/// The 8 handles around a box: corners and edge middles, clockwise from the top-left.
fn box_handles(b: Rect) -> Vec<(usize, Point)> {
    let (x0, xm, x1, y0, ym, y1) = (b.x, b.mid().x, b.max_x(), b.y, b.mid().y, b.max_y());
    [(x0, y0), (xm, y0), (x1, y0), (x1, ym), (x1, y1), (xm, y1), (x0, y1), (x0, ym)]
        .into_iter()
        .enumerate()
        .map(|(i, (x, y))| (i, Point::new(x, y)))
        .collect()
}

/// `old` with handle `i` dragged to `p`, possibly mirrored (negative size). `keep_aspect`: corners keep the proportions.
fn resize_box(old: Rect, i: usize, p: Point, keep_aspect: bool) -> Rect {
    let (mut x0, mut y0, mut x1, mut y1) = (old.x, old.y, old.max_x(), old.max_y());
    match i {
        0 => (x0, y0) = (p.x, p.y),
        1 => y0 = p.y,
        2 => (x1, y0) = (p.x, p.y),
        3 => x1 = p.x,
        4 => (x1, y1) = (p.x, p.y),
        5 => y1 = p.y,
        6 => (x0, y1) = (p.x, p.y),
        _ => x0 = p.x,
    }
    if keep_aspect && i.is_multiple_of(2) && old.width > 0.0 && old.height > 0.0 {
        // Follow the larger change, anchored at the opposite corner.
        let (w, h) = (x1 - x0, y1 - y0);
        let factor = (w / old.width).abs().max((h / old.height).abs());
        let (w, h) = (old.width * factor * w.signum(), old.height * factor * h.signum());
        if matches!(i, 0 | 6) {
            x0 = x1 - w
        } else {
            x1 = x0 + w
        }
        if matches!(i, 0 | 2) { y0 = y1 - h } else { y1 = y0 + h }
    }
    Rect::new(x0, y0, x1 - x0, y1 - y0)
}

/// `original` with one handle dragged to `p`. Shift: corners keep the proportions, the arrow's middle straightens,
/// its ends snap to 45°.
fn resized(original: &Annotation, handle: Handle, p: Point, shift: bool) -> Annotation {
    let mut a = original.clone();
    match (handle, &mut a.shape) {
        (Handle::ArrowStart, Shape::Arrow { start, end, .. }) => *start = if shift { snap45(*end, p) } else { p },
        (Handle::ArrowEnd, Shape::Arrow { start, end, .. }) => *end = if shift { snap45(*start, p) } else { p },
        (Handle::ArrowMiddle, Shape::Arrow { start, end, bend, .. }) => *bend = if shift { 0.0 } else { Curve::bend(p, *start, *end) },
        (Handle::TextPointer, Shape::Text { pointer, .. }) => *pointer = p,
        (Handle::StepTip, Shape::Step { tip, .. }) => *tip = Some(p),
        (Handle::MagnifierSource(i), Shape::Magnifier { source, target, .. }) => {
            // A bigger or smaller area keeps the zoom: the copy grows around its center.
            let (old_source, old_target) = (source.standardized(), target.standardized());
            let zoom = (old_target.width / old_source.width.max(1.0), old_target.height / old_source.height.max(1.0));
            *source = resize_box(old_source, i, p, shift).standardized();
            let mid = old_target.mid();
            let (w, h) = (source.width * zoom.0, source.height * zoom.1);
            *target = Rect::new(mid.x - w / 2.0, mid.y - h / 2.0, w, h);
        }
        // Same area, bigger or smaller copy: the zoom changes, the proportions don't.
        (Handle::MagnifierTarget(i), Shape::Magnifier { target, .. }) => {
            *target = resize_box(target.standardized(), i, p, true).standardized()
        }
        (Handle::Box(i), _) => {
            let old = original.bounds();
            return original.resized(old, resize_box(old, i, p, shift));
        }
        _ => {}
    }
    a
}

fn lock_axis(dx: f64, dy: f64, shift: bool) -> (f64, f64) {
    // Shift moves along one axis.
    match shift {
        true if dx.abs() > dy.abs() => (dx, 0.0),
        true => (0.0, dy),
        false => (dx, dy),
    }
}

/// `p` moved onto the nearest 45° line through `from`, keeping its distance.
fn snap45(from: Point, p: Point) -> Point {
    let (dx, dy) = (p.x - from.x, p.y - from.y);
    let angle = (dy.atan2(dx) / std::f64::consts::FRAC_PI_4).round() * std::f64::consts::FRAC_PI_4;
    let length = dx.hypot(dy);
    Point::new(from.x + length * angle.cos(), from.y + length * angle.sin())
}

fn outline(cr: &cairo::Context, r: Rect) {
    let (ar, ag, ab) = ACCENT;
    cr.set_source_rgb(ar, ag, ab);
    cr.set_line_width(1.0);
    cr.rectangle(r.x.floor() - 3.5, r.y.floor() - 3.5, r.max_x().ceil() - r.x.floor() + 7.0, r.max_y().ceil() - r.y.floor() + 7.0);
    let _ = cr.stroke();
}

fn handle(cr: &cairo::Context, (x, y): (f64, f64), square: bool) {
    if square {
        cr.rectangle(x - HANDLE / 2.0, y - HANDLE / 2.0, HANDLE, HANDLE);
    } else {
        cr.new_sub_path();
        cr.arc(x, y, HANDLE / 2.0 + 1.0, 0.0, std::f64::consts::TAU);
    }
    cr.set_source_rgb(1.0, 1.0, 1.0);
    let _ = cr.fill_preserve();
    let (ar, ag, ab) = ACCENT;
    cr.set_source_rgb(ar, ag, ab);
    cr.set_line_width(1.5);
    let _ = cr.stroke();
}

/// White text on a dark capsule (sizes, the ruler), placed by `place(width, height)`.
fn pill(cr: &cairo::Context, widget: &gtk::DrawingArea, text: &str, place: impl Fn(f64, f64) -> (f64, f64)) {
    let layout = widget.create_pango_layout(Some(text));
    layout.set_font_description(Some(&pango::FontDescription::from_string("Medium 9")));
    let (tw, th) = layout.pixel_size();
    let (w, h) = (tw as f64 + 20.0, th as f64 + 10.0);
    let (x, y) = place(w, h);
    draw::rounded_rect(cr, Rect::new(x, y, w, h), h / 2.0);
    cr.set_source_rgba(0.08, 0.08, 0.08, 0.9);
    let _ = cr.fill();
    cr.set_source_rgb(1.0, 1.0, 1.0);
    cr.move_to(x + 10.0, y + 5.0);
    pangocairo::functions::show_layout(cr, &layout);
}

/// The macOS editor's subtle dark checkerboard behind the picture.
fn checkerboard(cr: &cairo::Context, width: f64, height: f64) {
    let cell = 12.0;
    cr.set_source_rgb(0.17, 0.17, 0.17);
    let _ = cr.paint();
    cr.set_source_rgb(0.20, 0.20, 0.20);
    let (columns, rows) = ((width / cell).ceil() as i32, (height / cell).ceil() as i32);
    for row in 0..rows {
        for column in (row % 2..columns).step_by(2) {
            cr.rectangle(column as f64 * cell, row as f64 * cell, cell, cell);
        }
    }
    let _ = cr.fill();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::editor::annotation::Rgb;
    use crate::editor::effects::AreaShape;

    #[test]
    fn snapping_keeps_length() {
        let p = snap45(Point::new(0.0, 0.0), Point::new(10.0, 1.0));
        assert!((p.x - 10.0499).abs() < 1e-3 && p.y.abs() < 1e-9);
    }

    #[test]
    fn corner_resize_keeps_proportions_with_shift() {
        let a = Annotation::new(Shape::Rectangle { rect: Rect::new(0.0, 0.0, 100.0, 50.0) }, Rgb(0, 0, 0), 4.0);
        let r = resized(&a, Handle::Box(4), Point::new(200.0, 60.0), true);
        assert_eq!(r.bounds(), Rect::new(0.0, 0.0, 200.0, 100.0));
        let free = resized(&a, Handle::Box(3), Point::new(30.0, 999.0), false);
        assert_eq!(free.bounds(), Rect::new(0.0, 0.0, 30.0, 50.0));
    }

    #[test]
    fn magnifier_area_resize_keeps_the_zoom() {
        let shape = Shape::Magnifier {
            source: Rect::new(0.0, 0.0, 10.0, 10.0),
            target: Rect::new(40.0, 0.0, 20.0, 20.0),
            shape: AreaShape::Ellipse {},
        };
        let a = Annotation::new(shape, Rgb(0, 0, 0), 4.0);
        let r = resized(&a, Handle::MagnifierSource(4), Point::new(20.0, 20.0), false);
        let Shape::Magnifier { source, target, .. } = r.shape else { panic!() };
        assert_eq!(source, Rect::new(0.0, 0.0, 20.0, 20.0));
        assert_eq!(target, Rect::new(30.0, -10.0, 40.0, 40.0));
    }
}
