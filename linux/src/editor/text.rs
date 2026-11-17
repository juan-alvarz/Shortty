//! Text layout, ported from the macOS `Text.swift`. Drawing, hit testing and typing all use it, so text sits in
//! exactly the same place while typing and after.

use super::annotation::Rgb;
use crate::geometry::{Point, Rect};
use gtk::{cairo, pango, prelude::*};
use std::f64::consts::PI;

/// Text looks: a callout (filled box with a pointer), a label (filled box), or plain letters.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum TextStyle {
    #[default]
    Callout,
    Label,
    #[serde(rename = "Text")]
    Plain,
}

impl TextStyle {
    pub const ALL: [TextStyle; 3] = [TextStyle::Callout, TextStyle::Label, TextStyle::Plain];

    pub fn title(self) -> &'static str {
        match self {
            TextStyle::Callout => "Callout",
            TextStyle::Label => "Label",
            TextStyle::Plain => "Text",
        }
    }
}

/// One step of the callout's pointer outline.
#[derive(Debug)]
enum PathOp {
    Move(Point),
    Curve(Point, Point, Point),
    /// Center, radius, start angle, end angle (drawn with decreasing angle).
    ArcNegative(Point, f64, f64, f64),
}

/// A text annotation laid out in image pixels.
pub struct TextBox {
    /// Filled background (callout, label); for plain text, just the text's box.
    pub frame: Rect,
    pub text_rect: Rect,
    pub corner_radius: f64,
    pointer: Vec<PathOp>,
    layout: pango::Layout,
    text_color: Rgb,
}

impl TextBox {
    pub fn new(origin: Point, string: &str, style: TextStyle, pointer: Point, font_size: f64, color: Rgb) -> TextBox {
        let layout = layout(string, font_size);
        let (width, height) = measure(&layout, string, font_size);
        layout.set_text(string);
        let (px, py) = padding(style, font_size);
        let frame = Rect::new(origin.x, origin.y, width + px * 2.0, height + py * 2.0);
        let corner_radius = (font_size * 0.22).round();
        TextBox {
            frame,
            text_rect: Rect::new(origin.x + px, origin.y + py, width, height),
            corner_radius,
            pointer: if style == TextStyle::Callout { pointer_path(frame, pointer, font_size, corner_radius) } else { vec![] },
            layout,
            text_color: text_color(style, color),
        }
    }

    pub fn has_pointer(&self) -> bool {
        !self.pointer.is_empty()
    }

    pub fn draw_text(&self, cr: &cairo::Context) {
        let Rgb(r, g, b) = self.text_color;
        cr.set_source_rgb(r as f64 / 255.0, g as f64 / 255.0, b as f64 / 255.0);
        cr.move_to(self.text_rect.x, self.text_rect.y);
        pangocairo::functions::show_layout(cr, &self.layout);
    }

    /// Adds the callout's pointer to the current path.
    pub fn add_pointer(&self, cr: &cairo::Context) {
        for op in &self.pointer {
            match *op {
                PathOp::Move(p) => cr.move_to(p.x, p.y),
                PathOp::Curve(a, b, c) => cr.curve_to(a.x, a.y, b.x, b.y, c.x, c.y),
                PathOp::ArcNegative(c, r, a1, a2) => cr.arc_negative(c.x, c.y, r, a1, a2),
            }
        }
        cr.close_path();
    }

    /// Where the caret goes after the last letter, in image pixels (top and bottom of the last line).
    pub fn caret(&self) -> (Point, Point) {
        let text = self.layout.text();
        let (strong, _) = self.layout.cursor_pos(text.len() as i32);
        let s = pango::SCALE as f64;
        let top = Point::new(self.text_rect.x + strong.x() as f64 / s, self.text_rect.y + strong.y() as f64 / s);
        (top, top.offset(0.0, strong.height() as f64 / s))
    }
}

/// Where a callout points until it's aimed: just below-left of the box, like a speech bubble.
pub fn default_pointer(below: Rect, font_size: f64) -> Point {
    Point::new(below.x + font_size * 0.6, below.max_y() + font_size * 0.8)
}

/// Space between the text and the box edge.
pub fn padding(style: TextStyle, font_size: f64) -> (f64, f64) {
    if style == TextStyle::Plain { (0.0, 0.0) } else { ((font_size * 0.45).round(), (font_size * 0.28).round()) }
}

/// Plain text uses the color itself; on a filled box, black or white, whichever reads better.
pub fn text_color(style: TextStyle, color: Rgb) -> Rgb {
    if style == TextStyle::Plain {
        return color;
    }
    let Rgb(r, g, b) = color;
    let luminance = (0.2126 * r as f64 + 0.7152 * g as f64 + 0.0722 * b as f64) / 255.0;
    if luminance > 0.62 { Rgb(0, 0, 0) } else { Rgb(255, 255, 255) }
}

/// GTK's font in bold, `size` image pixels tall (step numbers).
pub fn bold_layout(text: &str, size: f64) -> pango::Layout {
    let layout = layout(text, size);
    let mut font = layout.font_description().unwrap();
    font.set_weight(pango::Weight::Bold);
    layout.set_font_description(Some(&font));
    layout
}

/// GTK's own font, semibold, `size` image pixels tall (the macOS app uses the system font the same way).
fn layout(text: &str, size: f64) -> pango::Layout {
    let context = pangocairo::FontMap::default().create_context();
    let layout = pango::Layout::new(&context);
    let mut font = pango::FontDescription::from_string(&family());
    font.set_weight(pango::Weight::Semibold);
    font.set_absolute_size(size * pango::SCALE as f64);
    layout.set_font_description(Some(&font));
    layout.set_text(text);
    layout
}

/// The family of GTK's interface font ("Fira Sans 11" → "Fira Sans"); "Sans" without a display (tests).
fn family() -> String {
    let name = gtk::is_initialized_main_thread()
        .then(gtk::Settings::default)
        .flatten()
        .and_then(|s| s.gtk_font_name())
        .map(|n| pango::FontDescription::from_string(&n))
        .and_then(|d| d.family().map(|f| f.to_string()));
    name.unwrap_or_else(|| "Sans".into())
}

/// Size of the text, unwrapped (lines break only at returns). Empty text and a trailing return still get a line.
fn measure(layout: &pango::Layout, string: &str, font_size: f64) -> (f64, f64) {
    if string.is_empty() || string.ends_with('\n') {
        layout.set_text(&format!("{string} "));
    }
    let (width, height) = layout.pixel_size();
    ((width as f64).max((font_size * 0.5).round()), height as f64)
}

/// Tapered wedge from the box edge facing the tip, with inward-curving sides and a small rounded point (like Shottr's).
fn pointer_path(frame: Rect, tip: Point, font_size: f64, corner_radius: f64) -> Vec<PathOp> {
    let mid = frame.mid();
    let nx = (tip.x - mid.x) / (frame.width / 2.0).max(1.0);
    let ny = (tip.y - mid.y) / (frame.height / 2.0).max(1.0);
    if nx.abs() <= 1.0 && ny.abs() <= 1.0 {
        return vec![];
    }
    let clamp = |v: f64, low: f64, high: f64| if low > high { (low + high) / 2.0 } else { v.clamp(low, high) };
    // Base: at least 1.2× the font size, growing a little with length, never past the edge's straight part.
    let vertical = ny.abs() >= nx.abs();
    let length = (tip.x - mid.x).hypot(tip.y - mid.y) - if vertical { frame.height } else { frame.width } / 2.0;
    let wanted = (font_size * 0.6).max(length * 0.09).min(font_size * 1.2);
    // Each side meets the box with a fillet: it leaves the edge `outer` further out, tangent to it, so the joint is smooth.
    let room = ((if vertical { frame.width } else { frame.height } - 2.0 * corner_radius) / 2.0).max(1.0);
    let half = wanted.min(room);
    let outer = (half * 1.6).min(room);
    // Middle of the base (1px into the box so there's no seam), and the edge direction.
    let (center, edge) = if vertical {
        let x = clamp(tip.x, frame.x + corner_radius + outer, frame.max_x() - corner_radius - outer);
        (Point::new(x, if ny > 0.0 { frame.max_y() - 1.0 } else { frame.y + 1.0 }), Point::new(1.0, 0.0))
    } else {
        let y = clamp(tip.y, frame.y + corner_radius + outer, frame.max_y() - corner_radius - outer);
        (Point::new(if nx > 0.0 { frame.max_x() - 1.0 } else { frame.x + 1.0 }, y), Point::new(0.0, 1.0))
    };
    let along = |d: f64| Point::new(center.x + edge.x * d, center.y + edge.y * d);
    let (base_a, base_b) = (along(-half), along(half));

    // Each side bows toward the base→tip line, so the wedge flares out of the box and narrows,
    // then ends in a small round cap (a needle point looks harsh) whose far edge sits on the tip.
    let base = center;
    let span = (tip.x - base.x).hypot(tip.y - base.y);
    if span <= 0.0 {
        return vec![];
    }
    let u = Point::new((tip.x - base.x) / span, (tip.y - base.y) / span);
    let n = Point::new(-u.y, u.x);
    let radius = (font_size * 0.07).max(1.5).min(span / 4.0);
    let cap = Point::new(tip.x - u.x * radius, tip.y - u.y * radius);
    let bow = |side: Point| {
        Point::new(base.x + (tip.x - base.x) * 0.3 + (side.x - base.x) * 0.25, base.y + (tip.y - base.y) * 0.3 + (side.y - base.y) * 0.25)
    };
    // Walk fillet(+n side) → round cap → fillet(−n side); the base points pull each curve along the edge first.
    let n_first = edge.x * n.x + edge.y * n.y < 0.0; // base_a (−edge) is on the +n side
    let (side_n, side_minus_n) = if n_first { (base_a, base_b) } else { (base_b, base_a) };
    let (outer_n, outer_minus_n) = if n_first { (along(-outer), along(outer)) } else { (along(outer), along(-outer)) };
    let start_angle = n.y.atan2(n.x);
    vec![
        PathOp::Move(outer_n),
        PathOp::Curve(side_n, bow(side_n), Point::new(cap.x + n.x * radius, cap.y + n.y * radius)),
        PathOp::ArcNegative(cap, radius, start_angle, start_angle - PI), // from +n through the tip (u)
        PathOp::Curve(bow(side_minus_n), side_minus_n, outer_minus_n),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn contrast_on_filled_boxes() {
        assert_eq!(text_color(TextStyle::Label, Rgb(255, 204, 26)), Rgb(0, 0, 0)); // yellow
        assert_eq!(text_color(TextStyle::Callout, Rgb(240, 59, 59)), Rgb(255, 255, 255)); // red
        assert_eq!(text_color(TextStyle::Plain, Rgb(240, 59, 59)), Rgb(240, 59, 59));
    }

    #[test]
    fn callout_points_only_outside_its_box() {
        let inside = TextBox::new(Point::new(0.0, 0.0), "Hi", TextStyle::Callout, Point::new(5.0, 5.0), 28.0, Rgb(0, 0, 0));
        assert!(!inside.has_pointer());
        let below = default_pointer(inside.frame, 28.0);
        let aimed = TextBox::new(Point::new(0.0, 0.0), "Hi", TextStyle::Callout, below, 28.0, Rgb(0, 0, 0));
        assert!(aimed.has_pointer() && aimed.frame.width > 28.0 && aimed.frame.height > 28.0);
    }
}
