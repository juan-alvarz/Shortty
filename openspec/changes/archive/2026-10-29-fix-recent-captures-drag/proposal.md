# Proposal

## Why

Since thumbnails in the recent captures strip moved to the AppKit drag source (1.3.5), two things regressed: a dragged
capture arrives without its edits (the raw screenshot file is handed over), and the hover state (highlight and ×)
sticks or goes missing, because it only follows enter/exit events that AppKit skips when a drag ends elsewhere or the
strip scrolls.

## What Changes

- Dragging captures out of the strip hands over each one with its saved edits drawn in, as the thumbnail shows it.
  The open capture's newest edits are saved first so they go along. Captures with no edits are handed over as-is.
- Dropping a thumbnail onto the canvas still inserts it as a picture (now with its edits); only the toolbar drag
  handle's own picture is refused.
- Thumbnail hover follows where the pointer actually is: it clears after a drag ends elsewhere, when the strip
  scrolls, and when thumbnails shift.
- Clicking the thumbnail of the capture already open no longer reloads it (which wiped its undo history).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `capture-history`: the recent captures strip requirement now says what a drag carries, how hover behaves, and what
  clicking the open capture does.

## Impact

- `Shortty/Editor/EditorView.swift` (`HistoryStrip`, `HistoryThumb`), `Shortty/Editor/DragHandle.swift`
  (`DragSource`, `DragSourceView`), `Shortty/Editor/EditorCanvas.swift` (drop filter).
- `Scripts/SelfCheck/main.swift`: new checks for drag-with-edits, canvas drop and hover.
- README recent captures line.
