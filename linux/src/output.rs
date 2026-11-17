use crate::settings::Settings;
use gtk::{gio, glib, prelude::*};
use std::path::Path;

/// After a capture: copy and save as the settings say; a notification when the editor doesn't open.
pub async fn deliver(path: &Path, settings: &Settings, notice: bool) {
    let mut done = Vec::new();
    if settings.copy_after_capture {
        match copy(path).await {
            Ok(()) => done.push("Copied"),
            Err(error) => return notify_failure("Copy", &error),
        }
    }
    if settings.save_after_capture {
        let name = format!("shortty-{}-image.png", glib::DateTime::now_local().unwrap().format("%Y%m%d-%H%M%S").unwrap());
        let target = settings.save_folder.join(name);
        let saved = std::fs::create_dir_all(&settings.save_folder).and_then(|_| std::fs::copy(path, &target));
        match saved {
            Ok(_) => done.push("Saved"),
            Err(error) => return notify_failure("Save", &error.to_string()),
        }
    }
    if notice {
        let title = if done.is_empty() { "Captured".to_string() } else { done.join(" and ") };
        notify(&title, &path.file_name().unwrap_or_default().to_string_lossy(), Some(path));
    }
}

/// A desktop notification, with the picture as its icon when there is one.
pub fn notify(title: &str, body: &str, picture: Option<&Path>) {
    let notification = gio::Notification::new(title);
    notification.set_body(Some(body));
    if let Some(picture) = picture {
        notification.set_icon(&gio::FileIcon::new(&gio::File::for_path(picture)));
    }
    send(notification);
}

/// The clipboard through `wl-copy`, which keeps serving it after we move on. GTK's own clipboard needs a
/// surface with keyboard focus on Wayland, and right after a capture there is none.
pub async fn copy(path: &Path) -> Result<(), String> {
    let launcher = gio::SubprocessLauncher::new(gio::SubprocessFlags::STDERR_PIPE);
    launcher.set_stdin_file_path(Some(path));
    let process = launcher.spawn(&["wl-copy".as_ref(), "--type".as_ref(), "image/png".as_ref()]).map_err(|e| e.to_string())?;
    process.wait_check_future().await.map_err(|e| e.to_string())
}

/// The theme's camera shutter, like the macOS capture sound.
pub fn shutter() {
    let flags = gio::SubprocessFlags::STDOUT_SILENCE | gio::SubprocessFlags::STDERR_SILENCE;
    if let Ok(process) = gio::Subprocess::newv(&["canberra-gtk-play".as_ref(), "-i".as_ref(), "camera-shutter".as_ref()], flags) {
        glib::spawn_future_local(async move {
            let _ = process.wait_future().await;
        });
    }
}

pub fn notify_failure(what: &str, error: &str) {
    let notification = gio::Notification::new(&format!("{what} failed"));
    notification.set_body(Some(error));
    send(notification);
}

fn send(notification: gio::Notification) {
    if let Some(app) = gio::Application::default() {
        app.send_notification(None, &notification);
    }
}
