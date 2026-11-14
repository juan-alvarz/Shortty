//! Arrow geometry, ported from the macOS `Arrow.swift`: a quadratic curve and the four looks.

use crate::geometry::Point;

/// Shottr's four arrow looks: hollow outline, solid tapered, thin line, double-headed line.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ArrowStyle {
    Outline,
    Solid,
    #[default]
    Line,
    Double,
}

impl ArrowStyle {
    pub const ALL: [ArrowStyle; 4] = [ArrowStyle::Outline, ArrowStyle::Solid, ArrowStyle::Line, ArrowStyle::Double];

    pub fn title(self) -> &'static str {
        match self {
            ArrowStyle::Outline => "Outline",
            ArrowStyle::Solid => "Solid",
            ArrowStyle::Line => "Line",
            ArrowStyle::Double => "Double",
        }
    }
}

/// Quadratic curve from `start` to `end`. `bend` is how far the arrow's middle sits off the straight line (signed, px).
pub struct Curve {
    start: Point,
    end: Point,
    control: Point,
}

impl Curve {
    pub fn new(start: Point, end: Point, bend: f64) -> Curve {
        let n = normal(start, end);
        // The curve passes through its control point's halfway mark, so 2× bend puts the middle exactly `bend` off the line.
        let control = Point::new((start.x + end.x) / 2.0 + n.x * 2.0 * bend, (start.y + end.y) / 2.0 + n.y * 2.0 * bend);
        Curve { start, end, control }
    }

    /// The bend that puts the middle handle under `point`.
    pub fn bend(point: Point, start: Point, end: Point) -> f64 {
        let n = normal(start, end);
        (point.x - (start.x + end.x) / 2.0) * n.x + (point.y - (start.y + end.y) / 2.0) * n.y
    }

    pub fn point(&self, t: f64) -> Point {
        let u = 1.0 - t;
        Point::new(
            u * u * self.start.x + 2.0 * u * t * self.control.x + t * t * self.end.x,
            u * u * self.start.y + 2.0 * u * t * self.control.y + t * t * self.end.y,
        )
    }

    pub fn middle(&self) -> Point {
        self.point(0.5)
    }

    pub fn samples(&self, count: usize) -> Vec<Point> {
        (0..=count).map(|i| self.point(i as f64 / count as f64)).collect()
    }
}

/// Unit vector perpendicular to a→b (zero when a == b).
pub fn normal(a: Point, b: Point) -> Point {
    let (dx, dy) = (b.x - a.x, b.y - a.y);
    let length = dx.hypot(dy);
    if length > 0.0 { Point::new(-dy / length, dx / length) } else { Point::default() }
}

/// Ready-to-draw outlines for one arrow, in the same coordinates as its points.
#[derive(Default)]
pub struct ArrowShape {
    /// Filled polygons (heads, or the whole solid arrow).
    pub fills: Vec<Vec<Point>>,
    /// A line to stroke and whether it closes (the outline style), with its width.
    pub stroke: Option<(Vec<Point>, bool)>,
    pub stroke_width: f64,
}

impl ArrowShape {
    pub fn new(start: Point, end: Point, bend: f64, style: ArrowStyle, width: f64) -> ArrowShape {
        let points = Curve::new(start, end, bend).samples(32);
        let length = path_length(&points);
        let mut shape = ArrowShape::default();
        match style {
            ArrowStyle::Line | ArrowStyle::Double => {
                // Short arrows get smaller heads.
                let head_length = (width * 3.2).max(10.0).min(length * if style == ArrowStyle::Double { 0.4 } else { 0.6 });
                let head_half = head_length * 0.5;
                let (mut shaft, end_base) = trim_end(&points, head_length);
                shape.fills.push(head(end_base, end, head_half));
                if style == ArrowStyle::Double {
                    let reversed: Vec<Point> = shaft.iter().rev().copied().collect();
                    let (trimmed, start_base) = trim_end(&reversed, head_length);
                    shaft = trimmed.into_iter().rev().collect();
                    shape.fills.push(head(start_base, start, head_half));
                }
                shape.stroke = Some((shaft, false));
                shape.stroke_width = width;
            }
            ArrowStyle::Solid | ArrowStyle::Outline => {
                let full_head = (width * 3.0).max(12.0);
                let head_length = full_head.min(length * 0.6);
                let head_half = (width * 1.6).max(7.0) * head_length / full_head;
                // Tapered body: thin at the tail, full width where it meets the head.
                let (tail_half, neck_half) = (width * 0.15, width * 0.5);
                let (shaft, base) = trim_end(&points, head_length);
                let shaft_length = path_length(&shaft);
                let (mut left, mut right) = (Vec::new(), Vec::new());
                let mut walked = 0.0;
                for i in 0..shaft.len() {
                    if i > 0 {
                        walked += shaft[i - 1].distance(shaft[i]);
                    }
                    let n = normal(shaft[i.saturating_sub(1)], shaft[(i + 1).min(shaft.len() - 1)]);
                    let half = tail_half + (neck_half - tail_half) * if shaft_length > 0.0 { walked / shaft_length } else { 1.0 };
                    left.push(offset(shaft[i], n, half));
                    right.push(offset(shaft[i], n, -half));
                }
                let n = normal(base, end);
                let mut outline = left;
                outline.extend([offset(base, n, head_half), end, offset(base, n, -head_half)]);
                outline.extend(right.into_iter().rev());
                if style == ArrowStyle::Solid {
                    shape.fills.push(outline);
                } else {
                    shape.stroke = Some((outline, true));
                    shape.stroke_width = (width * 0.35).max(2.0);
                }
            }
        }
        shape
    }
}

fn head(base: Point, tip: Point, half_width: f64) -> Vec<Point> {
    let n = normal(base, tip);
    vec![offset(base, n, half_width), tip, offset(base, n, -half_width)]
}

/// Cuts `length` off the end of a polyline. Returns the rest and the cut point (where the head starts).
fn trim_end(points: &[Point], length: f64) -> (Vec<Point>, Point) {
    let mut remaining = length;
    let mut i = points.len() - 1;
    while i > 0 {
        let segment = points[i - 1].distance(points[i]);
        if segment >= remaining && segment > 0.0 {
            let t = remaining / segment;
            let base = Point::new(points[i].x + (points[i - 1].x - points[i].x) * t, points[i].y + (points[i - 1].y - points[i].y) * t);
            let mut shaft = points[..i].to_vec();
            shaft.push(base);
            return (shaft, base);
        }
        remaining -= segment;
        i -= 1;
    }
    (vec![points[0]], points[0])
}

fn path_length(points: &[Point]) -> f64 {
    points.windows(2).map(|w| w[0].distance(w[1])).sum()
}

fn offset(p: Point, n: Point, amount: f64) -> Point {
    Point::new(p.x + n.x * amount, p.y + n.y * amount)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bend_puts_the_middle_off_the_line() {
        let (start, end) = (Point::new(0.0, 0.0), Point::new(100.0, 0.0));
        let middle = Curve::new(start, end, 20.0).middle();
        assert!((middle.x - 50.0).abs() < 1e-9 && (middle.y - 20.0).abs() < 1e-9);
        assert!((Curve::bend(middle, start, end) - 20.0).abs() < 1e-9);
    }

    #[test]
    fn heads_end_at_the_tip() {
        let shape = ArrowShape::new(Point::new(0.0, 0.0), Point::new(100.0, 0.0), 0.0, ArrowStyle::Double, 6.0);
        assert_eq!(shape.fills.len(), 2);
        assert_eq!(shape.fills[0][1], Point::new(100.0, 0.0));
        assert_eq!(shape.fills[1][1], Point::new(0.0, 0.0));
        let (shaft, closed) = shape.stroke.unwrap();
        assert!(!closed && shaft.first().unwrap().x > 0.0 && shaft.last().unwrap().x < 100.0);
    }
}
