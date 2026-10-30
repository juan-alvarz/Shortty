# image-export Specification

## Purpose
Gets the finished picture out of the editor: to the clipboard, a file, another app or a floating pin.

## Requirements

### Requirement: Copy and Save
Copy (⌘C) SHALL put the rendered picture on the clipboard and Save (⌘S) SHALL write it as `shortty-<timestamp>-image.png` in the save folder. Both SHALL close the editor and show a notice saying where the picture went.

#### Scenario: Save
- **WHEN** the user presses ⌘S with Downloads as the save folder
- **THEN** a PNG appears in Downloads and a notice says "Saved to ~/Downloads/…"

### Requirement: What is exported
The export SHALL contain the capture (or the crop) with every annotation flattened, the grown canvas area, and the backdrop if one is chosen, in fixed sRGB colors.

#### Scenario: Annotation colors
- **WHEN** a red arrow is exported
- **THEN** its pixels in the PNG are the same red as the color picked

### Requirement: Drag and drop
The drag handle next to Save SHALL drag the rendered picture into any app or upload box without leaving files in Downloads; older drag files SHALL be cleaned up.

#### Scenario: Drag into a browser
- **WHEN** the user drags the handle into a website's upload box
- **THEN** the site receives the picture as a PNG and nothing is added to Downloads

### Requirement: Pin to screen
Pin SHALL float the picture above every window; scrolling or pinching SHALL resize it with the same proportions and Esc SHALL close it.

#### Scenario: Resize a pin
- **WHEN** the user scrolls over a pin
- **THEN** it grows or shrinks and keeps its proportions

### Requirement: Gradient backdrop
The user SHALL be able to place the result on a gradient card with padding, rounded corners and a soft shadow, or choose None.

#### Scenario: None
- **WHEN** the user picks None for the backdrop
- **THEN** the export is the picture alone
