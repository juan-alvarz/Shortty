mod capture;
mod countdown;
mod editor;
mod geometry;
mod history;
mod hyprland;
mod output;
mod selector;
mod settings;
mod settings_window;
mod tray;

use gtk::{gio, glib, prelude::*};

const APP_ID: &str = "com.shortty.Shortty";

fn main() -> glib::ExitCode {
    // A panic inside a GTK callback aborts the app; keep its message where it can be read afterwards.
    let default_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let log = glib::user_cache_dir().join("shortty/crash.log");
        let line = format!("{} {info}\n", glib::DateTime::now_local().ok().and_then(|d| d.format_iso8601().ok()).unwrap_or_default());
        let _ = std::fs::create_dir_all(log.parent().unwrap());
        let _ = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(log)
            .and_then(|mut f| std::io::Write::write_all(&mut f, line.as_bytes()));
        default_hook(info);
    }));
    let app = adw::Application::builder().application_id(APP_ID).flags(gio::ApplicationFlags::HANDLES_COMMAND_LINE).build();
    app.connect_startup(|app| {
        // Lives in the tray, so no open window is what keeps it running.
        std::mem::forget(app.hold());
        tray::spawn();
        hyprland::setup();
    });
    app.connect_shutdown(|_| hyprland::unbind_all());
    // A second `shortty <command>` (a Hyprland bind) hands its arguments to the running one over D-Bus.
    app.connect_command_line(|app, line| {
        let args: Vec<String> = line.arguments().iter().skip(1).map(|a| a.to_string_lossy().into_owned()).collect();
        match args.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
            [] => {}
            ["quit"] => app.quit(),
            ["settings"] => settings_window::present(),
            ["edit", file] => editor::open(&line.create_file_for_arg(file).path().unwrap_or_default()),
            [name] if capture::Action::parse(name).is_some() => capture::perform(capture::Action::parse(name).unwrap(), false),
            _ => {
                let names: Vec<&str> = capture::Action::ALL.iter().map(|a| a.name()).collect();
                line.printerr_literal(&format!("usage: shortty [{}|settings|quit] or shortty edit FILE\n", names.join("|")));
                return glib::ExitCode::from(2);
            }
        }
        glib::ExitCode::SUCCESS
    });
    app.run()
}
