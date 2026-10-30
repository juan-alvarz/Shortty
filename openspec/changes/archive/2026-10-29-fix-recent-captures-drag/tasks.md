# Tasks

## 1. Drag carries the edits

- [x] 1.1 Render each dragged capture with its saved edits into the drag folder (`HistoryStrip.exported`), flushing the open capture's edits first; verify with a self-check that an edited capture's dragged file shows its annotation and an unedited one is the original file
- [x] 1.2 Replace the canvas's drag-folder path filter with a flag on the drag handle's source; verify with a self-check that the canvas accepts a strip drag and refuses the handle's own picture
- [x] 1.3 Update the README recent captures line; verify it says drags keep edits

## 2. Hover and click

- [x] 2.1 Make `DragSourceView` hover follow the pointer position (enter/exit, scroll, drag end); verify with a self-check that hover clears when the pointer is outside after a drag ends
- [x] 2.2 Skip reloading when the open capture's thumbnail is clicked; verify with a self-check that undo survives that click

## 3. Integration checks

- [x] 3.1 Run `Scripts/selfcheck.sh /tmp/shortty-shots` and the Swift 6 `xcodebuild` type-check; verify both pass and `history-expanded.png` looks right
- [x] 3.2 Run `openspec validate fix-recent-captures-drag --strict`; verify it passes

## Workflow follow-up

- Try the installed app by hand: drag edited thumbnails into Finder and a browser, hover across the strip after a drag.
- Archive the change.
