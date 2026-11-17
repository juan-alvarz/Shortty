//! Pure geometry and parsing, tested without a display.

/// Saved like Swift's `CGPoint`, `[x, y]`, so edits stay readable by the macOS app.
#[derive(Clone, Copy, Debug, Default, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(from = "[f64; 2]", into = "[f64; 2]")]
pub struct Point {
    pub x: f64,
    pub y: f64,
}

impl Point {
    pub const fn new(x: f64, y: f64) -> Point {
        Point { x, y }
    }

    pub fn offset(self, dx: f64, dy: f64) -> Point {
        Point::new(self.x + dx, self.y + dy)
    }

    pub fn distance(self, other: Point) -> f64 {
        (other.x - self.x).hypot(other.y - self.y)
    }

    /// Distance to the segment a–b.
    pub fn distance_to_segment(self, a: Point, b: Point) -> f64 {
        let (dx, dy) = (b.x - a.x, b.y - a.y);
        let length_squared = dx * dx + dy * dy;
        let t = if length_squared == 0.0 { 0.0 } else { (((self.x - a.x) * dx + (self.y - a.y) * dy) / length_squared).clamp(0.0, 1.0) };
        self.distance(Point::new(a.x + t * dx, a.y + t * dy))
    }
}

impl From<[f64; 2]> for Point {
    fn from([x, y]: [f64; 2]) -> Point {
        Point { x, y }
    }
}

impl From<Point> for [f64; 2] {
    fn from(p: Point) -> [f64; 2] {
        [p.x, p.y]
    }
}

/// Saved like Swift's `CGRect`, `[[x, y], [width, height]]`.
#[derive(Clone, Copy, Debug, Default, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(from = "[[f64; 2]; 2]", into = "[[f64; 2]; 2]")]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl From<[[f64; 2]; 2]> for Rect {
    fn from([[x, y], [width, height]]: [[f64; 2]; 2]) -> Rect {
        Rect { x, y, width, height }
    }
}

impl From<Rect> for [[f64; 2]; 2] {
    fn from(r: Rect) -> [[f64; 2]; 2] {
        [[r.x, r.y], [r.width, r.height]]
    }
}

impl Rect {
    pub const fn new(x: f64, y: f64, width: f64, height: f64) -> Rect {
        Rect { x, y, width, height }
    }

    /// The smallest box around all the points; None for no points.
    pub fn enclosing(points: impl IntoIterator<Item = Point>) -> Option<Rect> {
        points.into_iter().map(|p| Rect::new(p.x, p.y, 0.0, 0.0)).reduce(|a, b| a.union(b))
    }

    /// The box between two corners, in any order.
    pub fn between(a: Point, b: Point) -> Rect {
        Rect::new(a.x.min(b.x), a.y.min(b.y), (b.x - a.x).abs(), (b.y - a.y).abs())
    }

    /// Positive width and height (a negative size is a mirrored box).
    pub fn standardized(self) -> Rect {
        Rect::between(self.origin(), Point::new(self.x + self.width, self.y + self.height))
    }

    pub fn origin(self) -> Point {
        Point::new(self.x, self.y)
    }

    pub fn max_x(self) -> f64 {
        self.x + self.width
    }

    pub fn max_y(self) -> f64 {
        self.y + self.height
    }

    pub fn mid(self) -> Point {
        Point::new(self.x + self.width / 2.0, self.y + self.height / 2.0)
    }

    pub fn union(self, other: Rect) -> Rect {
        let (x, y) = (self.x.min(other.x), self.y.min(other.y));
        Rect::new(x, y, self.max_x().max(other.max_x()) - x, self.max_y().max(other.max_y()) - y)
    }

    /// Grown by `dx`/`dy` on each side (shrunk when negative).
    pub fn inset(self, dx: f64, dy: f64) -> Rect {
        Rect::new(self.x + dx, self.y + dy, self.width - 2.0 * dx, self.height - 2.0 * dy)
    }

    pub fn outset(self, by: f64) -> Rect {
        self.inset(-by, -by)
    }

    pub fn contains(self, p: Point) -> bool {
        p.x >= self.x && p.x <= self.max_x() && p.y >= self.y && p.y <= self.max_y()
    }

    pub fn intersects(self, r: Rect) -> bool {
        self.x < r.max_x() && r.x < self.max_x() && self.y < r.max_y() && r.y < self.max_y()
    }

    /// The overlap, or None.
    pub fn intersection(self, r: Rect) -> Option<Rect> {
        let (x, y) = (self.x.max(r.x), self.y.max(r.y));
        let (x1, y1) = (self.max_x().min(r.max_x()), self.max_y().min(r.max_y()));
        (x1 > x && y1 > y).then(|| Rect::new(x, y, x1 - x, y1 - y))
    }

    pub fn contains_rect(self, r: Rect) -> bool {
        self.contains(r.origin()) && self.contains(Point::new(r.max_x(), r.max_y()))
    }

    /// Whole pixels covering this box.
    pub fn integral(self) -> Rect {
        let (x, y) = (self.x.floor(), self.y.floor());
        Rect::new(x, y, self.max_x().ceil() - x, self.max_y().ceil() - y)
    }

    /// The box between a drag's start and its current point, clamped to a `width` × `height` view.
    pub fn spanning(start: (f64, f64), end: (f64, f64), width: f64, height: f64) -> Rect {
        let clamp = |v: f64, max: f64| v.clamp(0.0, max);
        let (x0, x1) = (clamp(start.0, width), clamp(end.0, width));
        let (y0, y1) = (clamp(start.1, height), clamp(end.1, height));
        Rect { x: x0.min(x1), y: y0.min(y1), width: (x1 - x0).abs(), height: (y1 - y0).abs() }
    }

    /// Image pixels under this view rect, for an image of `image` pixels shown stretched over a `view` sized area.
    /// Output scale can be fractional, so the ratio comes from the sizes rather than a scale factor.
    pub fn pixels(&self, view: (f64, f64), image: (u32, u32)) -> (u32, u32, u32, u32) {
        let (sx, sy) = (image.0 as f64 / view.0, image.1 as f64 / view.1);
        let x0 = ((self.x * sx).round() as u32).min(image.0);
        let y0 = ((self.y * sy).round() as u32).min(image.1);
        let x1 = (((self.x + self.width) * sx).round() as u32).min(image.0);
        let y1 = (((self.y + self.height) * sy).round() as u32).min(image.1);
        (x0, y0, x1 - x0, y1 - y0)
    }
}

/// `hyprctl -j monitors` → the focused monitor's output name, for `grim -o`.
pub fn focused_monitor(json: &str) -> Option<String> {
    let monitors: serde_json::Value = serde_json::from_str(json).ok()?;
    monitors.as_array()?.iter().find(|m| m["focused"] == true)?["name"].as_str().map(String::from)
}

/// `hyprctl -j activewindow` → its box as `grim -g` wants it ("x,y wxh", logical pixels). `{}` when nothing has focus.
pub fn window_geometry(json: &str) -> Option<String> {
    let window: serde_json::Value = serde_json::from_str(json).ok()?;
    let (at, size) = (window["at"].as_array()?, window["size"].as_array()?);
    let n = |v: &serde_json::Value| v.as_i64();
    Some(format!("{},{} {}x{}", n(&at[0])?, n(&at[1])?, n(&size[0])?, n(&size[1])?))
}

/// The windows on screen (`hyprctl -j clients`, `hyprctl -j monitors`), in the layout's logical coordinates,
/// topmost first: fullscreen, then floating above tiled, then the most recently focused.
pub fn visible_windows(clients: &str, monitors: &str) -> Vec<Rect> {
    let (Ok(clients), Ok(monitors)) =
        (serde_json::from_str::<serde_json::Value>(clients), serde_json::from_str::<serde_json::Value>(monitors))
    else {
        return vec![];
    };
    let shown: Vec<i64> = monitors
        .as_array()
        .into_iter()
        .flatten()
        .flat_map(|m| [m["activeWorkspace"]["id"].as_i64(), m["specialWorkspace"]["id"].as_i64().filter(|id| *id != 0)])
        .flatten()
        .collect();
    let mut windows: Vec<(i64, bool, i64, Rect)> = clients
        .as_array()
        .into_iter()
        .flatten()
        .filter(|c| c["mapped"] == true && c["hidden"] != true)
        .filter(|c| c["pinned"] == true || c["workspace"]["id"].as_i64().is_some_and(|id| shown.contains(&id)))
        .filter_map(|c| {
            let n = |v: &serde_json::Value| v.as_f64();
            let rect = Rect::new(n(&c["at"][0])?, n(&c["at"][1])?, n(&c["size"][0])?, n(&c["size"][1])?);
            Some((c["fullscreen"].as_i64().unwrap_or(0), c["floating"] == true, c["focusHistoryID"].as_i64().unwrap_or(i64::MAX), rect))
        })
        .collect();
    windows.sort_by_key(|(fullscreen, floating, focus, _)| (-fullscreen, !floating, *focus));
    windows.into_iter().map(|(.., rect)| rect).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spanning_normalizes_and_clamps() {
        let r = Rect::spanning((100.0, 80.0), (-20.0, 500.0), 400.0, 300.0);
        assert_eq!(r, Rect { x: 0.0, y: 80.0, width: 100.0, height: 220.0 });
    }

    #[test]
    fn pixels_follow_fractional_scale() {
        // 1.25 scale: a 1536×864 logical output is 1920×1080 pixels.
        let r = Rect { x: 100.0, y: 40.0, width: 200.0, height: 100.0 };
        assert_eq!(r.pixels((1536.0, 864.0), (1920, 1080)), (125, 50, 250, 125));
        let edge = Rect { x: 1500.0, y: 0.0, width: 36.0, height: 864.0 };
        assert_eq!(edge.pixels((1536.0, 864.0), (1920, 1080)), (1875, 0, 45, 1080));
    }

    #[test]
    fn visible_windows_topmost_first() {
        let monitors = r#"[{"activeWorkspace":{"id":2},"specialWorkspace":{"id":0}}]"#;
        let clients = r#"[
            {"at":[0,0],"size":[100,100],"workspace":{"id":2},"floating":false,"hidden":false,"mapped":true,"focusHistoryID":0,"fullscreen":0},
            {"at":[10,10],"size":[50,50],"workspace":{"id":2},"floating":true,"hidden":false,"mapped":true,"focusHistoryID":3,"fullscreen":0},
            {"at":[20,20],"size":[50,50],"workspace":{"id":5},"floating":true,"hidden":false,"mapped":true,"focusHistoryID":1,"fullscreen":0},
            {"at":[30,30],"size":[50,50],"workspace":{"id":5},"floating":true,"hidden":false,"mapped":true,"focusHistoryID":2,"fullscreen":0,"pinned":true}
        ]"#;
        let windows = visible_windows(clients, monitors);
        assert_eq!(windows, [Rect::new(30.0, 30.0, 50.0, 50.0), Rect::new(10.0, 10.0, 50.0, 50.0), Rect::new(0.0, 0.0, 100.0, 100.0)]);
    }

    #[test]
    fn hyprctl_parsing() {
        let monitors = r#"[{"name":"eDP-1","focused":false},{"name":"HDMI-A-1","focused":true}]"#;
        assert_eq!(focused_monitor(monitors).as_deref(), Some("HDMI-A-1"));
        assert_eq!(window_geometry(r#"{"at":[12,-40],"size":[800,600]}"#).as_deref(), Some("12,-40 800x600"));
        assert_eq!(window_geometry("{}"), None);
    }
}
