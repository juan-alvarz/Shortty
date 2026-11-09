# Decisions

Newest first. Each: what was decided, why, and what was rejected.

## 2026-11-09 · Pointer setting skips quiet frames
- **Decision:** Settings → Show the pointer in screenshots adds `-C` to every `capture()` (area, repeat, window, screen, inserted picture), not to `frame(of:)`.
- **Why:** a pointer in scrolling-capture frames breaks stitching, and in Capture Text it can cover the text being read.

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
- **Decision:** `AppPresence.prepareForPanelFocus()` (regular + inactive → accessory, then make the panel key) runs on mouse-up, not mouse-down.
- **Why:** switching activation policy mid-press cancels the drag (a text callout's aimed tail).
- **Rejected:** `NSApp.activate()` before showing the panel (a half-granted activation leaves the panel without focus); the mouse-down handoff.

## 2026-10-29 · Strip drags hand over rendered PNGs
- **Decision:** a dragged history capture is a temporary PNG with its edits drawn in. The canvas refuses only the drag handle's own picture, flagged on its `DragSourceView`.
- **Rejected:** handing over the raw capture file (lost the edits); filtering canvas drops by the drag folder's path.

## 2026-10-29 · About tab folded into General
- **Decision:** the icon, name and version head Settings → General; the version links to `releases/tag/v<version>`.
- **Why:** a whole tab for one line.
