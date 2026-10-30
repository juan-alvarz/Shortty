# Tasks

## 1. Focus handoff

- [x] 1.1 Add `AppPresence.prepareForPanelFocus()` (regular + inactive → accessory) and call it from `EditorWindowController.present`, a mouse-down on `EditorPanel` and the selector's key panel; verify with a self-check that a regular inactive Shortty steps back and the editor ends key with Shortty regular again
- [x] 1.2 Update the AGENTS.md editor window rule; verify it names the regular-but-inactive case

## 2. Integration checks

- [x] 2.1 Run `Scripts/selfcheck.sh` and the Swift 6 `xcodebuild` type-check; verify both pass
- [x] 2.2 Run `openspec validate fix-editor-keyboard-focus --strict`; verify it passes

## Workflow follow-up

- Try the installed app: keep the editor open, type in another app, capture again and press T; click the editor and press A.
- Archive the change.
