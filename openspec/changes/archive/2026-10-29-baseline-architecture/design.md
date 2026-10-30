# Design

## Context

See proposal.md for why. This change writes no app code: it records the architecture as it stands at version 1.3.5
so later proposals can point at it. AGENTS.md remains the source of truth for build commands, file map and coding
rules; this document explains how the pieces fit and which capability spec each one serves.

## Architecture map

### Runtime shape

A single macOS 14+ process, Swift 6 with MainActor as the default isolation. SwiftUI builds the views; AppKit owns
windows, panels, event handling and the canvas. No third-party code, no network, no server.

```
 Menu bar menu ─┐                                  ┌─> Editor window (NSPanel) ─> Copy / Save / Drag / Pin
 Global hotkey ─┼─> CaptureController ─> capture ──┼─> Quick card
 (Carbon)       │   (lazy countdown)     (PNG)     └─> Floating notice
 Finder Open ───┘                         │
                                          └─> CaptureHistory (Caches/History, last 20 + edits JSON)
```

### Modules and the capabilities they serve

| Module (`Shortty/…`) | Responsibility | Capability specs |
|---|---|---|
| `App/ShorttyApp`, `AppDelegate` | Entry point, menu bar menu, opening image files | app-presence |
| `App/AppPresence` | Switches between menu-bar-only and regular app as titled windows open and close; returns focus to the previous app | app-presence |
| `App/AppSettings` | `@Observable` preferences, each persisted to UserDefaults in `didSet`, clamped on load | app-settings, after-capture, editor-layouts |
| `Hotkey/Hotkey`, `HotkeyManager` | Key combo value type; Carbon `RegisterEventHotKey`, so no Accessibility permission | global-shortcuts |
| `Capture/CaptureAction` | Every user-triggerable action: title, summary, hotkey id from case order | screen-capture, global-shortcuts |
| `Capture/CaptureController` | Runs an action: selection, countdown, capture, then the after-capture flow | screen-capture, after-capture |
| `Capture/ScreenCapture` | Wraps `/usr/sbin/screencapture` for areas, windows and displays | screen-capture |
| `Capture/RegionSelector` | Area/window picking overlay, countdown outline, and `OverlayPanel` shared by toast, scroll HUD and pin | screen-capture, scrolling-capture |
| `Capture/ScrollCapture` + `ScrollStitcher` | Scroll session panel; pure row-hash stitcher (tested without views) | scrolling-capture |
| `Capture/TextCapture` | Vision text + QR detection to the clipboard | text-capture |
| `Capture/FloatingToast` | Click-through notice that fades on its own | text-capture, after-capture, image-export |
| `Capture/CaptureHistory` | `<timestamp>.png` + `<timestamp>.json` (edits) + `.preview.png` in Caches | capture-history |
| `Editor/EditorModel` | Editor state: annotations, crop, selection, tool, undo snapshots, export | annotation-editor, image-export |
| `Editor/Annotation`, `Arrow`, `Text`, `Effects`, `Ruler` | Shape data (Codable), hit tests, transforms, drawing; effects read only the base image | annotation-editor |
| `Editor/EditorCanvas` | `NSScrollView` zoom, mouse state machine, inline TextKit 1 editor, Live Text overlay | annotation-editor, text-recognition |
| `Editor/TextRecognition` | Vision line boxes (Blur/Erase Text) and colored lines (Text Card) | text-recognition, text-card |
| `Editor/TextCard`, `TextCardPanel` | Card drawing; tuning sheet before it opens as a new capture | text-card |
| `Editor/EditorView`, `Icons`, `Theme` | Shared chrome parts assembled into four layouts; custom line icons; fixed colors | editor-layouts, annotation-editor |
| `Editor/EditorWindowController` | The single non-activating editor panel and its key handling | annotation-editor, app-presence |
| `Editor/ImageExport`, `DragHandle`, `PinWindow`, `Backdrop`, `QuickCard` | PNG writing and clipboard, drag source, pin, gradient card, after-capture card | image-export, after-capture |
| `Settings/` | General, Shortcuts and About tabs; shortcut recorder | app-settings, global-shortcuts |

### Data and coordinates

- Captures are PNG files; edits are a JSON list of Codable annotations plus the crop, saved beside each capture.
- Annotations live in image pixels, origin top-left, and may extend past the image. The canvas is the image united
  with every annotation's drawn bounds, plus backdrop padding; export renders the same rectangle.
- Undo stores snapshots of annotations and crop; live drags record one step at the end.

### Verification

`Scripts/selfcheck.sh` compiles the app sources with `Scripts/SelfCheck/main.swift` and drives the real models and
views (275 checks at 1.3.5), writing PNG snapshots of every layout. It never touches the real clipboard or Downloads.

## Goals / Non-Goals

**Goals:**
- One spec per durable capability, written as user-visible behavior with testable scenarios.
- Specs match what ships today; where the README and code disagree, the code wins.

**Non-Goals:**
- No behavior change, refactor or new self-check in this change.
- No spec for build, signing, DMG and release tooling: that is process, kept in AGENTS.md.

## Decisions

- **Flat capability layout** (`specs/<capability>/spec.md`) over domain folders: 13 capabilities do not need nesting,
  and OpenSpec recommends following a flat layout until one is needed.
- **Split by user-facing feature, not by module.** Specs outlive file names; `annotation-editor` spans several files,
  while `after-capture` is one setting but a distinct promise. Alternative (one spec per folder) would tie specs to
  the code layout the proposal says specs must not describe.
- **Text recognition, Text Card and Capture Text are separate capabilities** even though they share Vision code:
  they promise different things and change independently.
- **Architecture map lives in this design.md**, archived with the change, rather than a new top-level doc: AGENTS.md
  already holds the file map, and a second copy would drift.
- **Project constraints go in `openspec/config.yaml` `context`**, pointing at AGENTS.md instead of copying it.

## Risks / Trade-offs

- [Specs drift from code as features change] → Every future behavior change goes through a change proposal with a
  delta spec; the config rules require a self-check task in each.
- [Some scenarios are only checked by hand (permissions, focus, multi-display)] → They stay in the spec; tasks list
  which ones the self-check covers.
- [README and specs both describe behavior] → README stays user-facing; specs are the contract. Update both when
  behavior changes.
