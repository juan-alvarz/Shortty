# app-presence Specification

## Purpose
Keeps Shortty out of the way as a menu bar app while still behaving like a normal Mac app whenever one of its windows is open.

## Requirements

### Requirement: Menu bar app
Shortty SHALL run with only a menu bar icon and no Dock icon while none of its titled windows is open. The menu SHALL list every capture action, Settings and the website.

#### Scenario: Launch
- **WHEN** Shortty launches
- **THEN** only its menu bar icon appears

### Requirement: Regular app while a window is open
While the editor or Settings is open and focused, Shortty SHALL appear in the Dock and ⌘Tab with its own menu bar, where ⌘, opens Settings.

#### Scenario: Editor opens
- **WHEN** the editor window becomes key
- **THEN** Shortty shows in the Dock and ⌘Tab

### Requirement: Back to the menu bar on close
Closing the last titled window SHALL hand focus back to the app the user was in and leave only the menu bar icon, with Shortty still running.

#### Scenario: Close the editor
- **WHEN** the user closes the last Shortty window
- **THEN** the previous app becomes active and Shortty leaves the Dock

### Requirement: Editor opens in front
The editor window SHALL open in front of the current app after a capture and receive keyboard focus, even though Shortty was in the background.

#### Scenario: Capture from another app
- **WHEN** the user captures with a shortcut while another app is in front
- **THEN** the editor appears in front and accepts keyboard shortcuts

#### Scenario: Editor left open while using another app
- **WHEN** the editor stays open, the user works in another app, then captures again
- **THEN** the editor takes keyboard focus and T selects the Text tool instead of typing into the other app

#### Scenario: Click back into the editor
- **WHEN** the editor stays open, the user works in another app, then clicks the editor
- **THEN** the editor takes keyboard focus and its shortcuts work

### Requirement: Open existing images
Shortty SHALL open PNG, JPEG, TIFF and HEIC files in the editor from Finder Open With or `open -a Shortty <file>`.

#### Scenario: Open With
- **WHEN** the user opens a PNG with Shortty from Finder
- **THEN** the editor shows that image

### Requirement: Area selector takes keys
The area selector SHALL receive Esc and Space even when the editor is open and another app is active.

#### Scenario: Esc with the editor open
- **WHEN** the editor is open, another app is active, and the user starts Capture Region and presses Esc
- **THEN** the selection is cancelled
