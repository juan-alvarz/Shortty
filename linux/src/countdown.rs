//! Lazy shots: a click-through outline of the area with the seconds left, gone before the capture runs.

use crate::geometry::Rect;
use gtk::{cairo, gdk, glib, pango, prelude::*};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use std::cell::Cell;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

/// True while a countdown runs, so the tray menu offers "Cancel Countdown".
pub static RUNNING: AtomicBool = AtomicBool::new(false);

thread_local! {
    static CANCELLED: Cell<bool> = const { Cell::new(false) };
}

/// Ends the countdown without a capture (the tray's "Cancel Countdown").
pub fn cancel() {
    CANCELLED.set(true);
}

/// Counts `seconds` down over `monitor`, outlining `area` (output points) or, without one, showing only the
/// seconds in the middle. False when cancelled.
pub async fn run(monitor: &gdk::Monitor, area: Option<Rect>, seconds: u32, color: (f64, f64, f64)) -> bool {
    CANCELLED.set(false);
    RUNNING.store(true, Ordering::Relaxed);
    crate::tray::refresh();
    let left = Rc::new(Cell::new(seconds));
    let window = overlay(monitor, area, left.clone(), color);
    for second in (1..=seconds).rev() {
        left.set(second);
        window.child().unwrap().queue_draw();
        for _ in 0..10 {
            glib::timeout_future(Duration::from_millis(100)).await;
            if CANCELLED.get() {
                break;
            }
        }
        if CANCELLED.get() {
            break;
        }
    }
    window.destroy();
    RUNNING.store(false, Ordering::Relaxed);
    crate::tray::refresh();
    glib::timeout_future(Duration::from_millis(150)).await; // until the compositor has taken the outline away
    !CANCELLED.get()
}

fn overlay(monitor: &gdk::Monitor, area: Option<Rect>, left: Rc<Cell<u32>>, color: (f64, f64, f64)) -> gtk::Window {
    let window = gtk::Window::new();
    window.init_layer_shell();
    window.set_layer(Layer::Overlay);
    window.set_monitor(Some(monitor));
    for edge in [Edge::Left, Edge::Right, Edge::Top, Edge::Bottom] {
        window.set_anchor(edge, true);
    }
    window.set_exclusive_zone(-1);
    window.set_keyboard_mode(KeyboardMode::None);
    window.set_namespace(Some("shortty-countdown"));
    // GTK paints windows with the theme's background; this one shows only the outline and the seconds.
    thread_local!(static STYLED: Cell<bool> = const { Cell::new(false) });
    if !STYLED.replace(true) {
        let css = gtk::CssProvider::new();
        css.load_from_string("window.shortty-countdown { background: transparent; }");
        gtk::style_context_add_provider_for_display(&monitor.display(), &css, gtk::STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
    window.add_css_class("shortty-countdown");
    let canvas = gtk::DrawingArea::new();
    canvas.set_draw_func(move |canvas, cr, w, h| {
        let (w, h) = (w as f64, h as f64);
        let (r, g, b) = color;
        let badge = match area {
            Some(a) => {
                cr.set_source_rgb(r, g, b);
                cr.set_line_width(2.0);
                cr.set_dash(&[6.0, 4.0], 0.0);
                cr.rectangle(a.x - 1.0, a.y - 1.0, a.width + 2.0, a.height + 2.0);
                let _ = cr.stroke();
                cr.set_dash(&[], 0.0);
                Some(a)
            }
            None => None,
        };
        let layout = canvas.create_pango_layout(Some(&left.get().to_string()));
        layout.set_font_description(Some(&pango::FontDescription::from_string("Bold 20")));
        let (tw, th) = layout.pixel_size();
        let size = (th as f64 + 16.0).max(tw as f64 + 24.0);
        // Inside the area's bottom-right corner, or the middle of the screen.
        let (x, y) = badge.map_or(((w - size) / 2.0, (h - size) / 2.0), |a| {
            ((a.x + a.width - size - 8.0).max(a.x), (a.y + a.height - size - 8.0).max(a.y))
        });
        cr.arc(x + size / 2.0, y + size / 2.0, size / 2.0, 0.0, std::f64::consts::TAU);
        cr.set_source_rgba(0.0, 0.0, 0.0, 0.72);
        let _ = cr.fill();
        cr.set_source_rgb(1.0, 1.0, 1.0);
        cr.move_to(x + (size - tw as f64) / 2.0, y + (size - th as f64) / 2.0);
        pangocairo::functions::show_layout(cr, &layout);
    });
    window.set_child(Some(&canvas));
    // Clicks go through to the apps underneath while it counts.
    window.connect_realize(|window| {
        if let Some(surface) = window.surface() {
            surface.set_input_region(Some(&cairo::Region::create()));
        }
    });
    window.present();
    window
}
