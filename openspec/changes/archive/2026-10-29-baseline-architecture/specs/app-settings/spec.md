# Spec Delta

## Purpose

Stores the user's preferences and offers them in a Settings window with General, Shortcuts and About tabs.

## ADDED Requirements

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

### Requirement: About tab
Settings SHALL include an About tab with the app's name and version.

#### Scenario: Version shown
- **WHEN** the user opens the About tab
- **THEN** it shows the installed version
