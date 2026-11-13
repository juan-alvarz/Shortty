# Known issues and platform limits

Newest first. An issue is fixed only once it has been checked in the installed app.

## 2026-11-13 · GIF recording — new, unverified in the installed app
- **Checked:** from a shell on macOS 15.7, a build of the app's own sources recorded 2 s of a 400×300 area with
  `ScreenCapture.Recording`, stopped it, wrote the GIF (19 frames), kept it in a history and opened it in an `EditorModel`.
  `screencapture -v -R` also recorded a second, 1× display, with the pointer in it.
- **Not checked:** the flow in the installed app from the menu or a shortcut (countdown, outline, Stop Recording), and
  playing, drawing on and exporting a real recording in the editor window. The self-check never records the screen.

## 2026-11-09 · Pointer missing from screenshots — fixed, checked in the installed app
- **Symptom:** with the setting on, captures had no pointer, even a lazy area with the pointer inside it.
- **Cause:** `screencapture -C` draws nothing with `-R` on macOS 15.7. The self-check only looked at the arguments.
- **Fix:** Shortty draws `NSCursor.currentSystem` itself (`ScreenCapture.Pointer`). Confirmed by the user with a lazy area capture.

## 2026-11-09 · Thumbnail hover stuck on the wrong capture — fixed in code, unverified
- **Symptom:** hovering recent captures highlighted (and showed × on) the wrong thumbnail, and the hand cursor showed between thumbnails.
- **Cause:** each `DragSourceView` tracked `.inVisibleRect`, and inside SwiftUI a thumbnail's `visibleRect` is the whole strip
  (the toolbar drag handle's, the whole window). Every thumbnail got enter/exit for the whole strip, none while moving between them.
- **Fix:** an exact `bounds ∩ visibleRect` area, rebuilt in `updateTrackingAreas` (called as the strip scrolls).

## 2026-11-09 · Editor shortcuts type into the other app — fixed, checked with replayed clicks, not yet by hand
- **Symptom:** with the editor open, the user typed in another app, came back, pressed P: the "p" landed in the other app.
- **Cause:** AppKit's stale belief. It counts the panel as key and Shortty as active while the window server sends key
  presses to the other app, so a click asks for nothing (`makeKey` on a "key" window is a no-op). Made on purpose in the
  installed app (key focus released behind AppKit's back): the build without the fix never got the keyboard back.
  How the state arises in normal use wasn't found. Capture from the background, switching apps and clicking back, and
  another process's panel taking the keyboard all kept AppKit and the window server in step.
- **Fix:** `AppPresence.holdsKeyboard` asks the window server. `AppPresence.focus(_:)` (step back, make key, then activate
  directly) first resigns a panel that only AppKit counts as key. It runs on every capture, reopen, area selection, and
  mouse-up in the editor while Shortty isn't active or doesn't hold the keyboard.
- **Checked:** in the installed app, with a debugger-loaded probe replaying clicks through `EditorPanel.sendEvent` and
  reading `SLPSGetKeyFocusProcess`. Real key presses can't be posted from an agent's shell, so pressing P is still to do by hand.
- **Gap:** a click that drifts past 6 pt on a thumbnail starts a drag session, which eats the mouse-up, so it opens the
  capture without taking focus.

## 2026-11-03 · Delete/Backspace "doesn't remove" a selected annotation — open
- **Symptom:** the user reported Delete only working for some selections.
- **Cause:** not found. Self-checks press ⌫ and ⌦ through `EditorWindowController.handle` on every annotation kind and on a group, and all pass.
- **Suspects:** the panel didn't have keyboard focus (see 2026-11-09, shortcuts typing into the other app), or the stale build copy was running (see below).
- **Next:** reproduce in the installed app before changing code.

## 2026-11-03 · Pictures on a selected picture can't be clicked — fixed in code, unverified
- **Symptom:** small pictures and text on top of a large picture looked dead.
- **Cause:** `annotation(at:)` returned the selected box shape for any point inside its box, before checking what was above it.
- **Status:** fixed (topmost hit wins). Not yet checked in the running app.

## 2026-11-03 · Launch Services launches build copies — fixed in install.sh, unverified
- **Symptom:** Screen Recording is asked again, and Shortty is missing from the Screen Recording list even after adding it.
- **Cause:** `personal` ran `.build.noindex/Build/Products/Release/Shortty.app`, started by launchd at login, not the installed app.
- **Workaround:** `ps -axo user,pid,comm | grep Shortty` shows which copy runs. `install.sh` now unregisters build products.
- **Status:** open until checked after a re-login on both accounts.

## 2026-11-03 · Two accounts, one app — open
- **Symptom:** each macOS account needs its own Screen Recording grant, and its own login item.
- **Cause:** TCC and SMAppService are per user. Each account's copy also keeps its own Launch Services registration.
- **Workaround:** one `/Applications/Shortty.app`. Each account allows it once, launched from Finder. Delete any `~/Applications/Shortty.app` from its own account.

## 2026-10-22 · Screen Recording grant doesn't come back — recurring
- **Cause:** the grant is keyed to the bundle id and the signing requirement. `didRequestScreenCapture = 1` in defaults stops the app from asking again. Launched from an agent's shell, the prompt is attributed to that shell ("claude"), so Shortty gets no entry.
- **Workaround:** `tccutil reset ScreenCapture com.shortty.Shortty`, then `defaults delete com.shortty.Shortty didRequestScreenCapture`, then launch from Finder. If Shortty is still missing, add `/Applications/Shortty.app` with "+". Never copy `didRequestScreenCapture` when migrating defaults.
- **Status:** mitigated 2026-11-02 (the flag is cleared whenever access is granted).

## 2026-11-02 · Trackpad clicks drift 3–4 pt — fixed
- **Symptom:** clicks on history thumbnails sometimes started a drag and did nothing.
- **Fix:** a press becomes a drag only after 6 pt. A drag released back on its thumbnail counts as a click. Failed drags don't slide back (the slide-back swallowed the next clicks).

## 2026-10-29 · AppKit drops enter/exit events — fixed
- **Symptom:** a thumbnail's hover highlight and × stuck, or went missing.
- **Cause:** no exit event when a drag ends in another app, or when the view moves under a still pointer (scrolling, thumbnails shifting). Inside SwiftUI, `visibleRect` can span the whole strip.
- **Fix:** hover is computed from the pointer position, clipped to the view's bounds.

## 2026-10-29 · Non-activating panel refused keyboard focus — fixed
- **Symptom:** editor shortcuts typed into the previous app after another app was used.
- **Cause:** once Shortty is a regular but inactive app, WindowServer won't let its non-activating panels take keyboard focus.
- **Fix:** step back to accessory before a panel asks for focus. See decisions, 2026-10-29.

## Platform limits
- **`screencapture -v` (macOS 15.7):** it leaves a playable file only when its input closes or a key arrives. SIGINT and
  SIGTERM end it with no file, `-V <seconds>` ignores the input, `-t mov` fails, and `-l <window>` is ignored (the whole
  screen is recorded). So `ScreenCapture.Recording` closes a pipe to stop, and GIF Window records the window's
  rectangle without following it. The pointer is always in the video.
- **GIF memory:** ImageIO holds every frame until the file is finalized, about 12 bytes a pixel (98 full-screen frames:
  1.8 GB). `GIF.pixelBudget` scales long or large recordings down; only a frame-by-frame encoder of our own would lift it.
- **GIFs in the editor:** ImageIO decodes a GIF from its start, so jumping back with the frame slider in a long
  full-screen recording takes up to half a second (playing forward is 6 ms a frame). Copy, Save and drags of an edited
  GIF draw every frame on the main thread: a few seconds for a long one, with the editor frozen meanwhile.
- **WebP export:** ImageIO can't write WebP on macOS, so it would need a third-party encoder (not allowed).
- **Scrolling capture:** scrolling more than one frame height between two frames loses the overlap. That frame is skipped, and the content between frames can be missing.
- **Crosshair over other apps:** a background app needs the `SetsCursorInBackground` connection property to show its cursor.
- **Checked by hand only:** permissions, focus handoff and multi-display capture can't be exercised by the self-check.
