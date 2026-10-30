# Spec Delta

## MODIFIED Requirements

### Requirement: Recent captures strip
The editor SHALL show a slim bar along the bottom that opens into thumbnails of the history, drawn with their edits. A click SHALL open that capture; ⌘-click SHALL pick several; the picked ones (or one) SHALL be draggable into any app; delete SHALL remove one or all.

#### Scenario: Pick several and drag
- **WHEN** the user ⌘-clicks three thumbnails and drags one of them
- **THEN** all three captures are dragged together

#### Scenario: Delete a capture
- **WHEN** the user deletes a capture from the strip
- **THEN** its image, edits and preview are removed

#### Scenario: Click the open capture
- **WHEN** the user clicks the thumbnail of the capture already open in the editor
- **THEN** nothing reloads and its undo history is kept

## ADDED Requirements

### Requirement: Dragged captures keep their edits
A capture dragged out of the strip SHALL arrive as its thumbnail shows it: its saved annotations and crop drawn in, without the backdrop. The open capture's newest edits SHALL be included. A capture with no edits SHALL arrive as the original file.

#### Scenario: Drag an edited capture into another app
- **WHEN** the user drags a thumbnail of a capture with an arrow drawn on it into Finder
- **THEN** the dropped PNG shows the arrow

#### Scenario: Edits made a moment ago
- **WHEN** the user draws on the open capture and drags its thumbnail right away
- **THEN** the dropped PNG includes the new drawing

#### Scenario: Drop on the canvas
- **WHEN** the user drags an edited thumbnail onto the editor's canvas
- **THEN** it is inserted as a picture with its edits

### Requirement: Thumbnail hover follows the pointer
A thumbnail SHALL show its hover highlight and delete button only while the pointer is over it, including after a drag ends elsewhere, after the strip scrolls and after thumbnails shift.

#### Scenario: After dragging out
- **WHEN** the user drags a thumbnail into another app and releases there
- **THEN** that thumbnail no longer shows the hover highlight or delete button
