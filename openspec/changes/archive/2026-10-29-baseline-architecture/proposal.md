# Proposal

## Why

Shortty has no written behavior contract: what each feature promises lives in the README, AGENTS.md and the self-check.
Adopting OpenSpec needs a baseline set of capability specs that describe what already ships (version 1.3.5), so future
changes can be proposed as deltas against them instead of against an unwritten understanding.

## What Changes

- Document the current, shipped behavior of Shortty as capability specs. No app code, settings or UI change.
- Record the architecture map (modules, data flow, persistence, the rules that shape every change) in `design.md`,
  which stays with the archived change as the reference for future proposals.
- Seed `openspec/config.yaml` with the project constraints an agent cannot infer from the code.

## Capabilities

### New Capabilities

- `screen-capture`: Region, window, active window, screen and repeat-last-region captures, the area selector and lazy (countdown) shots.
- `scrolling-capture`: Capturing a fixed area while the page scrolls and stitching the frames into one tall image.
- `text-capture`: Reading the text or QR code in a dragged area straight to the clipboard, without opening the editor.
- `global-shortcuts`: User-recorded system-wide shortcuts for every capture action.
- `annotation-editor`: The editor window, its drawing tools, selection, editing, undo and the growing canvas.
- `text-recognition`: On-device text recognition used by Blur Text, Erase Text and Recognize Text (Live Text).
- `text-card`: Redrawing recognized text as a window-like card that keeps each word's color, tuned in a sheet before it opens.
- `image-export`: Copy, Save, drag and drop, pin to screen and the gradient backdrop.
- `after-capture`: What appears right after a capture (editor, quick card or notice) and the automatic copy/save.
- `capture-history`: The last 20 captures with their saved edits, reopen, and the recent captures strip.
- `editor-layouts`: The four arrangements of the editor's chrome.
- `app-presence`: Living in the menu bar, becoming a regular app while a window is open, and opening existing images.
- `app-settings`: Persisted preferences and the Settings window.

### Modified Capabilities

None: no specs exist yet.

## Impact

- New files only: `openspec/` (config, specs, archived change), `.claude/` and `.agents/` OpenSpec skills and commands.
- No change to `Shortty/`, `Scripts/`, `project.yml` or the release process. The self-check must still pass unchanged.
