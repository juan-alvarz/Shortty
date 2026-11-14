//! Drawing annotations with Cairo in image pixels (top-left origin), and flattening them for export.

use super::annotation::{Annotation, Rgb, Shape, Tool};
use super::effects::AreaShape;
use super::text::{self, TextStyle};
use crate::geometry::{Point, Rect};
use gtk::{cairo, gdk, glib, prelude::*};

/// Draws annotations over `image`, in image pixels: blur and erase first, then one shared spotlight dim over
/// `content`, then everything else in list order (so arrows and text stay bright). Effects read the image's own
/// pixels, never other annotations. `hidden_text`: the text being typed, drawn without its letters.
pub fn annotations(cr: &cairo::Context, image: &cairo::ImageSurface, content: Rect, annotations: &[Annotation], hidden_text: Option<u64>) {
    for annotation in annotations {
        let Shape::Redact { rect, style, text_boxes } = &annotation.shape else { continue };
        let rect = rect.standardized();
        cr.save().ok();
        cr.rectangle(rect.x, rect.y, rect.width, rect.height);
        cr.clip();
        let areas = if style.text_only() { text_boxes.clone() } else { vec![rect] };
        for area in areas {
            if style.uses_strength() { pixelate(cr, image, area, annotation.width) } else { erase(cr, image, area) }
        }
        cr.restore().ok();
    }
    spotlights(cr, annotations, content);

    cr.set_line_cap(cairo::LineCap::Round);
    cr.set_line_join(cairo::LineJoin::Round);
    let mut step = 0;
    for annotation in annotations {
        let (r, g, b) = annotation.color.floats();
        cr.set_source_rgb(r, g, b);
        cr.set_line_width(annotation.width);
        match &annotation.shape {
            Shape::Stroke { points } => {
                polyline(cr, points, false);
                if points.len() == 1 {
                    cr.line_to(points[0].x, points[0].y); // a dot
                }
                let _ = cr.stroke();
            }
            Shape::Rectangle { rect } => {
                let r = rect.standardized();
                cr.rectangle(r.x, r.y, r.width, r.height);
                let _ = cr.stroke();
            }
            Shape::Ellipse { rect } => {
                area_path(cr, AreaShape::Ellipse {}, rect.standardized(), 0.0);
                let _ = cr.stroke();
            }
            Shape::Arrow { .. } => {
                let arrow = annotation.arrow_shape().unwrap();
                for fill in &arrow.fills {
                    polyline(cr, fill, true);
                    let _ = cr.fill();
                }
                if let Some((points, closed)) = &arrow.stroke {
                    cr.set_line_width(arrow.stroke_width);
                    polyline(cr, points, *closed);
                    let _ = cr.stroke();
                }
            }
            Shape::Text { style, .. } => {
                let layout = annotation.text_box().unwrap();
                if *style != TextStyle::Plain {
                    // Box and pointer filled separately: as one path, opposite windings could punch a hole where they overlap.
                    rounded_rect(cr, layout.frame, layout.corner_radius);
                    let _ = cr.fill();
                    if layout.has_pointer() {
                        layout.add_pointer(cr);
                        let _ = cr.fill();
                    }
                }
                if hidden_text != Some(annotation.id) {
                    layout.draw_text(cr);
                }
            }
            Shape::Magnifier { source, target, shape } => {
                magnifier(cr, image, annotation, source.standardized(), target.standardized(), *shape)
            }
            Shape::Step { center, .. } => {
                step += 1; // its place among the steps, so deleting one renumbers the rest
                draw_step(cr, step, *center, annotation.width, annotation.color, annotation.step_tip());
            }
            Shape::Redact { .. } | Shape::Spotlight { .. } => {} // drawn above, before everything else
        }
    }
}

/// The spotlight's hole and the magnifier's lens.
pub fn area_path(cr: &cairo::Context, shape: AreaShape, rect: Rect, corner_radius: f64) {
    match shape {
        AreaShape::Rectangle {} => rounded_rect(cr, rect, corner_radius),
        AreaShape::Ellipse {} => {
            if rect.width <= 0.0 || rect.height <= 0.0 {
                return;
            }
            cr.save().ok();
            cr.translate(rect.mid().x, rect.mid().y);
            cr.scale(rect.width / 2.0, rect.height / 2.0);
            cr.new_sub_path();
            cr.arc(0.0, 0.0, 1.0, 0.0, std::f64::consts::TAU);
            cr.restore().ok(); // stroke with an unscaled pen
        }
    }
}

/// Mosaic of `block`-pixel squares over `area`.
fn pixelate(cr: &cairo::Context, image: &cairo::ImageSurface, area: Rect, block: f64) {
    let bounds = Rect::new(0.0, 0.0, image.width() as f64, image.height() as f64);
    let area = area.integral();
    let (x0, y0) = (area.x.max(0.0), area.y.max(0.0));
    let area = Rect::new(x0, y0, area.max_x().min(bounds.width) - x0, area.max_y().min(bounds.height) - y0);
    if area.width < 1.0 || area.height < 1.0 {
        return;
    }
    let (columns, rows) = (((area.width / block).round() as i32).max(1), ((area.height / block).round() as i32).max(1));
    let Ok(small) = cairo::ImageSurface::create(cairo::Format::ARgb32, columns, rows) else { return };
    {
        let Ok(scaler) = cairo::Context::new(&small) else { return };
        scaler.scale(columns as f64 / area.width, rows as f64 / area.height);
        let _ = scaler.set_source_surface(image, -area.x, -area.y);
        scaler.source().set_filter(cairo::Filter::Good); // averages each block
        let _ = scaler.paint();
    }
    cr.save().ok();
    cr.translate(area.x, area.y);
    cr.scale(area.width / columns as f64, area.height / rows as f64);
    let _ = cr.set_source_surface(&small, 0.0, 0.0);
    cr.source().set_filter(cairo::Filter::Nearest); // hard block edges
    cr.rectangle(0.0, 0.0, columns as f64, rows as f64);
    let _ = cr.fill();
    cr.restore().ok();
}

/// Paints `area` with the color around it, so it looks erased.
fn erase(cr: &cairo::Context, image: &cairo::ImageSurface, area: Rect) {
    let (r, g, b) = median_around(image, area).floats();
    cr.set_source_rgb(r, g, b);
    cr.rectangle(area.x, area.y, area.width, area.height);
    let _ = cr.fill();
}

/// One shared dim layer with a hole per spotlight (so overlapping spotlights don't dim each other),
/// then each hole outlined in its color.
fn spotlights(cr: &cairo::Context, annotations: &[Annotation], content: Rect) {
    let holes: Vec<(Rect, AreaShape, Rgb)> = annotations
        .iter()
        .filter_map(|a| match a.shape {
            Shape::Spotlight { rect, shape } => Some((rect.standardized(), shape, a.color)),
            _ => None,
        })
        .collect();
    let Some(strength) = annotations.iter().filter(|a| a.tool() == Tool::Spotlight).map(|a| a.width).reduce(f64::max) else { return };
    cr.push_group();
    cr.set_source_rgba(0.0, 0.0, 0.0, strength / 100.0);
    cr.rectangle(content.x, content.y, content.width, content.height);
    let _ = cr.fill();
    cr.set_operator(cairo::Operator::Clear);
    for (rect, shape, _) in &holes {
        area_path(cr, *shape, *rect, 6.0);
        let _ = cr.fill();
    }
    cr.set_operator(cairo::Operator::Over);
    let _ = cr.pop_group_to_source();
    let _ = cr.paint();
    cr.set_line_width(4.0);
    for (rect, shape, color) in &holes {
        let (r, g, b) = color.floats();
        cr.set_source_rgb(r, g, b);
        area_path(cr, *shape, *rect, 6.0);
        let _ = cr.stroke();
    }
}

/// The source outline, the enlarged copy inside the target, and a line joining them.
fn magnifier(cr: &cairo::Context, image: &cairo::ImageSurface, a: &Annotation, source: Rect, target: Rect, shape: AreaShape) {
    if source.width < 1.0 || source.height < 1.0 {
        return;
    }
    let radius = target.width.min(target.height) * 0.12;
    cr.save().ok();
    area_path(cr, shape, target, radius);
    cr.clip();
    cr.set_source_rgb(0.1, 0.1, 0.1); // where the lens reaches past the image
    let _ = cr.paint();
    let (sx, sy) = (target.width / source.width, target.height / source.height);
    cr.translate(target.x - source.x * sx, target.y - source.y * sy);
    cr.scale(sx, sy);
    let _ = cr.set_source_surface(image, 0.0, 0.0);
    cr.source().set_filter(cairo::Filter::Good);
    let _ = cr.paint();
    cr.restore().ok();
    let (r, g, b) = a.color.floats();
    cr.set_source_rgb(r, g, b);
    cr.set_line_width(a.width);
    if !source.outset(a.width).intersects(target) {
        let from = shape.edge_point(source, target.mid());
        let to = shape.edge_point(target, source.mid());
        cr.move_to(from.x, from.y);
        cr.line_to(to.x, to.y);
    }
    area_path(cr, shape, source, source.width.min(source.height) * 0.12);
    area_path(cr, shape, target, radius);
    let _ = cr.stroke();
}

/// A filled circle with its number centered in black or white, whichever reads better on the color, and a pointer
/// toward `tip` that leaves the circle at most 45° either side of it.
pub fn draw_step(cr: &cairo::Context, number: usize, center: Point, diameter: f64, color: Rgb, tip: Option<Point>) {
    let (r, g, b) = color.floats();
    cr.set_source_rgb(r, g, b);
    let radius = diameter / 2.0;
    if let Some(tip) = tip {
        let angle = (tip.y - center.y).atan2(tip.x - center.x);
        let spread = (radius / tip.distance(center)).acos().min(std::f64::consts::FRAC_PI_4);
        cr.move_to(tip.x, tip.y);
        cr.line_to(center.x + radius * (angle + spread).cos(), center.y + radius * (angle + spread).sin());
        cr.line_to(center.x + radius * (angle - spread).cos(), center.y + radius * (angle - spread).sin());
        cr.close_path();
        let _ = cr.fill();
    }
    cr.new_sub_path();
    cr.arc(center.x, center.y, radius, 0.0, std::f64::consts::TAU);
    let _ = cr.fill();
    let layout = text::bold_layout(&number.to_string(), diameter * if number > 9 { 0.46 } else { 0.56 });
    let (w, h) = layout.pixel_size();
    let (r, g, b) = text::text_color(TextStyle::Label, color).floats();
    cr.set_source_rgb(r, g, b);
    cr.move_to(center.x - w as f64 / 2.0, center.y - h as f64 / 2.0);
    pangocairo::functions::show_layout(cr, &layout);
}

fn polyline(cr: &cairo::Context, points: &[Point], closed: bool) {
    let Some(first) = points.first() else { return };
    cr.move_to(first.x, first.y);
    for p in &points[1..] {
        cr.line_to(p.x, p.y);
    }
    if closed {
        cr.close_path();
    }
}

pub fn rounded_rect(cr: &cairo::Context, r: Rect, radius: f64) {
    let radius = radius.min(r.width / 2.0).min(r.height / 2.0).max(0.0);
    let quarter = std::f64::consts::FRAC_PI_2;
    cr.new_sub_path();
    cr.arc(r.max_x() - radius, r.y + radius, radius, -quarter, 0.0);
    cr.arc(r.max_x() - radius, r.max_y() - radius, radius, 0.0, quarter);
    cr.arc(r.x + radius, r.max_y() - radius, radius, quarter, 2.0 * quarter);
    cr.arc(r.x + radius, r.y + radius, radius, 2.0 * quarter, 3.0 * quarter);
    cr.close_path();
}

/// The crop when there is one, else the image plus anything drawn past its edges, in image pixels (the origin may be
/// negative). What's shown and exported.
pub fn content_rect(image: &cairo::ImageSurface, annotations: &[Annotation], crop: Option<Rect>) -> Rect {
    if let Some(crop) = crop {
        return crop.integral();
    }
    let bounds = Rect::new(0.0, 0.0, image.width() as f64, image.height() as f64);
    annotations.iter().filter_map(Annotation::drawn_bounds).fold(bounds, Rect::union).integral()
}

/// Flattens annotations onto a copy of the image, cut to `crop` if any. Anything drawn past the edges grows the
/// result, and the new area is filled with the color around the image's edge.
pub fn render(image: &cairo::ImageSurface, annotations: &[Annotation], crop: Option<Rect>) -> cairo::ImageSurface {
    let content = content_rect(image, annotations, crop);
    let surface = cairo::ImageSurface::create(cairo::Format::ARgb32, content.width as i32, content.height as i32).expect("surface");
    let cr = cairo::Context::new(&surface).expect("context");
    cr.translate(-content.x, -content.y);
    let bounds = Rect::new(0.0, 0.0, image.width() as f64, image.height() as f64);
    if !bounds.contains_rect(content) {
        let (r, g, b) = edge_color_of(image).floats();
        cr.set_source_rgb(r, g, b);
        let _ = cr.paint();
    }
    let _ = cr.set_source_surface(image, 0.0, 0.0);
    let _ = cr.paint();
    self::annotations(&cr, image, content, annotations, None);
    drop(cr);
    surface
}

/// Scaled down to at most `size` px on its longer side (history thumbnails).
pub fn scaled(surface: &cairo::ImageSurface, size: f64) -> cairo::ImageSurface {
    let scale = (size / surface.width().max(surface.height()).max(1) as f64).min(1.0);
    let (w, h) = (((surface.width() as f64 * scale).round() as i32).max(1), ((surface.height() as f64 * scale).round() as i32).max(1));
    let out = cairo::ImageSurface::create(cairo::Format::ARgb32, w, h).expect("surface");
    let cr = cairo::Context::new(&out).expect("context");
    cr.scale(scale, scale);
    let _ = cr.set_source_surface(surface, 0.0, 0.0);
    cr.source().set_filter(cairo::Filter::Good);
    let _ = cr.paint();
    drop(cr);
    out
}

/// The screenshot's typical edge color: the fill where the canvas grows past the image.
pub fn edge_color_of(image: &cairo::ImageSurface) -> Rgb {
    median_around(image, Rect::new(0.0, 0.0, image.width() as f64, image.height() as f64).inset(3.0, 3.0))
}

/// Median color of a 3 px ring just outside `rect`, clamped to the image.
fn median_around(image: &cairo::ImageSurface, rect: Rect) -> Rgb {
    let (w, h, stride) = (image.width() as i64, image.height() as i64, image.stride() as usize);
    let ring = rect.outset(3.0).integral();
    let inner = rect.integral();
    let (mut reds, mut greens, mut blues) = (Vec::new(), Vec::new(), Vec::new());
    let _ = image.with_data(|data| {
        for y in (ring.y as i64).max(0)..(ring.max_y() as i64).min(h) {
            for x in (ring.x as i64).max(0)..(ring.max_x() as i64).min(w) {
                if inner.contains(Point::new(x as f64 + 0.5, y as f64 + 0.5)) {
                    continue;
                }
                let i = y as usize * stride + x as usize * 4; // B, G, R, A
                blues.push(data[i]);
                greens.push(data[i + 1]);
                reds.push(data[i + 2]);
            }
        }
    });
    let median = |mut v: Vec<u8>| {
        v.sort_unstable();
        v.get(v.len() / 2).copied().unwrap_or(128)
    };
    Rgb(median(reds), median(greens), median(blues))
}

/// A PNG or other picture as a Cairo surface.
pub fn load(path: &std::path::Path) -> Result<cairo::ImageSurface, String> {
    let texture = gdk::Texture::from_filename(path).map_err(|e| e.to_string())?;
    let mut surface = cairo::ImageSurface::create(cairo::Format::ARgb32, texture.width(), texture.height()).map_err(|e| e.to_string())?;
    let stride = surface.stride() as usize;
    texture.download(&mut surface.data().map_err(|e| e.to_string())?, stride); // Cairo's ARGB32 is GDK's default download format
    Ok(surface)
}

pub fn save_png(surface: &cairo::ImageSurface, path: &std::path::Path) -> Result<(), String> {
    let (w, h, stride) = (surface.width(), surface.height(), surface.stride() as usize);
    let mut pixels = Vec::new();
    surface.flush();
    surface.with_data(|data| pixels = data.to_vec()).map_err(|e| e.to_string())?;
    let bytes = glib::Bytes::from_owned(pixels);
    let texture = gdk::MemoryTexture::new(w, h, gdk::MemoryFormat::B8g8r8a8Premultiplied, &bytes, stride);
    texture.save_to_png(path).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::editor::arrow::ArrowStyle;
    use crate::editor::model::PALETTE;

    /// Every shape and style on one picture, past its edges too. With SHORTTY_SNAPSHOTS=<dir> it's saved there to look at.
    #[test]
    fn snapshot_of_every_shape() {
        let image = cairo::ImageSurface::create(cairo::Format::ARgb32, 640, 360).unwrap();
        {
            let cr = cairo::Context::new(&image).unwrap();
            cr.set_source_rgb(0.93, 0.94, 0.96);
            let _ = cr.paint();
        }
        let p = Point::new;
        let mut list = vec![
            Annotation::new(Shape::Stroke { points: vec![p(20.0, 40.0), p(60.0, 20.0), p(100.0, 60.0), p(140.0, 30.0)] }, PALETTE[0], 4.0),
            Annotation::new(Shape::Rectangle { rect: Rect::new(170.0, 20.0, 120.0, 70.0) }, PALETTE[1], 4.0),
            Annotation::new(Shape::Ellipse { rect: Rect::new(320.0, 20.0, 120.0, 70.0) }, PALETTE[5], 4.0),
        ];
        for (i, style) in ArrowStyle::ALL.into_iter().enumerate() {
            let x = 30.0 + i as f64 * 150.0;
            list.push(Annotation::new(
                Shape::Arrow { start: p(x, 220.0), end: p(x + 110.0, 140.0), bend: if i % 2 == 0 { 0.0 } else { 25.0 }, style },
                PALETTE[i + 1],
                6.0,
            ));
        }
        let texts = [(TextStyle::Callout, PALETTE[0]), (TextStyle::Label, PALETTE[2]), (TextStyle::Plain, PALETTE[6])];
        for (i, (style, color)) in texts.into_iter().enumerate() {
            let origin = p(30.0 + i as f64 * 200.0, 260.0);
            list.push(Annotation::new(
                Shape::Text { origin, string: format!("{} ñá", style.title()), style, pointer: p(origin.x + 150.0, 350.0) },
                color,
                24.0,
            ));
        }
        list.push(Annotation::new(
            Shape::Arrow { start: p(560.0, 40.0), end: p(700.0, -20.0), bend: 0.0, style: ArrowStyle::Solid },
            PALETTE[3],
            6.0,
        ));
        let rendered = render(&image, &list, None);
        assert!(rendered.width() > 640 && rendered.height() > 360, "the arrow past the edge grows the canvas");
        if let Ok(dir) = std::env::var("SHORTTY_SNAPSHOTS") {
            save_png(&rendered, &std::path::Path::new(&dir).join("editor-shapes.png")).unwrap();
        }
    }

    /// Steps, magnifier, blur, erase and spotlight over a striped picture, then the same cropped.
    #[test]
    fn snapshot_of_effects() {
        use crate::editor::effects::{AreaShape, RedactStyle};
        let image = cairo::ImageSurface::create(cairo::Format::ARgb32, 640, 360).unwrap();
        {
            let cr = cairo::Context::new(&image).unwrap();
            for i in 0..32 {
                let shade = if i % 2 == 0 { 0.92 } else { 0.55 };
                cr.set_source_rgb(shade, shade * 0.9, 1.0 - shade * 0.5);
                cr.rectangle(i as f64 * 20.0, 0.0, 20.0, 360.0);
                let _ = cr.fill();
            }
            cr.set_source_rgb(0.1, 0.1, 0.1);
            cr.rectangle(300.0, 40.0, 120.0, 30.0);
            let _ = cr.fill();
        }
        let p = Point::new;
        let r = Rect::new;
        let list = vec![
            Annotation::new(
                Shape::Redact { rect: r(20.0, 20.0, 160.0, 90.0), style: RedactStyle::Blur, text_boxes: vec![] },
                PALETTE[0],
                12.0,
            ),
            Annotation::new(
                Shape::Redact { rect: r(310.0, 45.0, 60.0, 20.0), style: RedactStyle::Erase, text_boxes: vec![] },
                PALETTE[0],
                12.0,
            ),
            Annotation::new(Shape::Spotlight { rect: r(220.0, 140.0, 160.0, 100.0), shape: AreaShape::Ellipse {} }, PALETTE[5], 60.0),
            Annotation::new(
                Shape::Magnifier { source: r(40.0, 200.0, 40.0, 40.0), target: r(110.0, 180.0, 80.0, 80.0), shape: AreaShape::Ellipse {} },
                PALETTE[0],
                4.0,
            ),
            Annotation::new(Shape::Step { center: p(480.0, 80.0), tip: None }, PALETTE[1], 36.0),
            Annotation::new(Shape::Step { center: p(540.0, 160.0), tip: Some(p(600.0, 230.0)) }, PALETTE[2], 36.0),
        ];
        let rendered = render(&image, &list, None);
        let cropped = render(&image, &list, Some(r(200.0, 100.0, 300.0, 200.0)));
        assert_eq!((cropped.width(), cropped.height()), (300, 200));
        if let Ok(dir) = std::env::var("SHORTTY_SNAPSHOTS") {
            save_png(&rendered, &std::path::Path::new(&dir).join("editor-effects.png")).unwrap();
            save_png(&cropped, &std::path::Path::new(&dir).join("editor-cropped.png")).unwrap();
        }
    }
}
