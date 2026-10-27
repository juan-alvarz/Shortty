# Working on Shortty

Free, minimal macOS screenshot app (Shottr-like). Swift 6, SwiftUI + AppKit, menu bar only (`LSUIElement`).
No third-party dependencies: prefer the platform over code, and code over libraries. Minimal, premium look:
dark chrome, custom line icons, no SF Symbols in the editor UI.

## Build, run, verify

```bash
xcodegen generate          # after adding/removing/renaming files. project.yml is the source; never edit Shortty.xcodeproj
Scripts/selfcheck.sh /tmp/shots   # drives the real editor views; prints PASS/FAIL; PNG snapshots go to the dir if given
Scripts/install.sh         # Release build → /Applications/Shortty.app, launch (--profile-only: ~/Applications)
Scripts/make-dmg.sh        # Release build → build/Shortty-X.Y.Z.dmg with the styled install window
```

Type-check under the real Swift 6 settings (the self-check compiles in Swift 5 mode):

```bash
xcodebuild -project Shortty.xcodeproj -scheme Shortty -configuration Debug -destination 'platform=macOS' -derivedDataPath .build.noindex -quiet build
```

- Every behavior change gets a check in `Scripts/SelfCheck/main.swift`; for UI changes, also look at the snapshots.
- Only run the installed app. Build copies are signed differently and lose the Screen Recording permission.
- Builds go to `.build.noindex/`, which keeps Spotlight and launchers from listing duplicate apps.
- Logs: subsystem `com.shortty.Shortty`. Use `/usr/bin/log show`, because `log` may be a shell alias.

## Map

| Path | What lives there |
|---|---|
| `Shortty/App` | Entry point and menu bar menu, `AppDelegate` + `AppPresence` (regular app while a titled window is open, menu bar only otherwise), `AppSettings` (UserDefaults-backed, `@Observable`) |
| `Shortty/Capture` | `CaptureAction` (menu items + shortcut defaults), `CaptureController` (lazy countdown flow), `ScreenCapture` (`/usr/sbin/screencapture`), `CaptureHistory` (last 20 captures in Caches, each with its saved edits as `<capture>.json`; reopen and the history strip), `RegionSelector` (area-picking overlay + countdown outline + `OverlayPanel`, the borderless panel the toast, scroll HUD and pin window share), `ScrollCapture` (session + panel), `ScrollStitcher` (frame stitching, pure and tested), `TextCapture` (text/QR to clipboard), `FloatingToast` (notice without the editor) |
| `Shortty/Hotkey` | `Hotkey` value type, `HotkeyManager` (Carbon global hotkeys, no Accessibility permission needed) |
| `Shortty/Editor` | `EditorModel` (state, undo), `Annotation` (shapes, hit test, transforms, drawing), `Arrow` (curve + 4 styles), `Text` (`TextBox` layout shared by drawing, hit test and editor), `Effects` (blur/erase, spotlight dim, magnifier), `Ruler` (same-color runs through a pixel, for the Ruler tool), `TextRecognition` (Vision line boxes for Blur Text; Text Card's colored lines), `TextCard` + `TextCardPanel` (draw the card; tune it in a sheet before it opens as a new capture), `DragHandle`, `PinWindow`, `Backdrop` (gradient card), `EditorCanvas` (NSScrollView zoom + mouse state machine + inline text editor + Live Text overlay), `EditorView` (the four layouts from shared parts: tool/output buttons, `ToolOptions`, color and backdrop pickers, selection bar, history strip), `QuickCard` (after-capture card), `Icons`, `Theme` |
| `Shortty/Settings` | Settings tabs and the shortcut recorder |
| `Scripts` | install, signing cert, icon renderer, self-check, `make-dmg.sh` (release disk image), `make-dmg-background.swift` (its window artwork) |
| `Design/AppIcon.svg` | App icon source → `swift Scripts/make-icon.swift` |
| `Design/dmg` | Disk image window background, 1× and 2× → `swift Scripts/make-dmg-background.swift` (layout shared with `make-dmg.sh`) |
| `Design/screenshots` | README images (hero 1600 px wide, layouts 1200 px; `sips -Z` to resize) |

## Code quality

Every change is the smallest one that fully works. In order: don't build it; reuse what's in the repo; use the platform
(AppKit, CoreGraphics, Vision); then write the minimum code. No helpers, options or files "for later".
- Artwork and generated assets are drawn by Swift scripts with AppKit (`make-icon.swift`, `make-dmg-background.swift`) or kept as
  SVG. No HTML/CSS, headless browsers, web fonts or other outside tools.
- Delete what a change makes obsolete (old sources, previews, docs) in the same change.
- Pure logic (geometry, pixel scans, parsing) lives in its own type so the self-check can test it without views.
- Comments say why, in one line. Match the surrounding code's naming, density and idioms.
- No Claude attribution (`Co-Authored-By`, session links) in commits or PRs.

## Recipes

**New editor tool.** Follow how `.arrow` was added:
1. Add a case to `EditorModel.Tool`.
2. Add a case to `Annotation.Shape`, then cover it in `bounds`, `contains`, `isDegenerate`, `mapped` and `CGContext.drawAnnotations`.
   Its values must be `Codable`: shapes are saved with each history capture (`SavedEdits`).
3. In `EditorCanvas`, create the shape in `mouseDown` and update it in `update(to:shift:pointerMoved:)`. Add grips if the 8-box handles don't fit.
4. Give it a default thickness in `EditorModel.toolWidths` and map the shape back to it in `Annotation.tool`.
5. Add a toolbar button (`EditorView`), an icon (`Icons.swift`, 20pt grid, 1.5pt stroke), a key in `EditorWindowController.toolKeys`, and a README row.

**New editor control.** Build it once as a view in `EditorView.swift`, then place it in each layout
(`EditorToolbar`/`OptionsStrip`, `SlimBar`/`ToolRail`/`Inspector`, `FloatingChrome`). Check every layout's
snapshot (`layout-*.png`); tooltips follow `\.tooltipEdge` (below in bars, beside the rail, above the dock).

**New setting.** Add a property to `AppSettings` (its `didSet` persists; load it in `init`), then add a control in `SettingsView`.

**New capture action.** Add a `CaptureAction` case at the end (hotkey ids follow case order), give it a title and
default hotkey, handle it in `CaptureController.perform`/`run`,
add it to the menu in `ShorttyApp`, and add a row in `ShortcutsSettingsView`.

## Rules that bit before

- **Coordinates.** Annotations live in image pixels, origin at the image's top-left; they may go negative or past the
  edges. The canvas covers `EditorModel.canvasRect` (image ∪ each annotation's `drawnBounds`): view point → image px is
  `canvasRect.origin + point × pixelsPerPoint`. `NSScrollView.magnification` is the zoom. The canvas only resizes when
  no drag or typing is in progress (`CanvasView.isBusy`), so nothing jumps under the pointer.
- **Undo.** Snapshots hold the annotations and the crop. Change `annotations` through `EditorModel` methods, or call `recordChange(from:)` after a change. Live
  drags (sliders, mouse) apply with `undoable: false`, then record one step at the end (sliders: `EditorModel.liveChange`).
- **Text editing.** `EditorModel.editingID` drives it: `beginEditing` / `setText` / `endEditing` (removes empty text,
  records one undo step). The canvas shows a TextKit 1 `NSTextView` while it's set and hides those glyphs from the
  overlay. Key shortcuts must pass through while typing (`EditorWindowController.handle`).
- **Content vs canvas.** `contentRect` = the crop if any, else image ∪ annotations (what effects like the spotlight cover); `canvasRect` adds
  the backdrop padding (what's shown and exported). `rendered` flattens the content, then adds the backdrop.
- **Draw order.** `drawAnnotations(_:on:)` paints blur/erase first, then one shared spotlight dim, then everything
  else in list order. Effects read pixels from the base image passed in, never from other annotations.
- **Blur Text / Erase Text.** Text boxes are derived data: call `refreshTextBoxes` after the area changes (the canvas
  does it on mouse up). Vision `.fast` runs synchronously there. Recognize Text is separate: Live Text (VisionKit).
- **Exclusivity crash.** Inside `edit { }`, never read `annotations` or `selectedIndex`; look the index up first.
- **Concurrency.** Default isolation is MainActor. Completion handlers from system APIs (e.g. `NSColorSampler`)
  hop back with `Task { @MainActor in … }`, carrying plain values.
- **Colors.** Use fixed sRGB colors (`Color(rgb:)`), not system colors, so exports match. Compare colors with `.hex`.
- **Selection is live.** Picking a color, arrow style or thickness also changes the selected annotation, so deselect first when that isn't wanted.
- **Editor window.** It's a non-activating `NSPanel` shown with `orderFrontRegardless`. Since macOS 14 a background
  app can't activate itself, so a normal window opened after a capture lands behind the frontmost app. Never call
  `NSApp.activate()` before showing it: a half-granted activation makes Shortty "foreground" and the window server
  then refuses the panel keyboard focus. `AppPresence` activates (and turns Shortty into a regular app) only after the panel is key.
- **Self-check side effects.** Never touch the real clipboard or Downloads in checks (`model.textPasteboard` exists for that).
- **Signing.** Keep `CODE_SIGN_IDENTITY: "Shortty Dev"` in `project.yml`. Ad-hoc signing makes macOS re-ask for Screen Recording after every build.
