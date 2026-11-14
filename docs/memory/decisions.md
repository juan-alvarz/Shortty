# Decisions

Newest first. Each: what was decided, why, and what was rejected.

## 2026-11-14 · Linux editor: Classic layout first, Mac JSON, typing at the end
- **Decision:** the Linux editor ports the macOS model and drawing as they are (shapes, arrow and callout geometry,
  palette, per-tool widths, live options, undo snapshots) and only the Classic layout. Edits are saved in the macOS
  `SavedEdits` JSON (`{"arrow": {"start": [x, y], …}}`, `_0` for unlabeled values); shapes it can't draw yet are
  skipped when reading. Text is typed through GTK's input method (accents and dead keys) with the caret always at
  the end; the canvas draws it, no text view on top. The editor and Settings float through runtime window rules.
- **Why:** the user asked for the editor and shortcuts to act like the Mac's; one layout covers it before the other
  three. A text view over the canvas would need its font scaled with the zoom.
- **Rejected:** a GTK `TextView` overlay for typing (for now); a new JSON format (the history couldn't move between
  the apps).

- **Decision:** Settings → Shortcuts records a combo and Shortty binds it in the running Hyprland with
  `hyprctl eval 'hl.bind(...)'` (`hyprctl keyword bind` for classic configs), tagged with the description
  "Shortty: <action>". It binds again on `configreloaded` (Hyprland's event socket), unbinds while recording and on
  quit, and refuses combos another bind already uses (unbinding a combo removes every bind on it). The Settings window
  floats through a runtime `hl.window_rule`. Settings uses libadwaita (grouped rows, like the macOS grouped form).
- **Why:** the user wanted shortcuts to work like the Mac's: picked in Settings, none by default, no config editing.
- **Rejected:** the GlobalShortcuts portal (Hyprland ignores the app's preferred keys; the user would still edit
  their config); writing into the user's Hyprland config files; regex anchors and escapes in the eval'd rule (`\.` is
  an invalid Lua escape, and the rule silently never matched).
 in `linux/`, Hyprland first
- **Decision:** the port is a Rust crate in `linux/` of this repo (gtk4-rs, gtk4-layer-shell, ksni for the tray).
  The macOS code stays where it is. Hyprland on Wayland only for now: `grim` captures, `hyprctl` finds the focused
  monitor and window, `wl-copy` holds the clipboard, layer-shell draws overlays. Commands (`shortty region`, …) are
  bound in Hyprland's config and reach the running instance through GApplication's D-Bus single instance.
  Region capture freezes every output with `grim -o` first and crops the picked rect from that picture.
  Settings are a GKeyFile, `~/.config/shortty/settings.ini`; history uses the macOS file names in `~/.cache/shortty/History`.
- **Why:** almost all of the Swift code is AppKit/SwiftUI/Vision, so it's a rewrite either way; Rust has the most mature
  GTK4, layer-shell and tray bindings, and the toolchain was already installed. One repo keeps the README, artwork and
  memory shared.
- **Rejected:** Swift + GTK bindings (young bindings, little code to share); a separate repo; moving the macOS app into
  `mac/` (breaks `project.yml`, scripts and history for symmetry); app-level global hotkeys (Wayland has none);
  GTK's clipboard (needs a focused surface, and there is none right after a capture); the Screenshot portal
  (interactive, slower; worth it only for GNOME/KDE later).

## 2026-11-13 · GIF recordings: one length, the lazy countdown, edited like a screenshot
- **Decision:** GIF Region, Screen and Window run the lazy countdown, then record a fixed rectangle with `screencapture -v -R`
  for Settings → Shortcuts → Length (Stop Recording in the menu, or the same shortcut, ends it sooner and keeps it).
  `GIF` turns the movie into a 10 fps GIF at 1× with ImageIO. It's then a capture like any other: kept in the history as
  `<timestamp>.gif`, opened in the editor or on the card. The editor shows one frame, with a play button and a frame
  slider in a bar under the picture; edits don't change over time and are drawn on every frame when the GIF is copied,
  saved or dragged out.
- **Why:** the user wanted the simplest recording (a maximum length and the lazy countdown, nothing else), then expected
  the GIF in the recent captures, edited "as a normal PNG". `image.rendering(annotations, crop:, backdrop:)` already draws
  the edits on any picture, so a GIF is that call once a frame.
- **Rejected:** a length per mode; ScreenCaptureKit (`SCStream` follows a moving window, but it's a recorder to write and
  keep); our own GIF encoder (it would lift the memory budget, see known issues); GIFs saved straight to the save folder
  with their own card, outside the editor and the history (built first, then replaced); edits that appear partway
  through or follow motion (a timeline); the playback controls inside each layout's bars (one bar under the canvas
  serves all four).

## 2026-11-09 · Pointer setting skips quiet frames
- **Decision:** Settings → Show the pointer in screenshots: Shortty draws `NSCursor.currentSystem` into area, lazy area,
  repeat, screen and active-window captures (`ScreenCapture.Pointer`), taken at the shutter; a dragged area takes it from
  before the selector opened. Not into `frame(of:)`, window-by-click or inserted pictures.
- **Why:** a pointer in scrolling-capture frames breaks stitching, and in Capture Text it can cover the text being read.
- **Rejected:** `screencapture -C`. On macOS 15.7 it drew nothing with `-R` (checked in the installed app, lazy area with the
  pointer inside), and it isn't allowed with `-i`.

## 2026-11-09 · Report records events instead of asking for steps
- **Decision:** `BugReport` always keeps the editor's last 100 presses and keys in memory. Report in the strip starts a
  recording (drags, scrolling and every thumbnail's place too); Stop saves it all to a text file and shows it in Finder.
- **Why:** the dead-click and lost-keyboard bugs come and go; the user can't make them on demand, and a guess at the cause was wrong before.
- **Rejected:** reading the system log afterwards (needs the time it happened, and says nothing about where views were);
  a one-shot "save the trace" button (the user wanted to record while trying again).

## 2026-11-09 · The window server says who has the keyboard
- **Decision:** `AppPresence.holdsKeyboard` reads the key focus process from the window server (private `SLPSGetKeyFocusProcess`,
  found with `dlsym`; `NSApp.isActive` if it's gone). Focus code goes by it, and resigns key before asking again.
- **Why:** `isKeyWindow` and `isActive` stayed true after the keyboard went to another app, and no AppKit call re-asks while they are.
- **Rejected:** trusting AppKit's flags; `makeKey` alone (a no-op on a window it counts as key); stepping back to menu bar
  only before `makeKey` (same no-op).

## 2026-11-09 · Recent captures: arrows, pointing hand, own tracking areas
- **Decision:** ‹ and › beside the strip open the next newer or older capture (skipping unreadable ones) and scroll it into view.
  Thumbnails show the pointing hand, readable or not, and the closed hand only while pressed. The toolbar drag handle keeps the open hand.
- **Why:** the user wanted a way to move between captures that doesn't depend on hovering thumbnails, and a click cursor, not a drag one.
- **Rejected:** an animated `scrollTo`; it didn't land on the target when steps came quickly.

## 2026-11-09 · Strip and canvas listen only over themselves
- **Decision:** every `DragSourceView` tracks exactly its visible box. The canvas keeps `.inVisibleRect`: it sits in an AppKit
  scroll view, whose clip view bounds `visibleRect` correctly. The self-check asserts neither reaches over the other.
- **Rejected:** moving the strip into its own window or hosting view. The overlap was the tracking areas, not the view tree.

## 2026-11-03 · Project memory instead of OpenSpec
- **Decision:** behavior lives in the README and the self-check; `docs/memory/` keeps only decisions, known issues and critical changes.
- **Why:** the specs restated the README and self-check, and every change needed a propose/apply/archive round.
- **Rejected:** keeping OpenSpec capability specs and per-change deltas.

## 2026-11-03 · One install in /Applications for every account
- **Decision:** `Scripts/install.sh` always installs to `/Applications/Shortty.app`, readable by all accounts (`chmod -R go+rX`).
- **Why:** with a copy per account plus build copies, each profile ran a different copy and the Screen Recording grant never matched the one running.
- **Rejected:** `--profile-only` (`~/Applications`, one copy per account). Removed.

## 2026-11-03 · install.sh unregisters build copies from Launch Services
- **Decision:** after installing, `lsregister -u` every `.build.noindex/Build/Products/*/Shortty.app`.
- **Why:** login items and `open` launched the Release build copy, which has no grant ("Shortty isn't in the list").
- **Rejected:** relying on the `.noindex` folder name. It only hides builds from Spotlight; Launch Services still registers them.

## 2026-11-03 · History size is a setting, trimmed on the next capture
- **Decision:** Settings → Keep, 1–50 captures, default 20. Lowering it removes the oldest extras when the next capture arrives.
- **Why:** an accidental change in the field shouldn't delete captures on the spot.
- **Rejected:** pruning as soon as the value is lowered.

## 2026-11-03 · Area selection picks only what's fully inside, pictures included
- **Decision:** a marquee selects annotations whose bounds lie entirely inside it.
- **Why:** "touching" selection picked far more than intended, so Delete removed things the user didn't mean.
- **Rejected:** touching selection that left pictures out. Pictures had been excluded only to stop marquee-Delete from removing them.

## 2026-11-03 · Unreadable history captures stay until the user deletes them
- **Decision:** a capture whose file can't be read shows a red "!" and an always-visible ×. Clicking it does nothing.
- **Why:** auto-removing on click looked like a dead thumbnail that vanished, and it deleted data without asking.
- **Rejected:** `history.remove(url)` when loading fails.

## 2026-11-03 · Clicks go to the topmost annotation
- **Decision:** a selected box shape (rectangle, picture, blur, spotlight) is grabbed anywhere inside its box only where nothing above it is hit.
- **Why:** a selected big picture swallowed every click on pictures and text placed on top of it, so they looked dead.

## 2026-10-29 · Panel focus handoff on mouse-up
- **Decision:** the focus handoff (regular + inactive → accessory, then make the panel key) runs on mouse-up, not mouse-down.
  Since 2026-11-09 it's `AppPresence.focus(_:)`, which also activates directly instead of waiting for `didBecomeKey`.
- **Why:** switching activation policy mid-press cancels the drag (a text callout's aimed tail).
- **Rejected:** `NSApp.activate()` before showing the panel (a half-granted activation leaves the panel without focus); the mouse-down handoff.

## 2026-10-29 · Strip drags hand over rendered PNGs
- **Decision:** a dragged history capture is a temporary PNG with its edits drawn in. The canvas refuses only the drag handle's own picture, flagged on its `DragSourceView`.
- **Rejected:** handing over the raw capture file (lost the edits); filtering canvas drops by the drag folder's path.

## 2026-10-29 · About tab folded into General
- **Decision:** the icon, name and version head Settings → General; the version links to `releases/tag/v<version>`.
- **Why:** a whole tab for one line.
