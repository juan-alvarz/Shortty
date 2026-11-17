//! Effects geometry from the macOS `Effects.swift` and `Ruler.swift`: lens shapes, where the magnifier's copy goes,
//! and the ruler's same-color runs. Pure, so it's tested without a display.

use crate::geometry::{Point, Rect};
use serde::{Deserialize, Serialize};

/// Rectangle or ellipse: the spotlight's hole and the magnifier's lens. Saved like Swift's `{"rectangle": {}}`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AreaShape {
    Rectangle {},
    Ellipse {},
}

impl AreaShape {
    pub const ALL: [AreaShape; 2] = [AreaShape::Rectangle {}, AreaShape::Ellipse {}];

    pub fn title(self) -> &'static str {
        match self {
            AreaShape::Rectangle {} => "Rectangle",
            AreaShape::Ellipse {} => "Ellipse",
        }
    }

    /// Where a line from the shape's center toward `point` leaves the shape.
    pub fn edge_point(self, rect: Rect, toward: Point) -> Point {
        let mid = rect.mid();
        let (dx, dy) = (toward.x - mid.x, toward.y - mid.y);
        let (a, b) = (rect.width / 2.0, rect.height / 2.0);
        if (dx == 0.0 && dy == 0.0) || a <= 0.0 || b <= 0.0 {
            return mid;
        }
        let t = match self {
            AreaShape::Ellipse {} => 1.0 / ((dx * dx) / (a * a) + (dy * dy) / (b * b)).sqrt(),
            AreaShape::Rectangle {} => {
                let tx = if dx == 0.0 { f64::INFINITY } else { a / dx.abs() };
                let ty = if dy == 0.0 { f64::INFINITY } else { b / dy.abs() };
                tx.min(ty)
            }
        };
        Point::new(mid.x + dx * t, mid.y + dy * t)
    }
}

/// Shottr's four ways to hide things. Blur Text and Erase Text only cover the text boxes inside the area.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RedactStyle {
    Blur,
    #[serde(rename = "Blur Text")]
    BlurText,
    Erase,
    #[serde(rename = "Erase Text")]
    EraseText,
}

impl RedactStyle {
    /// The ones this version offers (the text ones need text recognition, which comes next).
    pub const OFFERED: [RedactStyle; 2] = [RedactStyle::Blur, RedactStyle::Erase];

    pub fn title(self) -> &'static str {
        match self {
            RedactStyle::Blur => "Blur",
            RedactStyle::BlurText => "Blur Text",
            RedactStyle::Erase => "Erase",
            RedactStyle::EraseText => "Erase Text",
        }
    }

    pub fn text_only(self) -> bool {
        matches!(self, RedactStyle::BlurText | RedactStyle::EraseText)
    }

    /// Blur has a strength (block size); erase doesn't.
    pub fn uses_strength(self) -> bool {
        matches!(self, RedactStyle::Blur | RedactStyle::BlurText)
    }
}

/// The magnifier's copy is twice the source.
pub const MAGNIFIER_ZOOM: f64 = 2.0;

/// Where the magnified copy goes: beside the source (right, left, below, above), inside the image when it fits.
pub fn magnifier_target(source: Rect, bounds: Rect) -> Rect {
    let (w, h) = (source.width * MAGNIFIER_ZOOM, source.height * MAGNIFIER_ZOOM);
    let gap = (source.width.min(source.height) * 0.4).max(16.0);
    let mid = source.mid();
    let candidates = [
        Rect::new(source.max_x() + gap, mid.y - h / 2.0, w, h),
        Rect::new(source.x - gap - w, mid.y - h / 2.0, w, h),
        Rect::new(mid.x - w / 2.0, source.max_y() + gap, w, h),
        Rect::new(mid.x - w / 2.0, source.y - gap - h, w, h),
    ];
    let visible = |r: &Rect| {
        let (x0, y0) = (r.x.max(bounds.x), r.y.max(bounds.y));
        let (x1, y1) = (r.max_x().min(bounds.max_x()), r.max_y().min(bounds.max_y()));
        (x1 - x0).max(0.0) * (y1 - y0).max(0.0)
    };
    let mut best = candidates
        .iter()
        .find(|c| bounds.contains_rect(**c))
        .copied()
        .unwrap_or_else(|| *candidates.iter().max_by(|a, b| visible(a).total_cmp(&visible(b))).unwrap());
    best.x = best.x.max(bounds.x).min((bounds.max_x() - best.width).max(bounds.x));
    best.y = best.y.max(bounds.y).min((bounds.max_y() - best.height).max(bounds.y));
    best
}

/// Ruler: from the pixel at `p`, how far the same color runs sideways (`horizontal`) or up and down, as a half-open
/// range of x or y. `pixels` are Cairo ARGB32 rows. None off the picture.
pub fn ruler_run(pixels: &[u8], width: usize, height: usize, stride: usize, p: Point, horizontal: bool) -> Option<(usize, usize)> {
    const TOLERANCE: i32 = 12;
    let (x, y) = (p.x.floor(), p.y.floor());
    if x < 0.0 || y < 0.0 || x as usize >= width || y as usize >= height {
        return None;
    }
    let (x, y) = (x as usize, y as usize);
    let at = |x: usize, y: usize| y * stride + x * 4;
    let start = at(x, y);
    let matches = |x: usize, y: usize| (0..3).all(|c| (pixels[at(x, y) + c] as i32 - pixels[start + c] as i32).abs() <= TOLERANCE);
    let (mut low, limit) = if horizontal { (x, width) } else { (y, height) };
    let mut high = low + 1;
    let same = |i: usize| if horizontal { matches(i, y) } else { matches(x, i) };
    while low > 0 && same(low - 1) {
        low -= 1;
    }
    while high < limit && same(high) {
        high += 1;
    }
    Some((low, high))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn area_shape_json_matches_swift() {
        assert_eq!(serde_json::to_string(&AreaShape::Ellipse {}).unwrap(), r#"{"ellipse":{}}"#);
        assert_eq!(serde_json::to_string(&RedactStyle::EraseText).unwrap(), r#""Erase Text""#);
    }

    #[test]
    fn magnifier_goes_beside_the_source_inside_the_image() {
        let bounds = Rect::new(0.0, 0.0, 400.0, 300.0);
        let right = magnifier_target(Rect::new(20.0, 100.0, 40.0, 40.0), bounds);
        assert_eq!(right, Rect::new(76.0, 80.0, 80.0, 80.0));
        let left = magnifier_target(Rect::new(340.0, 100.0, 40.0, 40.0), bounds);
        assert!(left.max_x() <= 340.0 && bounds.contains_rect(left));
    }

    #[test]
    fn edges_of_lenses() {
        let r = Rect::new(0.0, 0.0, 100.0, 50.0);
        assert_eq!(AreaShape::Rectangle {}.edge_point(r, Point::new(200.0, 25.0)), Point::new(100.0, 25.0));
        assert_eq!(AreaShape::Ellipse {}.edge_point(r, Point::new(50.0, 100.0)), Point::new(50.0, 50.0));
    }

    #[test]
    fn ruler_runs_to_the_color_change() {
        // 6×1: three black, then three white.
        let mut pixels = vec![0u8; 24];
        for x in 3..6 {
            pixels[x * 4..x * 4 + 4].copy_from_slice(&[255, 255, 255, 255]);
        }
        assert_eq!(ruler_run(&pixels, 6, 1, 24, Point::new(1.5, 0.5), true), Some((0, 3)));
        assert_eq!(ruler_run(&pixels, 6, 1, 24, Point::new(4.0, 0.0), true), Some((3, 6)));
        assert_eq!(ruler_run(&pixels, 6, 1, 24, Point::new(7.0, 0.0), true), None);
    }
}
