# Spec Delta

## Purpose

Decides what the user sees right after a capture and whether the capture is copied or saved automatically.

## ADDED Requirements

### Requirement: After-capture choice
After a capture the system SHALL show the editor, a quick card or only a notice, per Settings → After a capture. The default SHALL be the editor.

#### Scenario: Default
- **WHEN** a capture is taken with default settings
- **THEN** the editor opens with the capture

### Requirement: Automatic copy and save
When Copy is on, every capture SHALL go to the clipboard right away; when Save is on, it SHALL be written to the save folder right away. Copy SHALL be on and Save off by default.

#### Scenario: Save on
- **WHEN** Save is on and the user captures
- **THEN** a PNG named `shortty-<timestamp>-image.png` appears in the save folder

### Requirement: Quick card
The quick card SHALL appear in a screen corner without taking keyboard focus, SHALL offer Copy, Save, Pin and Edit, SHALL let the user drag its picture into any app or click it to edit, and SHALL go away on its own.

#### Scenario: Card does not steal focus
- **WHEN** the quick card appears while the user types in another app
- **THEN** the typing stays in that app

#### Scenario: Edit from the card
- **WHEN** the user clicks the card's picture
- **THEN** the card closes and the editor opens with the capture

### Requirement: Notice only
With Nothing chosen, the system SHALL show only a short notice saying the capture was taken, even when neither Copy nor Save is on.

#### Scenario: Nothing without Copy or Save
- **WHEN** After a capture is Nothing and Copy and Save are off
- **THEN** a notice still says the capture was taken
