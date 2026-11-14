//! Recent captures along the bottom of the editor: a slim bar that opens into thumbnails.

use super::icons::{self, Icon};
use super::model::preview_path;
use crate::history;
use gtk::{glib, prelude::*};
use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;

pub struct Strip {
    pub root: gtk::Box,
    title: gtk::Label,
    revealer: gtk::Revealer,
    list: gtk::Box,
    scroller: gtk::ScrolledWindow,
    newer: gtk::Button,
    older: gtk::Button,
    trash: gtk::Button,
    /// "Delete all N": the trash asks first, for 3 seconds.
    confirm: gtk::Button,
    /// The capture open in the editor.
    current: RefCell<Option<PathBuf>>,
    open: Rc<dyn Fn(PathBuf)>,
    removed: Rc<dyn Fn()>,
}

impl Strip {
    /// `open` loads a capture into the editor; `removed` is told when captures are deleted.
    pub fn new(open: Rc<dyn Fn(PathBuf)>, removed: Rc<dyn Fn()>) -> Rc<Strip> {
        let title = gtk::Label::new(None);
        let chevron = icons::widget(Icon::ChevronUp, 12);
        chevron.add_css_class("chevron");
        let header_content = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        header_content.append(&chevron);
        header_content.append(&title);
        let header = gtk::Button::builder().child(&header_content).css_classes(["flat", "strip-header"]).focus_on_click(false).build();
        let header_row = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        header_row.append(&header);

        let list = gtk::Box::new(gtk::Orientation::Horizontal, 10);
        let scroller = gtk::ScrolledWindow::builder().child(&list).vscrollbar_policy(gtk::PolicyType::Never).hexpand(true).build();
        let arrow = |icon| {
            gtk::Button::builder()
                .child(&icons::widget(icon, 14))
                .css_classes(["flat", "strip-arrow"])
                .focus_on_click(false)
                .valign(gtk::Align::Center)
                .build()
        };
        let (newer, older) = (arrow(Icon::ChevronLeft), arrow(Icon::ChevronRight));
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 4);
        row.append(&newer);
        row.append(&scroller);
        row.append(&older);
        let trash = gtk::Button::builder()
            .child(&icons::widget(Icon::Trash, 16))
            .tooltip_text("Delete all recent captures")
            .css_classes(["flat", "strip-arrow"])
            .focus_on_click(false)
            .valign(gtk::Align::Center)
            .build();
        let confirm = gtk::Button::builder()
            .css_classes(["destructive-action"])
            .focus_on_click(false)
            .valign(gtk::Align::Center)
            .visible(false)
            .build();
        row.append(&gtk::Separator::new(gtk::Orientation::Vertical));
        row.append(&trash);
        row.append(&confirm);
        row.set_margin_start(6);
        row.set_margin_end(6);
        row.set_margin_bottom(8);
        let expanded = crate::settings::Settings::load().history_expanded;
        let revealer =
            gtk::Revealer::builder().child(&row).transition_type(gtk::RevealerTransitionType::SlideUp).reveal_child(expanded).build();
        if expanded {
            header.add_css_class("open");
        }

        let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
        root.add_css_class("strip");
        root.append(&header_row);
        root.append(&revealer);
        let strip = Rc::new(Strip {
            root,
            title,
            revealer,
            list,
            scroller,
            newer,
            older,
            trash,
            confirm,
            current: RefCell::new(None),
            open,
            removed,
        });

        header.connect_clicked({
            let revealer = strip.revealer.clone();
            move |header| {
                let open = !revealer.reveals_child();
                revealer.set_reveal_child(open);
                if open {
                    header.add_css_class("open")
                } else {
                    header.remove_css_class("open")
                }
                let mut settings = crate::settings::Settings::load();
                settings.history_expanded = open;
                settings.save();
            }
        });
        for (button, step) in [(&strip.newer, -1isize), (&strip.older, 1)] {
            let strip = Rc::downgrade(&strip);
            button.connect_clicked(move |_| {
                let Some(strip) = strip.upgrade() else { return };
                if let Some(path) = strip.neighbor(step) {
                    (strip.open)(path);
                }
            });
        }
        strip.trash.connect_clicked({
            let strip = Rc::downgrade(&strip);
            move |trash| {
                let Some(strip) = strip.upgrade() else { return };
                trash.set_visible(false);
                strip.confirm.set_label(&format!("Delete all {}", history::captures().len()));
                strip.confirm.set_visible(true);
                let weak = Rc::downgrade(&strip);
                glib::timeout_add_local_once(std::time::Duration::from_secs(3), move || {
                    if let Some(strip) = weak.upgrade() {
                        strip.confirm.set_visible(false);
                        strip.trash.set_visible(true);
                    }
                });
            }
        });
        strip.confirm.connect_clicked({
            let strip = Rc::downgrade(&strip);
            move |confirm| {
                let Some(strip) = strip.upgrade() else { return };
                confirm.set_visible(false);
                strip.trash.set_visible(true);
                history::remove_all();
                (strip.removed)();
            }
        });
        strip
    }

    /// Rebuilds the thumbnails, highlighting `current`.
    pub fn reload(&self, current: Option<&Path>) {
        let captures = history::captures();
        self.title.set_text(&match captures.len() {
            1 => "1 recent capture".to_string(),
            n => format!("{n} recent captures"),
        });
        while let Some(child) = self.list.first_child() {
            self.list.remove(&child);
        }
        let index = current.and_then(|c| captures.iter().position(|p| p == c));
        self.trash.set_sensitive(!captures.is_empty());
        self.newer.set_sensitive(index.is_some_and(|i| i > 0));
        self.older.set_sensitive(index.is_some_and(|i| i + 1 < captures.len()));
        for path in captures {
            let item = thumbnail(&path, current == Some(path.as_path()), self.open.clone(), self.removed.clone());
            self.list.append(&item);
            if current == Some(path.as_path()) {
                // Scroll it into view once laid out.
                let (scroller, item) = (self.scroller.clone(), item.clone());
                glib::idle_add_local_once(move || {
                    if let Some(bounds) = item.compute_bounds(&scroller.child().unwrap()) {
                        let adjustment = scroller.hadjustment();
                        let (x, w) = (bounds.x() as f64, bounds.width() as f64);
                        let page = adjustment.page_size();
                        if x < adjustment.value() || x + w > adjustment.value() + page {
                            adjustment.set_value(x - (page - w) / 2.0);
                        }
                    }
                });
            }
        }
        self.current.replace(current.map(Path::to_path_buf));
    }

    /// The next newer (`-1`) or older (`1`) capture than the one open.
    fn neighbor(&self, step: isize) -> Option<PathBuf> {
        let captures = history::captures();
        let current = self.current.borrow().clone()?;
        let i = captures.iter().position(|p| *p == current)? as isize + step;
        captures.get(usize::try_from(i).ok()?).cloned()
    }
}

/// A capture's picture with its edits (the preview when there is one) and when it was taken.
const THUMB: (i32, i32) = (84, 50);

thread_local! {
    /// Thumbnails already scaled down, by file and when it last changed: the strip is rebuilt after every edit.
    static SMALL: RefCell<std::collections::HashMap<PathBuf, (std::time::SystemTime, gtk::cairo::ImageSurface)>> = RefCell::default();
}

/// The picture at about twice the cell's size, so it stays sharp on HiDPI screens and cheap to draw.
fn small_picture(file: &Path) -> Option<gtk::cairo::ImageSurface> {
    let modified = std::fs::metadata(file).and_then(|m| m.modified()).ok()?;
    if let Some(small) = SMALL.with_borrow(|cache| cache.get(file).filter(|(t, _)| *t == modified).map(|(_, s)| s.clone())) {
        return Some(small);
    }
    let small = super::draw::scaled(&super::draw::load(file).ok()?, (THUMB.0 * 2) as f64 * 2.0);
    SMALL.with_borrow_mut(|cache| cache.insert(file.to_path_buf(), (modified, small.clone())));
    Some(small)
}

/// × on hover deletes it.
fn thumbnail(path: &Path, current: bool, open: Rc<dyn Fn(PathBuf)>, removed: Rc<dyn Fn()>) -> gtk::Overlay {
    let preview = preview_path(path);
    let small = small_picture(if preview.exists() { &preview } else { path });
    // A fixed 84×50 cell the picture fills, cut to its rounded corners, like the macOS strip: a `Picture` would ask
    // for the image's own width and stretch the strip.
    let frame = gtk::DrawingArea::builder().content_width(THUMB.0).content_height(THUMB.1).build();
    frame.set_draw_func(move |_, cr, w, h| {
        let cell = crate::geometry::Rect::new(1.0, 1.0, w as f64 - 2.0, h as f64 - 2.0);
        super::draw::rounded_rect(cr, cell, 5.0);
        if let Some(small) = &small {
            cr.save().ok();
            cr.clip_preserve();
            let scale = (cell.width / small.width() as f64).max(cell.height / small.height() as f64);
            cr.translate(cell.mid().x - small.width() as f64 * scale / 2.0, cell.mid().y - small.height() as f64 * scale / 2.0);
            cr.scale(scale, scale);
            let _ = cr.set_source_surface(small, 0.0, 0.0);
            cr.source().set_filter(gtk::cairo::Filter::Good);
            let _ = cr.paint();
            cr.restore().ok();
        }
        if current {
            cr.set_source_rgb(1.0, 0.42, 0.24);
            cr.set_line_width(2.0);
        } else {
            cr.set_source_rgba(1.0, 1.0, 1.0, 0.12);
            cr.set_line_width(1.0);
        }
        let _ = cr.stroke();
    });
    let label = gtk::Label::builder().label(when(path)).css_classes(["thumb-date"]).build();
    let content = gtk::Box::new(gtk::Orientation::Vertical, 4);
    content.append(&frame);
    content.append(&label);
    let button = gtk::Button::builder().child(&content).css_classes(["flat", "thumb-button"]).focus_on_click(false).build();
    if current {
        button.add_css_class("current");
    }
    button.set_cursor_from_name(Some("pointer"));
    let close = gtk::Button::builder()
        .child(&icons::widget(Icon::Close, 10))
        .tooltip_text("Delete this capture")
        .css_classes(["thumb-close"])
        .halign(gtk::Align::End)
        .valign(gtk::Align::Start)
        .visible(false)
        .build();
    let cell = gtk::Overlay::builder().child(&button).build();
    cell.add_overlay(&close);
    let hover = gtk::EventControllerMotion::new();
    hover.connect_enter({
        let close = close.clone();
        move |_, _, _| close.set_visible(true)
    });
    hover.connect_leave({
        let close = close.clone();
        move |_| close.set_visible(false)
    });
    cell.add_controller(hover);
    let target = path.to_path_buf();
    button.connect_clicked(move |_| open(target.clone()));
    let target = path.to_path_buf();
    close.connect_clicked(move |_| {
        history::remove(&target);
        removed();
    });
    cell
}

/// "14:05" today, else "Nov 12", from the file name (`yyyyMMdd-HHmmss-SSS`).
fn when(path: &Path) -> String {
    let name = path.file_stem().and_then(|s| s.to_str()).unwrap_or("");
    let parse = |range: std::ops::Range<usize>| name.get(range).and_then(|s| s.parse::<i32>().ok());
    let (Some(year), Some(month), Some(day), Some(hour), Some(minute)) =
        (parse(0..4), parse(4..6), parse(6..8), parse(9..11), parse(11..13))
    else {
        return String::new();
    };
    let now = glib::DateTime::now_local().unwrap();
    if (now.year(), now.month(), now.day_of_month()) == (year, month, day) {
        format!("{hour:02}:{minute:02}")
    } else {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        format!("{} {day}", months.get(month as usize - 1).unwrap_or(&""))
    }
}
