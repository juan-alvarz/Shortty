use crate::capture::Action;
use gtk::glib;
use std::{collections::HashMap, path::PathBuf};

/// `~/.config/shortty/settings.ini`, read at each capture and written by the Settings window.
/// Missing keys take the macOS app's defaults.
pub struct Settings {
    /// Open the editor after a capture (the macOS default), or only show a notification.
    pub opens_editor: bool,
    pub copy_after_capture: bool,
    pub save_after_capture: bool,
    pub save_folder: PathBuf,
    pub shows_cursor: bool,
    pub capture_sound: bool,
    /// "#RRGGBB" for the selection outline; None is Shortty's orange (Linux has no accent color to follow).
    pub selection_color: Option<String>,
    pub history_limit: usize,
    /// The editor's recent captures bar is open (the macOS app remembers it too).
    pub history_expanded: bool,
    /// Seconds before a lazy shot.
    pub lazy_delay: u32,
    /// Hyprland key combos, "SUPER + SHIFT + 4". None set out of the box.
    pub shortcuts: HashMap<Action, String>,
}

pub const HISTORY_LIMIT_RANGE: std::ops::RangeInclusive<usize> = 1..=50;
const GROUP: &str = "Shortty";
const SHORTCUTS: &str = "Shortcuts";

impl Settings {
    fn file() -> PathBuf {
        glib::user_config_dir().join("shortty/settings.ini")
    }

    pub fn downloads() -> PathBuf {
        glib::user_special_dir(glib::UserDirectory::Downloads).unwrap_or_else(glib::home_dir)
    }

    pub fn load() -> Settings {
        let file = glib::KeyFile::new();
        let _ = file.load_from_file(Self::file(), glib::KeyFileFlags::NONE);
        let flag = |key, default| file.boolean(GROUP, key).unwrap_or(default);
        let limit = file.integer(GROUP, "history-limit").map_or(20, |n| n.max(0) as usize);
        Settings {
            opens_editor: file.string(GROUP, "after-capture").map_or(true, |s| s != "nothing"),
            copy_after_capture: flag("copy-after-capture", true),
            save_after_capture: flag("save-after-capture", false),
            save_folder: file.string(GROUP, "save-folder").map_or_else(|_| Self::downloads(), |s| PathBuf::from(s.as_str())),
            shows_cursor: flag("shows-cursor", false),
            capture_sound: flag("capture-sound", true),
            selection_color: file.string(GROUP, "selection-color").ok().map(String::from),
            history_limit: limit.clamp(*HISTORY_LIMIT_RANGE.start(), *HISTORY_LIMIT_RANGE.end()),
            history_expanded: flag("history-expanded", false),
            lazy_delay: file.integer(GROUP, "lazy-delay").map_or(3, |n| n.clamp(1, 30) as u32),
            shortcuts: Action::ALL
                .into_iter()
                .filter_map(|a| file.string(SHORTCUTS, a.name()).ok().map(|combo| (a, combo.to_string())))
                .collect(),
        }
    }

    pub fn save(&self) {
        let file = glib::KeyFile::new();
        file.set_string(GROUP, "after-capture", if self.opens_editor { "editor" } else { "nothing" });
        file.set_boolean(GROUP, "copy-after-capture", self.copy_after_capture);
        file.set_boolean(GROUP, "save-after-capture", self.save_after_capture);
        file.set_string(GROUP, "save-folder", &self.save_folder.to_string_lossy());
        file.set_boolean(GROUP, "shows-cursor", self.shows_cursor);
        file.set_boolean(GROUP, "capture-sound", self.capture_sound);
        if let Some(color) = &self.selection_color {
            file.set_string(GROUP, "selection-color", color);
        }
        file.set_integer(GROUP, "history-limit", self.history_limit as i32);
        file.set_integer(GROUP, "lazy-delay", self.lazy_delay as i32);
        file.set_boolean(GROUP, "history-expanded", self.history_expanded);
        for (action, combo) in &self.shortcuts {
            file.set_string(SHORTCUTS, action.name(), combo);
        }
        let _ = std::fs::create_dir_all(Self::file().parent().unwrap());
        if let Err(error) = file.save_to_file(Self::file()) {
            glib::g_warning!("shortty", "settings not saved: {error}");
        }
    }

    /// The selection outline as RGB 0–1.
    pub fn selection_rgb(&self) -> (f64, f64, f64) {
        let parsed = self.selection_color.as_deref().and_then(|hex| gtk::gdk::RGBA::parse(hex).ok());
        parsed.map_or(ACCENT, |c| (c.red() as f64, c.green() as f64, c.blue() as f64))
    }
}

/// `Theme.accent` in the macOS app.
pub const ACCENT: (f64, f64, f64) = (1.0, 0.42, 0.24);
