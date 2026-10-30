# Proposal

## Why

Editor shortcuts (T, A, …) stop working after the user visits another app while the editor stays open: the keys go to
that other app. While a window is open Shortty is a regular app; once it is inactive, macOS refuses its non-activating
editor panel keyboard focus ("a foreground app can't steal keyboard focus"), both after the next capture and when the
user clicks back into the editor. The area selector's Esc and Space hit the same refusal.

## What Changes

- Before a Shortty panel asks for keyboard focus while Shortty is a regular but inactive app, Shortty steps back to
  menu-bar-only, the state in which the panel can take focus; it becomes a regular app again once the panel is key.
- Applies to the editor shown after a capture or reopen, a click on the editor, and the area selector.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `app-presence`: the editor takes keyboard focus after a capture and on a click, also when another app was active
  while the editor stayed open.

## Impact

- `Shortty/App/AppDelegate.swift` (`AppPresence`), `Shortty/Editor/EditorWindowController.swift` (`EditorPanel`,
  `present`), `Shortty/Capture/RegionSelector.swift`.
- `Scripts/SelfCheck/main.swift`, AGENTS.md editor window rule.
