//! Hand-drawn line icons from the macOS `Icons.swift` (20×20 grid, 1.5 stroke), drawn with Cairo in the
//! widget's own color, so the editor doesn't depend on an icon theme.

use crate::geometry::Rect;
use gtk::{cairo, prelude::*};

#[derive(Clone, Copy)]
pub enum Icon {
    Copy,
    Save,
    Cursor,
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
    Eyedropper,
    Trash,
    Close,
    ChevronUp,
    ChevronLeft,
    ChevronRight,
}

/// A `size`-point widget showing the icon in the current foreground color.
pub fn widget(icon: Icon, size: i32) -> gtk::DrawingArea {
    // Centered at its own size: stretched to its button, it would scale up with it.
    let area = gtk::DrawingArea::builder()
        .content_width(size)
        .content_height(size)
        .halign(gtk::Align::Center)
        .valign(gtk::Align::Center)
        .can_target(false)
        .build();
    area.set_draw_func(move |area, cr, w, _| {
        let c = area.color();
        cr.set_source_rgba(c.red() as f64, c.green() as f64, c.blue() as f64, c.alpha() as f64);
        let unit = w as f64 / 20.0;
        cr.scale(unit, unit);
        cr.set_line_width(1.5);
        cr.set_line_cap(cairo::LineCap::Round);
        cr.set_line_join(cairo::LineJoin::Round);
        draw(cr, icon);
    });
    area
}

fn lines(cr: &cairo::Context, points: &[(f64, f64)]) {
    cr.move_to(points[0].0, points[0].1);
    for &(x, y) in &points[1..] {
        cr.line_to(x, y);
    }
}

fn rounded(cr: &cairo::Context, x: f64, y: f64, w: f64, h: f64, r: f64) {
    super::draw::rounded_rect(cr, Rect::new(x, y, w, h), r);
}

fn draw(cr: &cairo::Context, icon: Icon) {
    match icon {
        Icon::Copy => {
            // The back sheet stops short of the front one.
            cr.save().ok();
            cr.rectangle(0.0, 0.0, 20.0, 20.0);
            cr.rectangle(1.1, 5.1, 13.8, 13.8);
            cr.set_fill_rule(cairo::FillRule::EvenOdd);
            cr.clip();
            rounded(cr, 6.5, 2.5, 11.0, 11.0, 2.5);
            let _ = cr.stroke();
            cr.restore().ok();
            rounded(cr, 2.5, 6.5, 11.0, 11.0, 2.5);
        }
        Icon::Save => {
            cr.move_to(3.0, 12.5);
            cr.line_to(3.0, 15.5);
            cr.curve_to(3.0, 16.5, 3.5, 17.0, 4.5, 17.0);
            cr.line_to(15.5, 17.0);
            cr.curve_to(16.5, 17.0, 17.0, 16.5, 17.0, 15.5);
            cr.line_to(17.0, 12.5);
            lines(cr, &[(10.0, 3.0), (10.0, 13.0)]);
            lines(cr, &[(6.5, 9.5), (10.0, 13.0), (13.5, 9.5)]);
        }
        Icon::Cursor => {
            lines(cr, &[(5.5, 3.0), (5.5, 15.5), (8.8, 12.6), (11.0, 17.2), (13.2, 16.2), (11.0, 11.6), (15.5, 11.6)]);
            cr.close_path();
        }
        Icon::Pencil => {
            lines(cr, &[(3.0, 17.0), (6.4, 16.6), (17.0, 6.0), (14.0, 3.0), (3.4, 13.6)]);
            cr.close_path();
            lines(cr, &[(11.8, 5.2), (14.8, 8.2)]);
        }
        Icon::Arrow => {
            lines(cr, &[(4.0, 16.0), (15.5, 4.5)]);
            lines(cr, &[(8.5, 4.5), (15.5, 4.5), (15.5, 11.5)]);
        }
        Icon::Text => {
            lines(cr, &[(4.5, 6.5), (4.5, 4.5), (15.5, 4.5), (15.5, 6.5)]);
            lines(cr, &[(10.0, 4.5), (10.0, 16.0)]);
            lines(cr, &[(7.5, 16.0), (12.5, 16.0)]);
        }
        Icon::Rectangle => rounded(cr, 3.0, 4.5, 14.0, 11.0, 1.5),
        Icon::Ellipse => {
            cr.save().ok();
            cr.translate(10.0, 10.0);
            cr.scale(7.25, 5.75);
            cr.arc(0.0, 0.0, 1.0, 0.0, std::f64::consts::TAU);
            cr.restore().ok();
        }
        Icon::Step => {
            // A badge with a 1.
            cr.arc(10.0, 10.0, 7.25, 0.0, std::f64::consts::TAU);
            lines(cr, &[(8.25, 7.5), (10.25, 6.0), (10.25, 14.0)]);
        }
        Icon::Magnifier => {
            cr.arc(8.25, 8.25, 5.25, 0.0, std::f64::consts::TAU);
            lines(cr, &[(12.0, 12.0), (16.8, 16.8)]);
            lines(cr, &[(8.25, 5.75), (8.25, 10.75)]);
            lines(cr, &[(5.75, 8.25), (10.75, 8.25)]);
        }
        Icon::Blur => {
            // A droplet.
            cr.move_to(10.0, 2.8);
            cr.curve_to(12.0, 6.0, 15.0, 8.5, 15.0, 12.0);
            cr.arc(10.0, 12.0, 5.0, 0.0, std::f64::consts::PI);
            cr.curve_to(5.0, 8.5, 8.0, 6.0, 10.0, 2.8);
        }
        Icon::Spotlight => {
            rounded(cr, 2.5, 4.0, 15.0, 12.0, 2.0);
            let _ = cr.stroke();
            cr.save().ok();
            cr.translate(10.0, 10.0);
            cr.scale(3.5, 3.0);
            cr.arc(0.0, 0.0, 1.0, 0.0, std::f64::consts::TAU);
            cr.restore().ok();
            let _ = cr.fill();
        }
        Icon::Crop => {
            lines(cr, &[(6.0, 2.5), (6.0, 14.0), (17.5, 14.0)]);
            lines(cr, &[(2.5, 6.0), (14.0, 6.0), (14.0, 17.5)]);
        }
        Icon::Ruler => {
            // A ruler on a slant, with ticks.
            lines(cr, &[(2.8, 13.2), (13.2, 2.8), (17.2, 6.8), (6.8, 17.2)]);
            cr.close_path();
            for (x, y, length) in [(6.0, 10.0, 2.5), (8.5, 7.5, 1.5), (11.0, 5.0, 2.5)] {
                lines(cr, &[(x, y), (x + length * std::f64::consts::FRAC_1_SQRT_2, y + length * std::f64::consts::FRAC_1_SQRT_2)]);
            }
        }
        Icon::Eyedropper => {
            lines(cr, &[(11.2, 6.6), (13.4, 8.8), (6.2, 16.0), (3.6, 16.4), (4.0, 13.8)]);
            cr.close_path();
            let _ = cr.stroke();
            lines(cr, &[(10.0, 5.4), (14.6, 10.0)]);
            cr.move_to(12.2, 7.8);
            cr.arc(14.4, 5.6, 2.6, 135f64.to_radians(), 315f64.to_radians());
        }
        Icon::Trash => {
            lines(cr, &[(3.5, 5.5), (16.5, 5.5)]);
            lines(cr, &[(7.5, 5.5), (7.5, 3.0), (12.5, 3.0), (12.5, 5.5)]);
            lines(cr, &[(5.0, 5.5), (6.0, 17.0), (14.0, 17.0), (15.0, 5.5)]);
            lines(cr, &[(8.5, 8.5), (8.5, 14.0)]);
            lines(cr, &[(11.5, 8.5), (11.5, 14.0)]);
        }
        Icon::Close => {
            lines(cr, &[(5.0, 5.0), (15.0, 15.0)]);
            lines(cr, &[(15.0, 5.0), (5.0, 15.0)]);
        }
        Icon::ChevronUp => {
            cr.set_line_width(2.0);
            lines(cr, &[(4.0, 13.0), (10.0, 7.0), (16.0, 13.0)]);
        }
        Icon::ChevronLeft => {
            cr.set_line_width(2.0);
            lines(cr, &[(13.0, 4.0), (7.0, 10.0), (13.0, 16.0)]);
        }
        Icon::ChevronRight => {
            cr.set_line_width(2.0);
            lines(cr, &[(7.0, 4.0), (13.0, 10.0), (7.0, 16.0)]);
        }
    }
    let _ = cr.stroke();
}
