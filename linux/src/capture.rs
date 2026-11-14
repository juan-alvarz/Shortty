use crate::{countdown, editor, geometry, history, output, selector, settings::Settings};
use gtk::{gio, glib, prelude::*};
use std::{ffi::OsStr, path::Path, time::Duration};

/// What can be triggered from the tray or `shortty <name>` (a Hyprland bind). Titles match the macOS app.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Action {
    Region,
    Screen,
    ActiveWindow,
    Reopen,
    LazyRegion,
    LazyScreen,
    Window,
}

impl Action {
    pub const ALL: [Action; 7] =
        [Action::Region, Action::Window, Action::Screen, Action::ActiveWindow, Action::Reopen, Action::LazyRegion, Action::LazyScreen];

    pub fn name(self) -> &'static str {
        match self {
            Action::Region => "region",
            Action::Screen => "screen",
            Action::ActiveWindow => "active-window",
            Action::Reopen => "reopen",
            Action::LazyRegion => "lazy-region",
            Action::LazyScreen => "lazy-screen",
            Action::Window => "window",
        }
    }

    pub fn title(self) -> &'static str {
        match self {
            Action::Region => "Capture Region",
            Action::Screen => "Capture Screen",
            Action::ActiveWindow => "Capture Active Window",
            Action::Reopen => "Reopen Last Capture",
            Action::LazyRegion => "Lazy Region",
            Action::LazyScreen => "Lazy Screen",
            Action::Window => "Capture Window",
        }
    }

    /// What it does, under its name in Settings → Shortcuts.
    pub fn summary(self) -> &'static str {
        match self {
            Action::Region => "Drag over an area. Space switches to clicking a window, Esc cancels.",
            Action::Window => "Click a window to capture it.",
            Action::Screen => "The monitor with focus.",
            Action::ActiveWindow => "The window you're in, instantly.",
            Action::Reopen => "Brings back the editor with the latest capture and its edits.",
            Action::LazyRegion => "Pick the area first, then a countdown runs and that area is captured.",
            Action::LazyScreen => "A countdown, then the monitor with focus.",
        }
    }

    pub fn is_lazy(self) -> bool {
        matches!(self, Action::LazyRegion | Action::LazyScreen)
    }

    pub fn parse(name: &str) -> Option<Action> {
        Action::ALL.into_iter().find(|a| a.name() == name)
    }
}

/// Runs on the main thread. `from_menu` waits for the tray menu to close so it isn't in the picture.
pub fn perform(action: Action, from_menu: bool) {
    if action == Action::Reopen {
        return editor::reopen_last();
    }
    glib::spawn_future_local(async move {
        if from_menu {
            glib::timeout_future(Duration::from_millis(250)).await;
        }
        let settings = Settings::load();
        match capture(action, &settings).await {
            Ok(Some(path)) => {
                if settings.capture_sound {
                    output::shutter();
                }
                history::trim(settings.history_limit);
                if settings.opens_editor {
                    editor::open(&path);
                }
                output::deliver(&path, &settings, !settings.opens_editor).await;
            }
            Ok(None) => {} // cancelled
            Err(error) => {
                glib::g_warning!("shortty", "{}: {error}", action.title());
                output::notify_failure(action.title(), &error);
            }
        }
    });
}

/// The capture's file in the history, or None when the user cancelled.
async fn capture(action: Action, settings: &Settings) -> Result<Option<std::path::PathBuf>, String> {
    let path = history::next_path();
    match action {
        Action::Region => {
            let Some(picked) = selector::select(settings.shows_cursor, settings.selection_rgb(), false).await? else { return Ok(None) };
            picked.cropped().save_to_png(&path).map_err(|e| e.to_string())?;
        }
        Action::Window => {
            // Like the macOS window capture, without the pointer.
            let Some(picked) = selector::select(false, settings.selection_rgb(), true).await? else { return Ok(None) };
            picked.cropped().save_to_png(&path).map_err(|e| e.to_string())?;
        }
        Action::Screen => {
            // The focused monitor, which follows the pointer in Hyprland's default setup.
            let json = run(&["hyprctl", "-j", "monitors"]).await?;
            let name = geometry::focused_monitor(&json).ok_or("no focused monitor")?;
            grim(&["-o", &name], &path, settings.shows_cursor).await?;
        }
        Action::ActiveWindow => {
            let json = run(&["hyprctl", "-j", "activewindow"]).await?;
            let geometry = geometry::window_geometry(&json).ok_or("no active window")?;
            grim(&["-g", &geometry], &path, settings.shows_cursor).await?;
        }
        Action::Reopen => return Ok(None), // not a capture: `perform` opens the editor
        Action::LazyRegion => {
            // The area is picked on a frozen screen, then captured live once the countdown ends.
            let Some(picked) = selector::select(false, settings.selection_rgb(), false).await? else { return Ok(None) };
            if !countdown::run(&picked.monitor, Some(picked.rect()), settings.lazy_delay, settings.selection_rgb()).await {
                return Ok(None);
            }
            let r = picked.rect_in_layout();
            let geometry = format!("{},{} {}x{}", r.x.round(), r.y.round(), r.width.round(), r.height.round());
            grim(&["-g", &geometry], &path, settings.shows_cursor).await?;
        }
        Action::LazyScreen => {
            let json = run(&["hyprctl", "-j", "monitors"]).await?;
            let name = geometry::focused_monitor(&json).ok_or("no focused monitor")?;
            let display = gtk::gdk::Display::default().ok_or("no display")?;
            let monitor =
                display.monitors().iter::<gtk::gdk::Monitor>().flatten().find(|m| m.connector().as_deref() == Some(name.as_str()));
            let monitor = monitor.ok_or("focused monitor not found")?;
            if !countdown::run(&monitor, None, settings.lazy_delay, settings.selection_rgb()).await {
                return Ok(None);
            }
            // The monitor with focus when the countdown ends, like the macOS "display under the pointer".
            let json = run(&["hyprctl", "-j", "monitors"]).await?;
            let name = geometry::focused_monitor(&json).ok_or("no focused monitor")?;
            grim(&["-o", &name], &path, settings.shows_cursor).await?;
        }
    }
    Ok(Some(path))
}

pub async fn grim(args: &[&str], path: &Path, cursor: bool) -> Result<(), String> {
    let mut argv = vec!["grim"];
    if cursor {
        argv.push("-c");
    }
    argv.extend(args);
    argv.push(path.to_str().ok_or("path isn't UTF-8")?);
    run(&argv).await.map(|_| ())
}

/// Runs a command and returns its standard output, or its error output when it fails.
pub async fn run(argv: &[&str]) -> Result<String, String> {
    let argv: Vec<&OsStr> = argv.iter().map(OsStr::new).collect();
    let flags = gio::SubprocessFlags::STDOUT_PIPE | gio::SubprocessFlags::STDERR_PIPE;
    let process = gio::Subprocess::newv(&argv, flags).map_err(|e| e.to_string())?;
    let (stdout, stderr) = process.communicate_future(None).await.map_err(|e| e.to_string())?;
    let text = |b: Option<glib::Bytes>| b.map(|b| String::from_utf8_lossy(&b).trim().to_string()).unwrap_or_default();
    if process.is_successful() { Ok(text(stdout)) } else { Err(text(stderr)) }
}
