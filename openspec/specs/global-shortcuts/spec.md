# global-shortcuts Specification

## Purpose
Lets the user trigger every capture action from anywhere with a shortcut they record themselves.

## Requirements

### Requirement: No default shortcuts
The system SHALL ship with no capture shortcuts set; the user records each one in Settings → Shortcuts, which lists every capture action with a one-line summary.

#### Scenario: Fresh install
- **WHEN** Shortty runs for the first time
- **THEN** no capture action has a shortcut and pressing any key combination triggers nothing

### Requirement: System-wide shortcuts
A recorded shortcut SHALL trigger its capture action while any app is frontmost, without the Accessibility permission.

#### Scenario: Shortcut in another app
- **WHEN** the user presses the shortcut recorded for Capture Region while another app is in front
- **THEN** the region selector appears

### Requirement: Shortcuts persist
Recorded shortcuts SHALL apply immediately and SHALL survive relaunches. Each action's shortcut SHALL stay bound to that action when new actions are added in later versions.

#### Scenario: Relaunch
- **WHEN** the user records a shortcut and relaunches Shortty
- **THEN** the shortcut still triggers the same action
