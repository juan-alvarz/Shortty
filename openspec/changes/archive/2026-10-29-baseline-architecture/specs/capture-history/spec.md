# Spec Delta

## Purpose

Keeps recent captures and their edits so the user can pick up where they left off, even after a relaunch.

## ADDED Requirements

### Requirement: Recent captures
The system SHALL keep the last 20 captures on disk, newest first, and SHALL drop the oldest beyond that.

#### Scenario: Twenty-first capture
- **WHEN** a 21st capture is taken
- **THEN** the oldest capture and its edits are removed

### Requirement: Edits are saved
Each capture's annotations, inserted pictures and crop SHALL be saved next to it shortly after every change and when another capture is opened. A capture with nothing drawn SHALL keep no edits file.

#### Scenario: Survive a relaunch
- **WHEN** the user draws on a capture, quits and runs Reopen Last Capture
- **THEN** the editor shows that capture with its annotations still editable

### Requirement: Reopen Last Capture
Reopen Last Capture SHALL open the newest capture with its edits.

#### Scenario: No captures
- **WHEN** the history is empty
- **THEN** Reopen Last Capture opens nothing

### Requirement: Recent captures strip
The editor SHALL show a slim bar along the bottom that opens into thumbnails of the history, drawn with their edits. A click SHALL open that capture; ⌘-click SHALL pick several; the picked ones (or one) SHALL be draggable into any app; delete SHALL remove one or all.

#### Scenario: Pick several and drag
- **WHEN** the user ⌘-clicks three thumbnails and drags one of them
- **THEN** all three captures are dragged together

#### Scenario: Delete a capture
- **WHEN** the user deletes a capture from the strip
- **THEN** its image, edits and preview are removed

### Requirement: Strip can be hidden
The history strip SHALL be shown by default and SHALL be hideable in Settings.

#### Scenario: Hidden
- **WHEN** the strip is turned off
- **THEN** the editor shows no history bar
