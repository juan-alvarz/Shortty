# Shortty

A free, minimal screenshot tool for macOS in the spirit of [Shottr](https://shottr.cc). Every feature is free, no ads.
Native Swift (SwiftUI + AppKit), lives in the menu bar, no third-party dependencies.

## Capture

| Action | Default shortcut | What it does |
|---|---|---|
| Capture Region | `⌘⇧9` | System crosshair. Space switches to window capture, Esc cancels. |
| Capture Screen | none | The display under the pointer. |
| Lazy Region | `⌘⇧8` | Drag the area first, then a countdown runs and that exact area is captured. |
| Lazy Screen | none | Countdown, then the display under the pointer. |
| Reopen Last Capture | none | Brings back the editor with the latest capture and its edits, even after a relaunch. |

All four are in the menu bar too. During a countdown the seconds show next to the menu bar icon, and the menu has
"Cancel Lazy Shot". Shortcuts and the lazy delay (1–30 s, default 3) are in Settings → Shortcuts. The capture sound
can be turned off in Settings → General. The latest capture is kept at
`~/Library/Caches/com.socialgoodsoftware.Shortty/last-capture.png` so it can be reopened; each new capture replaces it.

## Edit

Every capture opens in one reused editor window.

| Key | Tool / action |
|---|---|
| `V` `P` `A` `T` `R` `O` | Select, Pencil, Arrow, Text, Rectangle, Ellipse |
| `M` `B` `S` `X` | Magnifier, Blur, Spotlight, Recognize Text |
| Shift while drawing | Pencil: straight line · Arrow: snaps to 45° · Rectangle/Ellipse: square/circle |
| Shift while editing | Corner resize keeps proportions · Move locks to one axis · Arrow middle handle straightens |
| Arrows / Shift+Arrows | Nudge the selection 1 px / 10 px |
| `⌫` | Delete the selection |
| `⌘Z` / `⌘⇧Z` | Undo / redo |
| `⌘C` / `⌘S` | Copy / save to `~/Downloads/shortty-<timestamp>-image.png` |
| `⌘V` | Paste a picture from the clipboard into the canvas |
| `⌘` + scroll, pinch, `⌘+` `⌘-` | Zoom around the pointer · `⌘0` fits |
| Esc | Back to the Select tool (finishing any typing); on Select, deselect. Never closes the window |

Everything you draw stays editable. Select it to move it, resize it from its handles, recolor it, or change its
thickness. Arrows have start, end and middle handles; drag the middle one to curve the arrow. With a drawing tool
active or something selected, a floating panel sets the thickness (text size for text), which each tool remembers
on its own. For arrows and text, the panel also sets the style. The color square opens 10 presets, R/G/B
sliders, a hex field and a screen eyedropper.

The Text tool has three variants: a callout (filled bubble with a pointer you drag onto what it points at), a label
(filled box) and plain letters. Click to type in place; Return adds a line; Esc or a click outside finishes. Click
existing text with the Text tool (or double-click it with Select) to edit it, drag it to move it. On a filled box the
letters turn black or white, whichever reads better on that color.

**Magnifier**: drag over a small area and a 2× copy appears beside it, joined by a line. Drag either one to move it;
drag the copy's corners to zoom. Circle or rounded rectangle.

**Blur**: Blur pixelates the area (strength slider), Blur Text pixelates only the text found in it, Erase paints the
area with the color around it, Erase Text erases only the text. Text is found on-device with Apple's Vision.

**Spotlight**: dims everything except the area (rectangle or ellipse, dim slider) and outlines it in the current color. Several spotlights share one dim
layer, and arrows or text drawn on top stay bright.

**Recognize Text**: drag over any area and its text is copied to the clipboard (on-device, nothing is uploaded).

**Drag and drop**: drag the handle next to Save into any app or a website's upload box. It hands over a temporary
PNG, so nothing piles up in Downloads.

**Insert pictures**: the picture button pastes from the clipboard, picks files in Finder, or captures a new area
(the editor steps aside while you select). You can also drop image files from Finder onto the canvas. Inserted
pictures move and resize like anything else, keeping their proportions (Shift frees them).

**Gradient Backdrop**: the backdrop button puts the whole result on a gradient card, with padding, rounded corners
and a soft shadow (8 gradients; sliders for each). It shows live in the editor and is part of every export.

**Room to work**: you can draw, type or drag things past the screenshot's edges. When the drag or typing ends, the
canvas grows to fit them, the new area takes the screenshot's edge color, and copy/save/drag export the whole canvas.

Shortty also opens existing images: Finder "Open With", or `open -a Shortty image.png`.

## Install

```bash
Scripts/install.sh
```

This builds Release, installs to `/Applications/Shortty.app` and launches it. The first run creates a local
code-signing certificate ("Shortty Dev"), and macOS asks for your login password once to trust it. A fixed
certificate is what makes macOS remember the Screen Recording permission across rebuilds. The first capture asks
for that permission.

Requirements: macOS 14+, Xcode, and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## App icon

The source is `Design/AppIcon.svg` (a kitty in a viewfinder). After editing it, or replacing it with your own
1024×1024 SVG:

```bash
swift Scripts/make-icon.swift && Scripts/install.sh
```

## Contributing

See [AGENTS.md](AGENTS.md) for how the code is organized, how to add features, and how to verify changes.
