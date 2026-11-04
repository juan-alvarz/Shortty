# Known issues and platform limits

Newest first. An issue is fixed only once it has been checked in the installed app.

## 2026-11-03 · Delete/Backspace "doesn't remove" a selected annotation — open
- **Symptom:** the user reported Delete only working for some selections.
- **Cause:** not found. Self-checks press ⌫ and ⌦ through `EditorWindowController.handle` on every annotation kind and on a group, and all pass.
- **Suspects:** the panel didn't have keyboard focus, or the stale build copy was running (see below).
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
- **WebP export:** ImageIO can't write WebP on macOS, so it would need a third-party encoder (not allowed).
- **Scrolling capture:** scrolling more than one frame height between two frames loses the overlap. That frame is skipped, and the content between frames can be missing.
- **Crosshair over other apps:** a background app needs the `SetsCursorInBackground` connection property to show its cursor.
- **Checked by hand only:** permissions, focus handoff and multi-display capture can't be exercised by the self-check.
