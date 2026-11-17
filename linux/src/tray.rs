use crate::capture::{self, Action};
use gtk::{cairo, gio, glib, prelude::*};
use ksni::blocking::TrayMethods;

/// The tray icon (StatusNotifierItem, shown by waybar's tray), standing in for the macOS menu bar item.
struct Tray;

impl ksni::Tray for Tray {
    const MENU_ON_ACTIVATE: bool = true;

    fn id(&self) -> String {
        "shortty".into()
    }

    fn title(&self) -> String {
        "Shortty".into()
    }

    fn icon_pixmap(&self) -> Vec<ksni::Icon> {
        [22, 44].map(icon).into()
    }

    fn menu(&self) -> Vec<ksni::MenuItem<Self>> {
        use ksni::menu::{MenuItem, StandardItem};
        let mut items: Vec<MenuItem<Self>> = Vec::new();
        if crate::countdown::RUNNING.load(std::sync::atomic::Ordering::Relaxed) {
            let cancel = Box::new(|_: &mut Self| on_main(crate::countdown::cancel));
            items.push(StandardItem { label: "Cancel Countdown".into(), activate: cancel, ..Default::default() }.into());
            items.push(MenuItem::Separator);
        }
        // Each action shows its shortcut, like the macOS menu bar menu.
        let shortcuts = crate::settings::Settings::load().shortcuts;
        items.extend(Action::ALL.into_iter().map(|action| {
            let activate = Box::new(move |_: &mut Self| on_main(move || capture::perform(action, true)));
            let shortcut = shortcuts.get(&action).map(|combo| vec![menu_shortcut(combo)]).unwrap_or_default();
            StandardItem { label: action.title().into(), activate, shortcut, ..Default::default() }.into()
        }));
        items.push(MenuItem::Separator);
        let settings = Box::new(|_: &mut Self| on_main(crate::settings_window::present));
        items.push(StandardItem { label: "Settings…".into(), activate: settings, ..Default::default() }.into());
        let quit = Box::new(|_: &mut Self| on_main(|| gio::Application::default().into_iter().for_each(|app| app.quit())));
        items.push(StandardItem { label: "Quit Shortty".into(), activate: quit, ..Default::default() }.into());
        items
    }
}

/// "CTRL + SHIFT + R" as the menu protocol spells it: ["Control", "Shift", "R"].
fn menu_shortcut(combo: &str) -> Vec<String> {
    combo
        .split(" + ")
        .map(|part| match part {
            "SUPER" => "Super",
            "CTRL" => "Control",
            "ALT" => "Alt",
            "SHIFT" => "Shift",
            key => key,
        })
        .map(String::from)
        .collect()
}

/// Menu clicks arrive on the tray's D-Bus thread; GTK only runs on the main one.
fn on_main(work: impl FnOnce() + Send + 'static) {
    glib::MainContext::default().invoke(work);
}

thread_local! {
    static HANDLE: std::cell::OnceCell<ksni::blocking::Handle<Tray>> = const { std::cell::OnceCell::new() };
}

/// Rebuilds the menu after the state it shows changed (a countdown started or ended).
pub fn refresh() {
    HANDLE.with(|h| {
        if let Some(handle) = h.get() {
            handle.update(|_| {});
        }
    });
}

pub fn spawn() {
    // Shortty can start before waybar (at login, or while it restarts): the icon then appears once the tray does.
    match Tray.assume_sni_available(true).spawn() {
        Ok(handle) => HANDLE.with(|h| {
            let _ = h.set(handle);
        }),
        Err(error) => glib::g_warning!("shortty", "no tray icon: {error}"),
    }
}

/// The macOS menu bar mark (Icon.menuBar: the app icon's cat), in white for a dark bar, `size` pixels square.
fn icon(size: i32) -> ksni::Icon {
    let mut surface = cairo::ImageSurface::create(cairo::Format::ARgb32, size, size).expect("surface");
    {
        let cr = cairo::Context::new(&surface).expect("context");
        // On the 1024 grid of Design/AppIcon.svg, scaled so the 548-wide mark fills 15.2 of 18 units.
        let unit = size as f64 / 18.0;
        let scale = 15.2 / 548.0 * unit;
        cr.translate(1.4 * unit - 238.0 * scale, 1.5 * unit - 250.0 * scale);
        cr.scale(scale, scale);
        cr.move_to(238.0, 500.0);
        cr.line_to(266.0, 250.0);
        cr.line_to(414.0, 368.0);
        cr.curve_to(479.33, 345.33, 544.67, 345.33, 610.0, 368.0); // the Mac's quadratic through (512, 334)
        cr.line_to(758.0, 250.0);
        cr.line_to(786.0, 500.0);
        let sides: [fn(f64) -> f64; 2] = [|v| v, |v| 1024.0 - v]; // left cheek, then the mirrored right one
        for x in sides {
            cr.move_to(x(238.0), 624.0);
            cr.line_to(x(238.0), 672.0);
            cr.curve_to(x(238.0), 742.0, x(290.0), 790.0, x(362.0), 790.0);
            cr.line_to(x(420.0), 790.0);
        }
        cr.identity_matrix();
        cr.set_line_width(1.6 * unit);
        cr.set_line_cap(cairo::LineCap::Round);
        cr.set_line_join(cairo::LineJoin::Round);
        cr.set_source_rgb(1.0, 1.0, 1.0);
        let _ = cr.stroke();
    }
    surface.flush();
    let stride = surface.stride() as usize;
    let pixels = surface.data().expect("pixels");
    let mut data = Vec::with_capacity((size * size * 4) as usize);
    for row in pixels.chunks(stride) {
        for p in row[..size as usize * 4].chunks(4) {
            // Cairo: premultiplied B, G, R, A in memory. SNI: straight A, R, G, B.
            let (b, g, r, a) = (p[0] as u32, p[1] as u32, p[2] as u32, p[3] as u32);
            let straight = |c: u32| (c * 255).checked_div(a).unwrap_or(0) as u8;
            data.extend([a as u8, straight(r), straight(g), straight(b)]);
        }
    }
    ksni::Icon { width: size, height: size, data }
}

#[cfg(test)]
mod tests {
    #[test]
    fn shortcuts_in_menu_terms() {
        assert_eq!(super::menu_shortcut("SUPER + CTRL + SHIFT + 4"), ["Super", "Control", "Shift", "4"]);
        assert_eq!(super::menu_shortcut("Print"), ["Print"]);
    }
}
