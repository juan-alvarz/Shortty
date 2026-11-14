use gtk::glib;
use std::{fs, path::PathBuf};

/// Recent captures in `~/.cache/shortty/History`, named like the macOS app's (`yyyyMMdd-HHmmss-SSS.png`) so
/// sorting by name sorts by time, with each capture's `.json` edits and `.preview.png` next to it.
pub fn folder() -> PathBuf {
    glib::user_cache_dir().join("shortty/History")
}

/// A free name for a new capture, creating the folder if it's gone.
pub fn next_path() -> PathBuf {
    let _ = fs::create_dir_all(folder());
    loop {
        let now = glib::DateTime::now_local().expect("local time");
        let name = format!("{}-{:03}.png", now.format("%Y%m%d-%H%M%S").unwrap(), now.microsecond() / 1000);
        let path = folder().join(name);
        if !path.exists() {
            return path;
        }
    }
}

/// The kept captures, newest first.
pub fn captures() -> Vec<PathBuf> {
    let mut names: Vec<String> = names().into_iter().filter(|n| is_capture(n)).collect();
    names.sort_by(|a, b| b.cmp(a));
    names.into_iter().map(|n| folder().join(n)).collect()
}

/// How many captures are kept.
pub fn count() -> usize {
    names().iter().filter(|n| is_capture(n)).count()
}

/// Deletes one capture with its edits and preview.
pub fn remove(capture: &std::path::Path) {
    for file in [capture.to_path_buf(), capture.with_extension("json"), capture.with_extension("preview.png")] {
        let _ = fs::remove_file(file);
    }
}

/// Settings → Delete All: every capture with its edits and previews.
pub fn remove_all() {
    let _ = fs::remove_dir_all(folder());
}

fn names() -> Vec<String> {
    fs::read_dir(folder()).into_iter().flatten().flatten().filter_map(|e| e.file_name().into_string().ok()).collect()
}

fn is_capture(name: &str) -> bool {
    name.ends_with(".png") && !name.ends_with(".preview.png") || name.ends_with(".gif")
}

/// Removes the oldest captures past `limit`, with their edits and previews.
pub fn trim(limit: usize) {
    for name in extras(names(), limit) {
        let stem = name.rsplit_once('.').map_or(name.as_str(), |(stem, _)| stem);
        for file in [name.clone(), format!("{stem}.json"), format!("{stem}.preview.png")] {
            let _ = fs::remove_file(folder().join(file));
        }
    }
}

/// The captures (PNG or GIF, not previews or edits) beyond the newest `limit`.
fn extras(mut names: Vec<String>, limit: usize) -> Vec<String> {
    names.retain(|n| is_capture(n));
    names.sort_by(|a, b| b.cmp(a));
    names.split_off(limit.min(names.len()))
}

#[cfg(test)]
mod tests {
    #[test]
    fn extras_are_the_oldest_captures() {
        let names = [
            "20261113-100000-000.png",
            "20261113-100000-000.json",
            "20261113-100000-000.preview.png",
            "20261113-110000-000.gif",
            "20261113-120000-000.png",
        ];
        let extras = super::extras(names.iter().map(|s| s.to_string()).collect(), 1);
        assert_eq!(extras, ["20261113-110000-000.gif", "20261113-100000-000.png"]);
    }
}
