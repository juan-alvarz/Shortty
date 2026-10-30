# app-settings Specification

## Purpose
Stores the user's preferences and offers them in a Settings window with General, Shortcuts and About tabs.

## Requirements

### Requirement: Persisted preferences
Every preference SHALL be saved as soon as it changes and SHALL be restored on the next launch. Out-of-range stored values SHALL be clamped to their allowed range.

#### Scenario: Relaunch keeps a choice
- **WHEN** the user picks a save folder and relaunches Shortty
- **THEN** Save still writes to that folder

### Requirement: General preferences
Settings SHALL offer: start at login, capture sound (default on), selection color (default: the Mac's accent color), save folder (default Downloads), editor layout (default Classic) and after-capture behavior.

#### Scenario: Selection color follows the accent
- **WHEN** the user has not picked a selection color
- **THEN** the selection outline uses the Mac's accent color

#### Scenario: Picked selection color
- **WHEN** the user picks #22CC88 as the selection color
- **THEN** area selection and countdown outlines use #22CC88

### Requirement: Lazy delay
The lazy shot delay SHALL be adjustable from 1 to 30 seconds, default 3, in Settings → Shortcuts.

#### Scenario: Default delay
- **WHEN** the user has never changed the delay
- **THEN** lazy shots wait 3 seconds

### Requirement: App identity in General
Settings → General SHALL start with the app icon, name and installed version. The version SHALL be a link that opens the GitHub release notes for exactly that version.

#### Scenario: Open the release notes
- **WHEN** the user clicks "Version 1.3.5" in Settings → General
- **THEN** the browser opens https://github.com/juan-alvarz/Shortty/releases/tag/v1.3.5

#### Scenario: No About tab
- **WHEN** the user opens Settings
- **THEN** it has the General and Shortcuts tabs only
