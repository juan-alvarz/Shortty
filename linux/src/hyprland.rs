//! What Shortty adds to Hyprland while it runs, since Wayland gives apps neither global shortcuts nor window
//! placement: binds for the shortcuts (`hyprctl eval` for Lua configs, `hyprctl keyword` for classic ones) and a
//! rule that floats the Settings window. Both are added again after every config reload.

use crate::settings::Settings;
use gtk::{gio, glib, prelude::*};
use std::{cell::RefCell, process::Command};

/// Every bind Shortty added carries this description, so its own binds are told apart from the user's.
const TAG: &str = "Shortty: ";

thread_local! {
    /// The combos bound right now.
    static BOUND: RefCell<Vec<String>> = const { RefCell::new(Vec::new()) };
}

/// Binds the shortcuts and adds the window rule, now and after each config reload.
pub fn setup() {
    add_window_rules();
    apply(&Settings::load());
    watch_reloads();
}

/// Settings floats in the middle of the screen, like the macOS Settings window. Lua configs only: the classic
/// rule syntax changed between versions, and a tiled Settings window still works.
fn add_window_rules() {
    // The editor floats centered too, at the size it asks for (it fits the capture).
    hyprctl(&[
        "eval",
        r#"hl.window_rule({ name = "shortty-editor", match = { class = "com.shortty.Shortty", title = "Shortty" }, float = true, center = true })"#,
    ]);
    let rule = r#"hl.window_rule({ name = "shortty-settings", match = { class = "com.shortty.Shortty", title = "Shortty Settings" }, float = true, center = true, size = "540 680" })"#;
    hyprctl(&["eval", rule]);
}

/// Binds every shortcut in the settings, replacing what was bound before.
pub fn apply(settings: &Settings) {
    unbind_all();
    let exe = std::env::current_exe().map(|p| p.to_string_lossy().into_owned()).unwrap_or("shortty".into());
    for (action, combo) in &settings.shortcuts {
        // A Shortty that crashed or was killed left its binds behind, and Hyprland keeps duplicates: each would fire.
        unbind(combo);
        let command = format!("'{exe}' {}", action.name());
        let lua = format!(
            "hl.bind({}, hl.dsp.exec_cmd({}), {{ description = {} }})",
            lua_string(combo),
            lua_string(&command),
            lua_string(&format!("{TAG}{}", action.title()))
        );
        let classic = format!("{}, exec, {command}", classic_combo(combo));
        if hyprctl(&["eval", &lua]) || hyprctl(&["keyword", "bind", &classic]) {
            BOUND.with_borrow_mut(|bound| bound.push(combo.clone()));
        } else {
            glib::g_warning!("shortty", "couldn't bind {combo}");
        }
    }
    crate::tray::refresh(); // the menu shows the shortcuts
}

/// Removes Shortty's binds (while recording a new one, and on quit).
pub fn unbind_all() {
    for combo in BOUND.take() {
        unbind(&combo);
    }
}

fn unbind(combo: &str) {
    let lua = format!("hl.unbind({})", lua_string(combo));
    let _ = hyprctl(&["eval", &lua]) || hyprctl(&["keyword", "unbind", &classic_combo(combo)]);
}

/// Hyprland reloads its config on every save, dropping runtime binds and rules: listen on its event socket and add them again.
fn watch_reloads() {
    let (Ok(runtime), Ok(instance)) = (std::env::var("XDG_RUNTIME_DIR"), std::env::var("HYPRLAND_INSTANCE_SIGNATURE")) else {
        return glib::g_warning!("shortty", "not running under Hyprland: no global shortcuts");
    };
    let path = std::path::Path::new(&runtime).join("hypr").join(instance).join(".socket2.sock");
    glib::spawn_future_local(async move {
        let address = gio::UnixSocketAddress::new(&path);
        let Ok(connection) = gio::SocketClient::new().connect_future(&address).await else { return };
        let events = gio::DataInputStream::new(&connection.input_stream());
        while let Ok(Some(line)) = events.read_line_utf8_future(glib::Priority::DEFAULT).await {
            if line.starts_with("configreloaded>>") {
                add_window_rules();
                apply(&Settings::load());
            }
        }
    });
}

/// What else in Hyprland already uses `combo` (its description, or dispatcher and argument), if anything.
pub fn taken_by(combo: &str) -> Option<String> {
    let json = Command::new("hyprctl").args(["-j", "binds"]).output().ok()?.stdout;
    conflict(&String::from_utf8_lossy(&json), combo)
}

fn hyprctl(args: &[&str]) -> bool {
    Command::new("hyprctl").args(args).output().is_ok_and(|o| o.status.success() && o.stdout.trim_ascii() == b"ok")
}

fn lua_string(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}

/// "SUPER + SHIFT + 4" → "SUPER SHIFT, 4", the classic config's form.
fn classic_combo(combo: &str) -> String {
    let parts: Vec<&str> = combo.split(" + ").collect();
    let (key, mods) = parts.split_last().unwrap_or((&"", &[]));
    format!("{}, {key}", mods.join(" "))
}

/// Hyprland's modifier mask bits, in the order combos are written.
const MODIFIERS: [(&str, u64); 4] = [("SUPER", 64), ("CTRL", 4), ("ALT", 8), ("SHIFT", 1)];

/// A combo from a key press, or None when it needs a modifier and has none. Print and F-keys work alone,
/// everything else needs Super, Ctrl or Alt so typing never triggers a capture (the macOS app asks for ⌘, ⌥ or ⌃).
pub fn combo(held: &[&str], key: &str) -> Option<String> {
    let alone = key == "Print" || key.strip_prefix('F').is_some_and(|n| n.parse::<u8>().is_ok());
    if !alone && !held.iter().any(|m| ["SUPER", "CTRL", "ALT"].contains(m)) {
        return None;
    }
    let key = if key.chars().count() == 1 { key.to_uppercase() } else { key.to_string() };
    let mut parts: Vec<&str> = MODIFIERS.iter().map(|(name, _)| *name).filter(|m| held.contains(m)).collect();
    parts.push(&key);
    Some(parts.join(" + "))
}

fn conflict(binds_json: &str, combo: &str) -> Option<String> {
    let parts: Vec<&str> = combo.split(" + ").collect();
    let (key, mods) = parts.split_last()?;
    let mask: u64 = MODIFIERS.iter().filter(|(name, _)| mods.contains(name)).map(|(_, bit)| bit).sum();
    let binds: serde_json::Value = serde_json::from_str(binds_json).ok()?;
    binds.as_array()?.iter().find_map(|b| {
        let description = b["description"].as_str().unwrap_or("");
        let same = b["modmask"].as_u64() == Some(mask) && b["key"].as_str()?.eq_ignore_ascii_case(key);
        (same && !description.starts_with(TAG)).then(|| match description {
            "" => format!("{} {}", b["dispatcher"].as_str().unwrap_or(""), b["arg"].as_str().unwrap_or("")).trim().to_string(),
            d => d.to_string(),
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn combos_need_a_modifier_except_print_and_f_keys() {
        assert_eq!(combo(&["SHIFT", "SUPER"], "4").as_deref(), Some("SUPER + SHIFT + 4"));
        assert_eq!(combo(&["CTRL"], "a").as_deref(), Some("CTRL + A"));
        assert_eq!(combo(&["SHIFT"], "a"), None);
        assert_eq!(combo(&[], "Print").as_deref(), Some("Print"));
        assert_eq!(combo(&[], "F12").as_deref(), Some("F12"));
        assert_eq!(combo(&[], "Fn"), None);
    }

    #[test]
    fn classic_form() {
        assert_eq!(classic_combo("SUPER + SHIFT + 4"), "SUPER SHIFT, 4");
        assert_eq!(classic_combo("Print"), ", Print");
    }

    #[test]
    fn conflicts_skip_shorttys_own_binds() {
        let binds = r#"[
            {"modmask":64,"key":"Print","description":"Take a screenshot","dispatcher":"exec","arg":"screenshot.sh"},
            {"modmask":65,"key":"4","description":"","dispatcher":"movetoworkspace","arg":"4"},
            {"modmask":76,"key":"F12","description":"Shortty: Capture Region","dispatcher":"exec","arg":"shortty region"}
        ]"#;
        assert_eq!(conflict(binds, "SUPER + Print").as_deref(), Some("Take a screenshot"));
        assert_eq!(conflict(binds, "SUPER + SHIFT + 4").as_deref(), Some("movetoworkspace 4"));
        assert_eq!(conflict(binds, "SUPER + CTRL + ALT + F12"), None);
        assert_eq!(conflict(binds, "CTRL + Print"), None);
    }
}
