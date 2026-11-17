//! The editor's state: the capture, what's drawn on it, the selection and undo. No widgets, so it's testable.

use super::annotation::{Annotation, Rgb, SavedEdits, Shape, Tool};
use super::arrow::ArrowStyle;
use super::draw;
use super::effects::{AreaShape, RedactStyle};
use super::text::TextStyle;
use crate::geometry::Rect;
use gtk::cairo;
use std::{collections::HashMap, path::PathBuf};

/// The macOS `Theme.palette`: fixed sRGB so exports look the same everywhere.
pub const PALETTE: [Rgb; 10] = [
    Rgb(255, 107, 61), // accent
    Rgb(240, 59, 59),  // red
    Rgb(255, 204, 26), // yellow
    Rgb(51, 199, 89),  // green
    Rgb(26, 191, 217), // cyan
    Rgb(41, 120, 255), // blue
    Rgb(153, 89, 242), // purple
    Rgb(255, 89, 166), // pink
    Rgb(255, 255, 255),
    Rgb(0, 0, 0),
];

/// What undo restores: the annotations and the crop.
#[derive(Clone)]
struct Snapshot {
    annotations: Vec<Annotation>,
    crop: Option<Rect>,
}

pub struct Model {
    pub image: cairo::ImageSurface,
    /// The history file this capture came from; its edits are saved next to it.
    pub source: Option<PathBuf>,
    /// Bottom to top. Change it through the methods below, or call `record_change` after, to be undoable.
    pub annotations: Vec<Annotation>,
    pub selection: Option<u64>,
    /// Several annotations picked with a drag over empty space; `selection` is None while it's set.
    pub group: Vec<u64>,
    pub tool: Tool,
    pub color: Rgb,
    pub arrow_style: ArrowStyle,
    pub text_style: TextStyle,
    pub redact_style: RedactStyle,
    pub spotlight_shape: AreaShape,
    pub magnifier_shape: AreaShape,
    widths: HashMap<Tool, f64>,
    /// The applied crop (image px): the output is just this area. Nothing is thrown away; Reset or undo brings it back.
    pub crop: Option<Rect>,
    /// Crop tool: the box being adjusted, not applied yet.
    pub crop_box: Option<Rect>,
    /// The text annotation being typed into.
    pub editing: Option<u64>,
    before_edit: Vec<Annotation>,
    undo_stack: Vec<Snapshot>,
    redo_stack: Vec<Snapshot>,
    /// None = fit the window. Otherwise image pixels per screen pixel (1 = 100%).
    pub zoom: Option<f64>,
}

impl Model {
    pub fn new(image: cairo::ImageSurface, source: Option<PathBuf>) -> Model {
        let saved = source
            .as_ref()
            .and_then(|s| std::fs::read_to_string(edits_path(s)).ok())
            .map(|json| SavedEdits::parse(&json))
            .unwrap_or_default();
        Model {
            image,
            source,
            annotations: saved.annotations,
            crop: saved.crop,
            crop_box: None,
            selection: None,
            group: Vec::new(),
            tool: Tool::Pencil,
            color: PALETTE[0],
            arrow_style: ArrowStyle::Line,
            text_style: TextStyle::Callout,
            redact_style: RedactStyle::Blur,
            spotlight_shape: AreaShape::Rectangle {},
            magnifier_shape: AreaShape::Ellipse {},
            widths: HashMap::from([
                (Tool::Pencil, 4.0),
                (Tool::Arrow, 6.0),
                (Tool::Text, 28.0),
                (Tool::Rectangle, 4.0),
                (Tool::Ellipse, 4.0),
                (Tool::Magnifier, 4.0),
                (Tool::Blur, 12.0),
                (Tool::Spotlight, 60.0),
                (Tool::Step, 36.0),
            ]),
            editing: None,
            before_edit: Vec::new(),
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            zoom: None,
        }
    }

    /// Carries the tool, color, styles and thicknesses over to another capture, like the one macOS editor window.
    pub fn take_choices(&mut self, from: &Model) {
        (self.tool, self.color, self.arrow_style, self.text_style) = (from.tool, from.color, from.arrow_style, from.text_style);
        (self.redact_style, self.spotlight_shape, self.magnifier_shape) = (from.redact_style, from.spotlight_shape, from.magnifier_shape);
        self.widths = from.widths.clone();
    }

    pub fn width(&self, tool: Tool) -> f64 {
        self.widths.get(&tool).copied().unwrap_or(4.0)
    }

    /// What the thickness slider covers for a kind of annotation (the macOS `currentWidthRange`).
    pub fn width_range(tool: Tool) -> (f64, f64) {
        match tool {
            Tool::Text => (12.0, 120.0),
            Tool::Blur => (4.0, 40.0),
            Tool::Spotlight => (20.0, 90.0),
            Tool::Step => (16.0, 96.0),
            _ => (2.0, 24.0),
        }
    }

    /// The crop when there is one, else the image plus anything drawn past its edges.
    pub fn content_rect(&self) -> Rect {
        draw::content_rect(&self.image, &self.annotations, self.crop)
    }

    pub fn index(&self, id: u64) -> Option<usize> {
        self.annotations.iter().position(|a| a.id == id)
    }

    pub fn selected(&self) -> Option<&Annotation> {
        self.selection.and_then(|id| self.index(id)).map(|i| &self.annotations[i])
    }

    /// The picked annotations: the group, else the selection.
    pub fn picked(&self) -> Vec<u64> {
        if self.group.is_empty() { self.selection.into_iter().collect() } else { self.group.clone() }
    }

    /// Selecting shows its color, style and thickness in the options, so new shapes continue from it.
    pub fn select(&mut self, id: Option<u64>) {
        if id != self.editing {
            self.end_editing();
        }
        self.selection = id;
        self.group.clear();
        let Some(selected) = self.selected().cloned() else { return };
        self.color = selected.color;
        self.widths.insert(selected.tool(), selected.width);
        match selected.shape {
            Shape::Arrow { style, .. } => self.arrow_style = style,
            Shape::Text { style, .. } => self.text_style = style,
            Shape::Redact { style, .. } => self.redact_style = style,
            Shape::Spotlight { shape, .. } => self.spotlight_shape = shape,
            Shape::Magnifier { shape, .. } => self.magnifier_shape = shape,
            _ => {}
        }
    }

    pub fn set_tool(&mut self, tool: Tool) {
        self.end_editing();
        self.tool = tool;
        if tool != Tool::Crop {
            self.crop_box = None;
        }
        if tool != Tool::Select {
            self.select(None);
        }
    }

    // MARK: Live options: they also change what's picked.

    pub fn set_color(&mut self, color: Rgb) {
        self.color = color;
        self.update_picked(true, |a| a.color = color);
    }

    /// `undoable: false` while a slider moves; one step is recorded when it's let go (`record_change`).
    pub fn set_width(&mut self, width: f64, undoable: bool) {
        let tool = self.selected().map(Annotation::tool).unwrap_or(self.tool);
        self.widths.insert(tool, width);
        if let Some(id) = self.selection {
            self.update(&[id], undoable, |a| a.width = width);
        }
    }

    pub fn set_arrow_style(&mut self, style: ArrowStyle) {
        self.arrow_style = style;
        self.update_picked(true, |a| {
            if let Shape::Arrow { style: s, .. } = &mut a.shape {
                *s = style;
            }
        });
    }

    pub fn set_text_style(&mut self, style: TextStyle) {
        self.text_style = style;
        self.update_picked(true, |a| {
            if let Shape::Text { style: s, .. } = &mut a.shape {
                *s = style;
            }
        });
    }

    pub fn set_redact_style(&mut self, style: RedactStyle) {
        self.redact_style = style;
        self.update_picked(true, |a| {
            if let Shape::Redact { style: s, .. } = &mut a.shape {
                *s = style;
            }
        });
    }

    /// The spotlight's or magnifier's shape, whichever the options show.
    pub fn set_area_shape(&mut self, tool: Tool, area: AreaShape) {
        if tool == Tool::Spotlight {
            self.spotlight_shape = area
        } else {
            self.magnifier_shape = area
        }
        self.update_picked(true, |a| match &mut a.shape {
            Shape::Spotlight { shape, .. } if tool == Tool::Spotlight => *shape = area,
            Shape::Magnifier { shape, .. } if tool == Tool::Magnifier => *shape = area,
            _ => {}
        });
    }

    // MARK: Crop

    /// Crops to the box being adjusted (Return or the Crop button), then goes back to Select.
    pub fn apply_crop(&mut self) {
        let Some(crop_box) = self.crop_box.map(|b| b.standardized().integral()).filter(|b| b.width >= 4.0 && b.height >= 4.0) else {
            return;
        };
        self.undo_stack.push(Snapshot { annotations: self.annotations.clone(), crop: self.crop });
        self.redo_stack.clear();
        self.crop = Some(crop_box);
        self.set_tool(Tool::Select);
    }

    pub fn reset_crop(&mut self) {
        if self.crop.is_none() {
            return;
        }
        self.undo_stack.push(Snapshot { annotations: self.annotations.clone(), crop: self.crop });
        self.redo_stack.clear();
        self.crop = None;
    }

    fn update_picked(&mut self, undoable: bool, change: impl Fn(&mut Annotation)) {
        let picked = self.picked();
        self.update(&picked, undoable, change);
    }

    fn update(&mut self, ids: &[u64], undoable: bool, change: impl Fn(&mut Annotation)) {
        if ids.is_empty() {
            return;
        }
        let before = self.annotations.clone();
        for a in self.annotations.iter_mut().filter(|a| ids.contains(&a.id)) {
            change(a);
        }
        if undoable && self.annotations != before {
            self.record_change(before);
        }
    }

    // MARK: Editing

    pub fn delete_picked(&mut self) {
        let picked = self.picked();
        if picked.is_empty() {
            return;
        }
        let before = self.annotations.clone();
        self.annotations.retain(|a| !picked.contains(&a.id));
        self.record_change(before);
        self.select(None);
    }

    /// Copies of what's picked, a little down and right, picked instead.
    pub fn duplicate_picked(&mut self) {
        let picked = self.picked();
        let copies: Vec<Annotation> =
            self.annotations.iter().filter(|a| picked.contains(&a.id)).map(|a| a.copy().moved(16.0, 16.0)).collect();
        if copies.is_empty() {
            return;
        }
        let before = self.annotations.clone();
        let ids: Vec<u64> = copies.iter().map(|a| a.id).collect();
        self.annotations.extend(copies);
        self.record_change(before);
        self.pick(ids);
    }

    /// Picks one (selection) or several (group).
    pub fn pick(&mut self, ids: Vec<u64>) {
        if ids.len() == 1 {
            self.select(Some(ids[0]));
        } else {
            self.select(None);
            self.group = ids;
        }
    }

    /// Bring to front (`true`) or send to back, keeping the picked ones' order among themselves.
    pub fn reorder_picked(&mut self, to_front: bool) {
        let picked = self.picked();
        let before = self.annotations.clone();
        let (mut moving, rest): (Vec<_>, Vec<_>) = self.annotations.drain(..).partition(|a| picked.contains(&a.id));
        self.annotations = if to_front {
            [rest, moving].concat()
        } else {
            moving.extend(rest);
            moving
        };
        if self.annotations != before {
            self.record_change(before);
        }
    }

    pub fn nudge_picked(&mut self, dx: f64, dy: f64) {
        let picked = self.picked();
        self.update(&picked, true, |a| *a = a.moved(dx, dy));
    }

    // MARK: Text

    /// Adds new text and starts typing into it; undo removes it in one step.
    pub fn start_text(&mut self, text: Annotation) {
        self.end_editing();
        let before = self.annotations.clone();
        let id = text.id;
        self.annotations.push(text);
        self.begin_editing(id);
        self.before_edit = before;
    }

    pub fn begin_editing(&mut self, id: u64) {
        self.end_editing();
        self.before_edit = self.annotations.clone();
        self.editing = Some(id);
        self.selection = Some(id);
        self.group.clear();
    }

    pub fn editing_text(&self) -> Option<String> {
        let i = self.editing.and_then(|id| self.index(id))?;
        match &self.annotations[i].shape {
            Shape::Text { string, .. } => Some(string.clone()),
            _ => None,
        }
    }

    pub fn set_text(&mut self, text: &str) {
        let Some(i) = self.editing.and_then(|id| self.index(id)) else { return };
        if let Shape::Text { string, .. } = &mut self.annotations[i].shape {
            *string = text.to_string();
        }
    }

    /// Removes text left empty, and records the whole typing session as one undo step.
    pub fn end_editing(&mut self) {
        let Some(id) = self.editing.take() else { return };
        if self.index(id).is_some_and(|i| self.annotations[i].is_degenerate()) {
            self.annotations.retain(|a| a.id != id);
            self.selection = None;
        }
        let before = std::mem::take(&mut self.before_edit);
        if self.annotations != before {
            self.record_change(before);
        }
    }

    // MARK: Undo

    pub fn record_change(&mut self, before: Vec<Annotation>) {
        self.undo_stack.push(Snapshot { annotations: before, crop: self.crop });
        self.redo_stack.clear();
    }

    pub fn undo(&mut self) {
        self.end_editing();
        if let Some(previous) = self.undo_stack.pop() {
            let current = self.restore(previous);
            self.redo_stack.push(current);
        }
    }

    pub fn redo(&mut self) {
        self.end_editing();
        if let Some(next) = self.redo_stack.pop() {
            let current = self.restore(next);
            self.undo_stack.push(current);
        }
    }

    /// Puts a snapshot back and returns what was there.
    fn restore(&mut self, snapshot: Snapshot) -> Snapshot {
        let current = Snapshot { annotations: std::mem::replace(&mut self.annotations, snapshot.annotations), crop: self.crop };
        self.crop = snapshot.crop;
        self.crop_box = None;
        self.forget_missing();
        current
    }

    fn forget_missing(&mut self) {
        if self.selection.is_some_and(|id| self.index(id).is_none()) {
            self.selection = None;
        }
        let present: Vec<u64> = self.annotations.iter().map(|a| a.id).collect();
        self.group.retain(|id| present.contains(id));
    }

    // MARK: Output

    pub fn rendered(&self) -> cairo::ImageSurface {
        draw::render(&self.image, &self.annotations, self.crop)
    }

    /// `<capture>.json` and a `<capture>.preview.png` with the edits for the history strip; with nothing drawn, neither.
    pub fn save_edits(&self) {
        let Some(source) = &self.source else { return };
        let (json, preview) = (edits_path(source), preview_path(source));
        if self.annotations.is_empty() && self.crop.is_none() {
            let _ = std::fs::remove_file(json);
            let _ = std::fs::remove_file(preview);
            return;
        }
        if !source.exists() {
            return; // the capture was deleted meanwhile
        }
        let edits = SavedEdits { annotations: self.annotations.clone(), crop: self.crop };
        if let Ok(text) = serde_json::to_string(&edits) {
            let _ = std::fs::write(json, text);
        }
        let _ = draw::save_png(&draw::scaled(&self.rendered(), 240.0), &preview);
    }
}

pub fn edits_path(capture: &std::path::Path) -> PathBuf {
    capture.with_extension("json")
}

pub fn preview_path(capture: &std::path::Path) -> PathBuf {
    capture.with_extension("preview.png")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geometry::Rect;

    fn model() -> Model {
        Model::new(cairo::ImageSurface::create(cairo::Format::ARgb32, 100, 100).unwrap(), None)
    }

    trait Add {
        fn add(&mut self, annotation: Annotation);
    }

    impl Add for Model {
        /// What the canvas does once a new shape is drawn.
        fn add(&mut self, annotation: Annotation) {
            let before = self.annotations.clone();
            let id = annotation.id;
            self.annotations.push(annotation);
            self.record_change(before);
            self.select(Some(id));
        }
    }

    fn rect(x: f64) -> Annotation {
        Annotation::new(Shape::Rectangle { rect: Rect::new(x, 0.0, 10.0, 10.0) }, PALETTE[0], 4.0)
    }

    #[test]
    fn undo_and_redo() {
        let mut m = model();
        m.add(rect(0.0));
        m.add(rect(20.0));
        m.undo();
        assert_eq!(m.annotations.len(), 1);
        m.redo();
        assert_eq!(m.annotations.len(), 2);
        m.select(Some(m.annotations[1].id));
        m.delete_picked();
        assert_eq!(m.annotations.len(), 1);
        m.undo();
        assert_eq!(m.annotations.len(), 2);
    }

    #[test]
    fn options_change_the_selection() {
        let mut m = model();
        m.add(rect(0.0));
        m.set_color(PALETTE[5]);
        m.set_width(9.0, true);
        assert_eq!((m.annotations[0].color, m.annotations[0].width), (PALETTE[5], 9.0));
        m.undo();
        assert_eq!(m.annotations[0].width, 4.0);
    }

    #[test]
    fn typing_is_one_undo_step_and_empty_text_goes() {
        let mut m = model();
        let text = Shape::Text { origin: Default::default(), string: String::new(), style: TextStyle::Label, pointer: Default::default() };
        m.start_text(Annotation::new(text, PALETTE[0], 28.0));
        m.set_text("H");
        m.set_text("Hi");
        m.end_editing();
        m.undo();
        assert!(m.annotations.is_empty());
        let empty = Annotation::new(
            Shape::Text { origin: Default::default(), string: String::new(), style: TextStyle::Plain, pointer: Default::default() },
            PALETTE[0],
            28.0,
        );
        m.start_text(empty);
        m.end_editing();
        assert!(m.annotations.is_empty());
    }

    #[test]
    fn reorder_and_duplicate() {
        let mut m = model();
        m.add(rect(0.0));
        m.add(rect(20.0));
        let first = m.annotations[0].id;
        m.select(Some(first));
        m.reorder_picked(true);
        assert_eq!(m.annotations[1].id, first);
        m.duplicate_picked();
        assert_eq!(m.annotations.len(), 3);
        assert_eq!(m.annotations[2].bounds().x, 16.0);
    }
}
