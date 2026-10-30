# Spec Delta

## Purpose

Captures content taller than the screen by recording a fixed area while the user scrolls and stitching the frames into one image.

## ADDED Requirements

### Requirement: Scrolling session
Scrolling Capture SHALL let the user drag over an area, then record that area while they scroll, with a small panel offering Done (Return) and Cancel (Esc).

#### Scenario: Finish a scrolling capture
- **WHEN** the user drags an area, scrolls down the page and presses Return
- **THEN** the stitched image is stored in the capture history and handed to the after-capture flow

#### Scenario: Cancel a scrolling capture
- **WHEN** the user presses Esc in the scrolling panel
- **THEN** the session ends and no capture is kept

### Requirement: Frame stitching
Each new frame SHALL add only the rows newly revealed by scrolling. Frames with no movement SHALL add nothing.

#### Scenario: Page matches the original
- **WHEN** a page is scrolled in steps that overlap the previous frame
- **THEN** the stitched result matches the original page row for row

#### Scenario: Pause while scrolling
- **WHEN** a frame is identical to the previous one
- **THEN** it is ignored

### Requirement: Sticky header and footer
Rows that stay still at the top and bottom of every frame SHALL appear once in the result: the header at the top and the footer at the bottom.

#### Scenario: Page with sticky bars
- **WHEN** a page with a fixed header and footer is scrolled to the end
- **THEN** the result height is the header plus the whole scrolled content plus the footer

### Requirement: Lost overlap
A frame with no overlap with the previous one SHALL be skipped, and stitching SHALL continue from the next frame that overlaps.

#### Scenario: Scrolled too far at once
- **WHEN** the user scrolls more than a frame's height between two captures
- **THEN** that frame is skipped and the next overlapping frame continues the image
