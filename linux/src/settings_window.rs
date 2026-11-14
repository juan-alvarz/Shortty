//! Settings → General and Shortcuts, laid out like the macOS app's grouped tabs.

use crate::{
    capture::Action,
    history, hyprland,
    settings::{HISTORY_LIMIT_RANGE, Settings},
};
use adw::prelude::*;
use gtk::{gdk, gio, glib};
use std::{cell::RefCell, path::PathBuf, rc::Rc};

type Shared = Rc<RefCell<Settings>>;

/// "#FF6B3D", Shortty's orange: picking it again goes back to no custom color.
const DEFAULT_COLOR: &str = "#FF6B3D";

thread_local! {
    static WINDOW: glib::WeakRef<adw::Window> = glib::WeakRef::new();
}

/// Opens the window, or brings the open one forward.
pub fn present() {
    if let Some(window) = WINDOW.with(|w| w.upgrade()) {
        return window.present();
    }
    let settings: Shared = Rc::new(RefCell::new(Settings::load()));
    let toasts = adw::ToastOverlay::new();
    let stack = adw::ViewStack::new();
    stack.add_titled_with_icon(&general(&settings), Some("general"), "General", "preferences-system-symbolic");
    let keyboard = "preferences-desktop-keyboard-shortcuts-symbolic";
    stack.add_titled_with_icon(&shortcuts_page(&settings, &toasts), Some("shortcuts"), "Shortcuts", keyboard);
    let header = adw::HeaderBar::new();
    header.set_title_widget(Some(&adw::ViewSwitcher::builder().stack(&stack).policy(adw::ViewSwitcherPolicy::Wide).build()));
    let view = adw::ToolbarView::new();
    view.add_top_bar(&header);
    view.set_content(Some(&stack));
    toasts.set_child(Some(&view));

    let window = adw::Window::builder().title("Shortty Settings").default_width(540).default_height(680).content(&toasts).build();
    window.set_application(gio::Application::default().and_downcast_ref::<gtk::Application>());
    WINDOW.with(|w| w.set(Some(&window)));
    window.present();
}

fn general(settings: &Shared) -> adw::PreferencesPage {
    let page = adw::PreferencesPage::new();

    let about = adw::PreferencesGroup::new();
    let version = concat!("Version ", env!("CARGO_PKG_VERSION"), " for Linux (preview)");
    let row = adw::ActionRow::builder().title("Shortty").subtitle(version).build();
    let svg = glib::Bytes::from_static(include_bytes!("../../Design/AppIcon.svg"));
    if let Ok(icon) = gdk::Texture::from_bytes(&svg) {
        let image = gtk::Image::from_paintable(Some(&icon));
        image.set_pixel_size(48);
        row.add_prefix(&image);
    }
    about.add(&row);
    page.add(&about);

    let basics = adw::PreferencesGroup::new();
    basics.add(&switch(settings, "Play sound when capturing", |s| &mut s.capture_sound));
    basics.add(&switch(settings, "Show the pointer in screenshots", |s| &mut s.shows_cursor));
    page.add(&basics);

    let capturing = adw::PreferencesGroup::builder().title("Capturing").build();
    capturing.add(&selection_color_row(settings));
    page.add(&capturing);

    let saving = adw::PreferencesGroup::builder().title("Saving").build();
    saving.add(&save_folder_row(settings));
    page.add(&saving);

    let after = adw::PreferencesGroup::builder().title("After a capture").build();
    let show = adw::ComboRow::builder()
        .title("Show")
        .subtitle("A notification when the editor is off. Copy and Save happen right away either way.")
        .model(&gtk::StringList::new(&["Editor", "Notification"]))
        .selected(if settings.borrow().opens_editor { 0 } else { 1 })
        .build();
    show.connect_selected_notify({
        let settings = settings.clone();
        move |row| {
            let mut settings = settings.borrow_mut();
            settings.opens_editor = row.selected() == 0;
            settings.save();
        }
    });
    after.add(&show);
    after.add(&switch(settings, "Copy to the clipboard", |s| &mut s.copy_after_capture));
    after.add(&switch(settings, "Save to the folder", |s| &mut s.save_after_capture));
    page.add(&after);

    page.add(&recent_captures_group(settings));
    page
}

/// A switch bound to one setting, saved as it flips.
fn switch(settings: &Shared, title: &str, field: fn(&mut Settings) -> &mut bool) -> adw::SwitchRow {
    let row = adw::SwitchRow::builder().title(title).active(*field(&mut settings.borrow_mut())).build();
    let settings = settings.clone();
    row.connect_active_notify(move |row| {
        let mut settings = settings.borrow_mut();
        *field(&mut settings) = row.is_active();
        settings.save();
    });
    row
}

fn suffix_button(label: &str) -> gtk::Button {
    gtk::Button::builder().label(label).valign(gtk::Align::Center).build()
}

/// The selection overlay's outline: Shortty's orange until another is picked.
fn selection_color_row(settings: &Shared) -> adw::ActionRow {
    let row = adw::ActionRow::builder().title("Selection color").subtitle("The outline while selecting an area.").build();
    let picker = gtk::ColorDialogButton::new(Some(gtk::ColorDialog::builder().with_alpha(false).build()));
    picker.set_valign(gtk::Align::Center);
    let (r, g, b) = settings.borrow().selection_rgb();
    picker.set_rgba(&gdk::RGBA::new(r as f32, g as f32, b as f32, 1.0));
    let reset = suffix_button("Use Default");
    reset.set_visible(settings.borrow().selection_color.is_some());
    picker.connect_rgba_notify({
        let (settings, reset) = (settings.clone(), reset.clone());
        move |picker| {
            let c = picker.rgba();
            let byte = |v: f32| (v * 255.0).round() as u8;
            let hex = format!("#{:02X}{:02X}{:02X}", byte(c.red()), byte(c.green()), byte(c.blue()));
            let mut settings = settings.borrow_mut();
            settings.selection_color = (hex != DEFAULT_COLOR).then_some(hex);
            settings.save();
            reset.set_visible(settings.selection_color.is_some());
        }
    });
    reset.connect_clicked({
        let picker = picker.clone();
        move |_| picker.set_rgba(&gdk::RGBA::parse(DEFAULT_COLOR).unwrap())
    });
    row.add_suffix(&reset);
    row.add_suffix(&picker);
    row
}

/// Where Save writes: shows the folder, lets you pick another, or go back to Downloads.
fn save_folder_row(settings: &Shared) -> adw::ActionRow {
    let row = adw::ActionRow::builder().title("Save to").build();
    let choose = suffix_button("Choose…");
    let downloads = suffix_button("Use Downloads");
    let set: Rc<dyn Fn(PathBuf)> = Rc::new({
        let (settings, row, downloads) = (settings.clone(), row.clone(), downloads.clone());
        move |folder: PathBuf| {
            let home = glib::home_dir();
            let shown = folder.strip_prefix(&home).map_or(folder.display().to_string(), |p| format!("~/{}", p.display()));
            row.set_subtitle(&shown);
            downloads.set_visible(folder != Settings::downloads());
            let mut settings = settings.borrow_mut();
            if settings.save_folder != folder {
                settings.save_folder = folder;
                settings.save();
            }
        }
    });
    let folder = settings.borrow().save_folder.clone(); // released before `set` borrows it mutably
    set(folder);
    choose.connect_clicked({
        let (settings, set) = (settings.clone(), set.clone());
        move |button| {
            let dialog = gtk::FileDialog::builder()
                .title("Where should Shortty save screenshots?")
                .accept_label("Use Folder")
                .initial_folder(&gio::File::for_path(&settings.borrow().save_folder))
                .build();
            let window = button.root().and_downcast::<gtk::Window>();
            let set = set.clone();
            glib::spawn_future_local(async move {
                if let Some(folder) = dialog.select_folder_future(window.as_ref()).await.ok().and_then(|f| f.path()) {
                    set(folder);
                }
            });
        }
    });
    downloads.connect_clicked(move |_| set(Settings::downloads()));
    row.add_suffix(&downloads);
    row.add_suffix(&choose);
    row
}

/// How many captures to keep, and a way to delete them.
fn recent_captures_group(settings: &Shared) -> adw::PreferencesGroup {
    let group = adw::PreferencesGroup::builder().title("Recent captures").build();
    let (low, high) = (*HISTORY_LIMIT_RANGE.start() as f64, *HISTORY_LIMIT_RANGE.end() as f64);
    let keep = adw::SpinRow::with_range(low, high, 1.0);
    keep.set_title("Keep");
    keep.set_subtitle("Up to 50. Fewer removes the oldest with your next capture.");
    keep.set_value(settings.borrow().history_limit as f64);
    keep.connect_value_notify({
        let settings = settings.clone();
        move |keep| {
            let mut settings = settings.borrow_mut();
            settings.history_limit = keep.value() as usize;
            settings.save();
        }
    });
    group.add(&keep);

    let kept = adw::ActionRow::builder().title(format!("{} kept", history::count())).build();
    let delete = suffix_button("Delete All");
    delete.add_css_class("destructive-action");
    delete.set_sensitive(history::count() > 0);
    delete.connect_clicked({
        let kept = kept.clone();
        move |delete| {
            history::remove_all();
            kept.set_title("0 kept");
            delete.set_sensitive(false);
        }
    });
    kept.add_suffix(&delete);
    group.add(&kept);
    group
}

/// Every action with what it does and its shortcut (none until you record one).
fn shortcuts_page(settings: &Shared, toasts: &adw::ToastOverlay) -> adw::PreferencesPage {
    let page = adw::PreferencesPage::new();
    let lazy = adw::PreferencesGroup::builder().title("Lazy shots").build();
    let group = adw::PreferencesGroup::builder()
        .title("Capture")
        .description(
            "Shortty adds these to Hyprland while it runs. Click, then press a combination with Super, Ctrl or Alt \
                      (Print and F-keys work alone). Backspace clears, Esc cancels.",
        )
        .build();
    // The action being recorded and its button.
    let recording: Rc<RefCell<Option<(Action, gtk::Button)>>> = Default::default();

    for action in Action::ALL {
        let row = adw::ActionRow::builder().title(action.title()).subtitle(action.summary()).build();
        let button = suffix_button(&label(settings.borrow().shortcuts.get(&action)));
        button.connect_clicked({
            let (settings, recording) = (settings.clone(), recording.clone());
            move |button| {
                let previous = recording.take();
                if let Some((other, other_button)) = &previous {
                    other_button.set_label(&label(settings.borrow().shortcuts.get(other)));
                }
                if previous.is_some_and(|(other, _)| other == action) {
                    return hyprland::apply(&settings.borrow()); // a second click stops recording
                }
                hyprland::unbind_all(); // so existing combos don't fire while re-binding
                button.set_label("Press shortcut…");
                *recording.borrow_mut() = Some((action, button.clone()));
            }
        });
        row.add_suffix(&button);
        if action.is_lazy() { lazy.add(&row) } else { group.add(&row) }
    }
    let delay = adw::SpinRow::with_range(1.0, 30.0, 1.0);
    delay.set_title("Delay");
    delay.set_subtitle("Seconds before the lazy shot. Cancel Countdown is in the tray menu while it runs.");
    delay.set_value(settings.borrow().lazy_delay as f64);
    delay.connect_value_notify({
        let settings = settings.clone();
        move |delay| {
            let mut settings = settings.borrow_mut();
            settings.lazy_delay = delay.value() as u32;
            settings.save();
        }
    });
    lazy.add(&delay);
    page.add(&group);
    page.add(&lazy);

    let keys = gtk::EventControllerKey::new();
    keys.set_propagation_phase(gtk::PropagationPhase::Capture);
    keys.connect_key_pressed({
        let (settings, recording, toasts) = (settings.clone(), recording.clone(), toasts.clone());
        move |keys, keyval, keycode, state| {
            let Some((action, button)) = recording.borrow().clone() else { return glib::Propagation::Proceed };
            match keyval {
                gdk::Key::Escape => {}
                gdk::Key::BackSpace | gdk::Key::Delete => {
                    let mut settings = settings.borrow_mut();
                    settings.shortcuts.remove(&action);
                    settings.save();
                }
                _ => {
                    // The key without Shift's effect: Shift+4 is "4", as Hyprland's binds spell it.
                    let display = keys.widget().map_or_else(|| gdk::Display::default().unwrap(), |w| w.display());
                    let base = display.translate_key(keycode, gdk::ModifierType::empty(), keys.group() as i32);
                    let Some(name) = base.and_then(|(key, ..)| key.name()) else { return glib::Propagation::Stop };
                    if is_modifier(&name) {
                        return glib::Propagation::Stop; // wait for the rest of the combination
                    }
                    let held: Vec<&str> = [
                        (gdk::ModifierType::SUPER_MASK, "SUPER"),
                        (gdk::ModifierType::CONTROL_MASK, "CTRL"),
                        (gdk::ModifierType::ALT_MASK, "ALT"),
                        (gdk::ModifierType::SHIFT_MASK, "SHIFT"),
                    ]
                    .into_iter()
                    .filter(|(mask, _)| state.contains(*mask))
                    .map(|(_, name)| name)
                    .collect();
                    let Some(combo) = hyprland::combo(&held, &name) else { return glib::Propagation::Stop };
                    let other = settings.borrow().shortcuts.iter().find(|(a, c)| **a != action && **c == combo).map(|(a, _)| *a);
                    if let Some(other) = other {
                        toasts.add_toast(adw::Toast::new(&format!("{} is already set for {}.", label(Some(&combo)), other.title())));
                        return glib::Propagation::Stop;
                    }
                    if let Some(owner) = hyprland::taken_by(&combo) {
                        toasts.add_toast(adw::Toast::new(&format!("{} is used in your Hyprland config: {owner}.", label(Some(&combo)))));
                        return glib::Propagation::Stop;
                    }
                    let mut settings = settings.borrow_mut();
                    settings.shortcuts.insert(action, combo);
                    settings.save();
                }
            }
            recording.take();
            button.set_label(&label(settings.borrow().shortcuts.get(&action)));
            hyprland::apply(&settings.borrow());
            glib::Propagation::Stop
        }
    });
    page.add_controller(keys);

    // Closing the window mid-recording puts the shortcuts back.
    page.connect_unmap({
        let settings = settings.clone();
        move |_| {
            if recording.take().is_some() {
                hyprland::apply(&settings.borrow());
            }
        }
    });
    page
}

/// "SUPER + SHIFT + 4" shown as "Super + Shift + 4".
fn label(combo: Option<&String>) -> String {
    let Some(combo) = combo else { return "Record Shortcut".into() };
    combo.replace("SUPER", "Super").replace("CTRL", "Ctrl").replace("ALT", "Alt").replace("SHIFT", "Shift")
}

fn is_modifier(key: &str) -> bool {
    key.ends_with("_L") || key.ends_with("_R") || key.ends_with("_Lock") || key.starts_with("ISO_")
}
