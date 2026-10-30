# Tasks

## 1. Verify capture specs against the code

- [x] 1.1 Check `screen-capture` against `CaptureAction`, `CaptureController`, `ScreenCapture` and `RegionSelector`; verify by fixing any requirement the code contradicts
- [x] 1.2 Check `scrolling-capture` against `ScrollCapture` and `ScrollStitcher`; verify the stitching scenarios match the existing "frames:" and "stitched height" self-checks
- [x] 1.3 Check `text-capture` against `TextCapture` and `FloatingToast`; verify the scenarios match the "Capture Text reads text" and notice self-checks
- [x] 1.4 Check `global-shortcuts` against `Hotkey`, `HotkeyManager`, `AppSettings.hotkeys` and the Shortcuts tab; verify "no defaults" and case-order ids in the code

## 2. Verify editor specs against the code

- [x] 2.1 Check `annotation-editor` against `EditorModel`, `Annotation`, `EditorCanvas` and `EditorWindowController.toolKeys`; verify every tool and key listed exists
- [x] 2.2 Check `text-recognition` and `text-card` against `Effects`, `TextRecognition`, `TextCard` and `TextCardPanel`; verify by matching the Blur Text, Copy All and text card self-checks
- [x] 2.3 Check `image-export` against `EditorModel.copy/save`, `ImageExport`, `DragHandle`, `PinWindow` and `Backdrop`; verify the save file name in code
- [x] 2.4 Check `editor-layouts` against `EditorLayout` and `EditorView`; verify all four layouts and the tooltip edges exist

## 3. Verify app specs against the code

- [x] 3.1 Check `after-capture` against `AfterCapture`, `QuickCard` and the after-capture flow; verify defaults (editor, Copy on, Save off) in `AppSettings.init`
- [x] 3.2 Check `capture-history` against `CaptureHistory` and the history strip; verify the 20-item limit, edits file, reopen and hide setting in code
- [x] 3.3 Check `app-presence` and `app-settings` against `AppDelegate`, `AppPresence`, `ShorttyApp` and `SettingsView`; verify every listed preference exists with its stated default

## 4. Integration checks

- [x] 4.1 Run `openspec validate baseline-architecture --strict` and verify it passes
- [x] 4.2 Self-check coverage: confirm each spec has scenarios backed by `Scripts/SelfCheck/main.swift` or is a manual-only behavior (permissions, focus, displays); no new check needed since no behavior changes
- [x] 4.3 Run `Scripts/selfcheck.sh` and the Swift 6 `xcodebuild` type-check from AGENTS.md; verify both pass with no app code changed (`git diff --stat Shortty Scripts` is empty)

## Workflow follow-up

- Archive the change so the 13 specs land in `openspec/specs/`.
- Verify with `openspec list --specs` and `openspec validate --specs --strict`.
