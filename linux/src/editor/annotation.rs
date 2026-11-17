//! Something drawn on the screenshot, in image pixels (origin top-left; may go negative or past the edges).
//! Saved as `<capture>.json` in the macOS app's format, so the two apps read each other's edits.

use super::arrow::{ArrowShape, ArrowStyle, Curve};
use super::effects::{AreaShape, RedactStyle};
use super::text::{TextBox, TextStyle};
use crate::geometry::{Point, Rect};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};

/// A fixed sRGB color, saved as "#RRGGBB".
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct Rgb(pub u8, pub u8, pub u8);

impl Rgb {
    pub fn hex(self) -> String {
        format!("#{:02X}{:02X}{:02X}", self.0, self.1, self.2)
    }

    /// Accepts "#RRGGBB", "RRGGBB" or "#RGB".
    pub fn parse(hex: &str) -> Option<Rgb> {
        let digits = hex.trim().trim_start_matches('#');
        let digits: String = if digits.len() == 3 { digits.chars().flat_map(|c| [c, c]).collect() } else { digits.into() };
        let value = u32::from_str_radix(&digits, 16).ok().filter(|_| digits.len() == 6)?;
        Some(Rgb((value >> 16) as u8, (value >> 8) as u8, value as u8))
    }

    pub fn floats(self) -> (f64, f64, f64) {
        (self.0 as f64 / 255.0, self.1 as f64 / 255.0, self.2 as f64 / 255.0)
    }
}

impl TryFrom<String> for Rgb {
    type Error = String;
    fn try_from(hex: String) -> Result<Rgb, String> {
        Rgb::parse(&hex).ok_or(format!("not a color: {hex}"))
    }
}

impl From<Rgb> for String {
    fn from(c: Rgb) -> String {
        c.hex()
    }
}

/// The shapes the Linux editor draws so far, encoded like Swift's synthesized `Codable` enum
/// (`{"arrow": {"start": …}}`, unlabeled values as `_0`).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Shape {
    Stroke {
        #[serde(rename = "_0")]
        points: Vec<Point>,
    },
    Rectangle {
        #[serde(rename = "_0")]
        rect: Rect,
    },
    Ellipse {
        #[serde(rename = "_0")]
        rect: Rect,
    },
    /// `bend`: how far the middle sits off the straight start→end line (0 = straight).
    Arrow { start: Point, end: Point, bend: f64, style: ArrowStyle },
    /// `origin`: top-left of the box. `pointer`: where a callout points. Font size is the annotation's `width`.
    Text { origin: Point, string: String, style: TextStyle, pointer: Point },
    /// Blur or erase an area, or only the text in it (`text_boxes`). Strength is `width`.
    Redact {
        rect: Rect,
        style: RedactStyle,
        #[serde(rename = "textBoxes", default)]
        text_boxes: Vec<Rect>,
    },
    /// Dims everything else. Dim percent is `width`.
    Spotlight { rect: Rect, shape: AreaShape },
    /// `source` shown enlarged inside `target`.
    Magnifier { source: Rect, target: Rect, shape: AreaShape },
    /// A numbered badge (its number is its place among the steps). The diameter is `width`. `tip`: where its pointer
    /// ends (None: the lower-right corner; inside the badge: no pointer).
    Step {
        center: Point,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        tip: Option<Point>,
    },
}

/// The tool that draws each kind of annotation.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Tool {
    Select,
    Pencil,
    Arrow,
    Text,
    Rectangle,
    Ellipse,
    Step,
    Magnifier,
    Blur,
    Spotlight,
    Crop,
    Ruler,
}

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

fn next_id() -> u64 {
    NEXT_ID.fetch_add(1, Ordering::Relaxed)
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Annotation {
    /// Not saved: a reopened annotation gets a new one.
    #[serde(skip, default = "next_id")]
    pub id: u64,
    pub shape: Shape,
    pub color: Rgb,
    pub width: f64,
}

impl Annotation {
    pub fn new(shape: Shape, color: Rgb, width: f64) -> Annotation {
        Annotation { id: next_id(), shape, color, width }
    }

    /// The same annotation under a new id (Duplicate).
    pub fn copy(&self) -> Annotation {
        Annotation { id: next_id(), ..self.clone() }
    }

    pub fn tool(&self) -> Tool {
        match self.shape {
            Shape::Stroke { .. } => Tool::Pencil,
            Shape::Rectangle { .. } => Tool::Rectangle,
            Shape::Ellipse { .. } => Tool::Ellipse,
            Shape::Arrow { .. } => Tool::Arrow,
            Shape::Text { .. } => Tool::Text,
            Shape::Redact { .. } => Tool::Blur,
            Shape::Spotlight { .. } => Tool::Spotlight,
            Shape::Magnifier { .. } => Tool::Magnifier,
            Shape::Step { .. } => Tool::Step,
        }
    }

    /// Arrows are edited by their points, text by its pointer, the magnifier by its two lenses, steps by their tip;
    /// everything else by a box with 8 handles.
    pub fn uses_box_handles(&self) -> bool {
        !matches!(self.shape, Shape::Arrow { .. } | Shape::Text { .. } | Shape::Magnifier { .. } | Shape::Step { .. })
    }

    /// A step's pointer tip, when it reaches outside the badge. By default it's the badge's lower-right corner.
    pub fn step_tip(&self) -> Option<Point> {
        let Shape::Step { center, tip } = self.shape else { return None };
        let tip = tip.unwrap_or(center.offset(self.width / 2.0, self.width / 2.0));
        (tip.distance(center) > self.width / 2.0 + 1.0).then_some(tip)
    }

    pub fn text_box(&self) -> Option<TextBox> {
        let Shape::Text { origin, string, style, pointer } = &self.shape else { return None };
        Some(TextBox::new(*origin, string, *style, *pointer, self.width, self.color))
    }

    /// The box that selection handles sit on.
    pub fn bounds(&self) -> Rect {
        match &self.shape {
            Shape::Stroke { points } => Rect::enclosing(points.iter().copied()).unwrap_or_default(),
            Shape::Rectangle { rect } | Shape::Ellipse { rect } => rect.standardized(),
            Shape::Arrow { start, end, bend, .. } => Rect::enclosing(Curve::new(*start, *end, *bend).samples(16)).unwrap(),
            Shape::Text { style, pointer, .. } => {
                let frame = self.text_box().unwrap().frame;
                if *style == TextStyle::Callout { frame.union(Rect::new(pointer.x, pointer.y, 0.0, 0.0)) } else { frame }
            }
            Shape::Redact { rect, .. } | Shape::Spotlight { rect, .. } => rect.standardized(),
            Shape::Magnifier { source, target, .. } => source.standardized().union(target.standardized()),
            Shape::Step { center, .. } => Rect::new(center.x - self.width / 2.0, center.y - self.width / 2.0, self.width, self.width),
        }
    }

    /// What it covers once drawn (line width, arrow heads), for growing the canvas. Blur and spotlight only act on
    /// the image, so they never grow it.
    pub fn drawn_bounds(&self) -> Option<Rect> {
        Some(match self.shape {
            Shape::Redact { .. } | Shape::Spotlight { .. } => return None,
            Shape::Arrow { .. } => self.bounds().outset((self.width * 1.8).max(8.0) + 2.0),
            Shape::Text { .. } => self.bounds().outset(3.0),
            Shape::Step { .. } => self.step_tip().map_or(self.bounds(), |t| self.bounds().union(Rect::new(t.x, t.y, 0.0, 0.0))).outset(2.0),
            _ => self.bounds().outset(self.width / 2.0 + 2.0),
        })
    }

    /// A shape too small to see (a click without a drag), or text with nothing typed.
    pub fn is_degenerate(&self) -> bool {
        match &self.shape {
            Shape::Stroke { .. } | Shape::Step { .. } => false,
            Shape::Redact { rect, .. } | Shape::Spotlight { rect, .. } | Shape::Magnifier { source: rect, .. } => {
                rect.width.abs() < 3.0 || rect.height.abs() < 3.0
            }
            Shape::Arrow { start, end, .. } => start.distance(*end) < 4.0,
            Shape::Rectangle { .. } | Shape::Ellipse { .. } => self.bounds().width < 3.0 || self.bounds().height < 3.0,
            Shape::Text { string, .. } => string.trim().is_empty(),
        }
    }

    /// True when `p` is on the line itself (shapes are outlines, so their inside doesn't count).
    pub fn contains(&self, p: Point, tolerance: f64) -> bool {
        let reach = tolerance + self.width / 2.0;
        match &self.shape {
            Shape::Stroke { points } => {
                points.len() == 1 && p.distance(points[0]) <= reach || points.windows(2).any(|w| p.distance_to_segment(w[0], w[1]) <= reach)
            }
            Shape::Rectangle { rect } => {
                let rect = rect.standardized();
                rect.outset(reach).contains(p) && !rect.inset(reach, reach).contains(p)
            }
            Shape::Ellipse { rect } => {
                let rect = rect.standardized();
                let (a, b) = (rect.width / 2.0, rect.height / 2.0);
                if a <= 0.0 || b <= 0.0 {
                    return rect.outset(reach).contains(p);
                }
                let (dx, dy) = ((p.x - rect.mid().x) / a, (p.y - rect.mid().y) / b);
                ((dx * dx + dy * dy).sqrt() - 1.0).abs() * a.min(b) <= reach
            }
            Shape::Arrow { start, end, bend, .. } => {
                let points = Curve::new(*start, *end, *bend).samples(32);
                let reach = tolerance + self.width.max(6.0); // heads are wider than the line
                points.windows(2).any(|w| p.distance_to_segment(w[0], w[1]) <= reach)
            }
            Shape::Text { style, pointer, .. } => {
                let frame = self.text_box().unwrap().frame;
                frame.outset(tolerance).contains(p)
                    || *style == TextStyle::Callout && p.distance_to_segment(frame.mid(), *pointer) <= tolerance + self.width * 0.3
            }
            // Areas: anywhere inside.
            Shape::Redact { rect, .. } | Shape::Spotlight { rect, .. } => rect.standardized().outset(tolerance).contains(p),
            Shape::Magnifier { source, target, .. } => [source, target].iter().any(|r| r.standardized().outset(tolerance).contains(p)),
            Shape::Step { center, .. } => {
                p.distance(*center) <= self.width / 2.0 + tolerance
                    || self.step_tip().is_some_and(|t| p.distance_to_segment(*center, t) <= tolerance + self.width * 0.15)
            }
        }
    }

    pub fn moved(&self, dx: f64, dy: f64) -> Annotation {
        self.mapped(|p| p.offset(dx, dy))
    }

    /// Maps the `old` box onto `new`. `new` may have a negative size, which mirrors the annotation.
    pub fn resized(&self, old: Rect, new: Rect) -> Annotation {
        self.mapped(|p| {
            Point::new(
                if old.width == 0.0 { p.x + new.x - old.x } else { new.x + (p.x - old.x) / old.width * new.width },
                if old.height == 0.0 { p.y + new.y - old.y } else { new.y + (p.y - old.y) / old.height * new.height },
            )
        })
    }

    fn mapped(&self, transform: impl Fn(Point) -> Point) -> Annotation {
        let mut copy = self.clone();
        let rect = |r: Rect| Rect::between(transform(r.origin()), transform(Point::new(r.max_x(), r.max_y())));
        copy.shape = match &self.shape {
            Shape::Stroke { points } => Shape::Stroke { points: points.iter().map(|p| transform(*p)).collect() },
            Shape::Rectangle { rect: r } => Shape::Rectangle { rect: rect(*r) },
            Shape::Ellipse { rect: r } => Shape::Ellipse { rect: rect(*r) },
            Shape::Arrow { start, end, bend, style } => {
                Shape::Arrow { start: transform(*start), end: transform(*end), bend: *bend, style: *style }
            }
            Shape::Text { origin, string, style, pointer } => {
                Shape::Text { origin: transform(*origin), string: string.clone(), style: *style, pointer: transform(*pointer) }
            }
            // Text boxes follow until they're found again.
            Shape::Redact { rect: r, style, text_boxes } => {
                Shape::Redact { rect: rect(*r), style: *style, text_boxes: text_boxes.iter().map(|b| rect(*b)).collect() }
            }
            Shape::Spotlight { rect: r, shape } => Shape::Spotlight { rect: rect(*r), shape: *shape },
            Shape::Magnifier { source, target, shape } => Shape::Magnifier { source: rect(*source), target: rect(*target), shape: *shape },
            Shape::Step { center, tip } => Shape::Step { center: transform(*center), tip: tip.map(&transform) },
        };
        copy
    }

    /// The arrow's look, for drawing.
    pub fn arrow_shape(&self) -> Option<ArrowShape> {
        let Shape::Arrow { start, end, bend, style } = self.shape else { return None };
        Some(ArrowShape::new(start, end, bend, style, self.width))
    }
}

/// The box dragged from `start` to `end`; `square` forces equal sides (Shift).
pub fn drag_rect(start: Point, end: Point, square: bool) -> Rect {
    let (mut dx, mut dy) = (end.x - start.x, end.y - start.y);
    if square {
        let side = dx.abs().max(dy.abs());
        (dx, dy) = (side.copysign(dx), side.copysign(dy));
    }
    Rect::new(start.x, start.y, dx, dy).standardized()
}

/// What's kept of a capture's edits so they come back when it's reopened (the macOS `SavedEdits`).
#[derive(Default, Serialize, Deserialize)]
pub struct SavedEdits {
    pub annotations: Vec<Annotation>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub crop: Option<Rect>,
}

impl SavedEdits {
    /// Annotations this version can't draw yet (made on a Mac: blur, steps, …) are skipped, not an error.
    pub fn parse(json: &str) -> SavedEdits {
        let Ok(value) = serde_json::from_str::<serde_json::Value>(json) else { return SavedEdits::default() };
        let annotations = value["annotations"].as_array().into_iter().flatten();
        SavedEdits {
            annotations: annotations.filter_map(|a| serde_json::from_value(a.clone()).ok()).collect(),
            crop: serde_json::from_value(value["crop"].clone()).ok(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_matches_the_macos_format() {
        let arrow = Annotation::new(
            Shape::Arrow { start: Point::new(1.0, 2.0), end: Point::new(30.0, 40.0), bend: 0.0, style: ArrowStyle::Solid },
            Rgb(255, 107, 61),
            6.0,
        );
        let json = serde_json::to_string(&arrow).unwrap();
        assert_eq!(
            json,
            r##"{"shape":{"arrow":{"start":[1.0,2.0],"end":[30.0,40.0],"bend":0.0,"style":"solid"}},"color":"#FF6B3D","width":6.0}"##
        );
        let rect = serde_json::to_string(&Shape::Rectangle { rect: Rect::new(1.0, 2.0, 3.0, 4.0) }).unwrap();
        assert_eq!(rect, r#"{"rectangle":{"_0":[[1.0,2.0],[3.0,4.0]]}}"#);
        let text = Shape::Text { origin: Point::default(), string: "Hi".into(), style: TextStyle::Plain, pointer: Point::default() };
        assert!(serde_json::to_string(&text).unwrap().contains(r#""style":"Text""#));
    }

    #[test]
    fn unknown_shapes_are_skipped() {
        let json = r##"{"annotations":[{"shape":{"image":{"rect":[[0,0],[1,1]],"image":"iVBO"}},"color":"#000000","width":4},
            {"shape":{"ellipse":{"_0":[[0,0],[10,10]]}},"color":"#FFFFFF","width":4}],"crop":[[1,2],[3,4]]}"##;
        let edits = SavedEdits::parse(json);
        assert_eq!(edits.annotations.len(), 1);
        assert_eq!(edits.annotations[0].tool(), Tool::Ellipse);
        assert_eq!(edits.crop, Some(Rect::new(1.0, 2.0, 3.0, 4.0)));
    }

    #[test]
    fn hit_tests_follow_the_outline() {
        let rect = Annotation::new(Shape::Rectangle { rect: Rect::new(0.0, 0.0, 100.0, 50.0) }, Rgb(0, 0, 0), 4.0);
        assert!(rect.contains(Point::new(1.0, 25.0), 4.0));
        assert!(!rect.contains(Point::new(50.0, 25.0), 4.0));
        let ellipse = Annotation::new(Shape::Ellipse { rect: Rect::new(0.0, 0.0, 100.0, 50.0) }, Rgb(0, 0, 0), 4.0);
        assert!(ellipse.contains(Point::new(50.0, 1.0), 4.0) && !ellipse.contains(Point::new(50.0, 25.0), 4.0));
    }

    #[test]
    fn resizing_maps_and_mirrors() {
        let stroke = Annotation::new(Shape::Stroke { points: vec![Point::new(0.0, 0.0), Point::new(10.0, 10.0)] }, Rgb(0, 0, 0), 4.0);
        let resized = stroke.resized(Rect::new(0.0, 0.0, 10.0, 10.0), Rect::new(10.0, 0.0, -20.0, 10.0));
        assert_eq!(resized.shape, Shape::Stroke { points: vec![Point::new(10.0, 0.0), Point::new(-10.0, 10.0)] });
        assert_eq!(drag_rect(Point::new(10.0, 10.0), Point::new(0.0, 40.0), true), Rect::new(-20.0, 10.0, 30.0, 30.0));
    }

    #[test]
    fn colors_parse() {
        assert_eq!(Rgb::parse("#f0a"), Some(Rgb(255, 0, 170)));
        assert_eq!(Rgb::parse("FF6B3D"), Some(Rgb(255, 107, 61)));
        assert_eq!(Rgb::parse("#12345"), None);
    }
}
