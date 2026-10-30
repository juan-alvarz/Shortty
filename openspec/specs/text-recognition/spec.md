# text-recognition Specification

## Purpose
Finds text in a capture on the Mac so the user can hide it or copy exactly the words they want.

## Requirements

### Requirement: Blur Text and Erase Text
Blur Text and Erase Text SHALL find the text lines inside the chosen area and blur or erase only those lines, refreshing them whenever the area changes.

#### Scenario: Blur only the words
- **WHEN** the user drags Blur Text over a paragraph on a plain background
- **THEN** only the text lines are blurred and the background around them is unchanged

### Requirement: Recognize Text
Recognize Text SHALL overlay macOS Live Text on the capture so the user can select and copy words, and SHALL offer Copy All. It SHALL add nothing to the picture, and leaving the tool SHALL hide the overlay.

#### Scenario: Copy All
- **WHEN** the user clicks Copy All on a capture reading "Hello Shortty 42"
- **THEN** the clipboard holds "Hello Shortty 42" and the picture is unchanged

### Requirement: On-device recognition
All text recognition SHALL run on the Mac with no network access.

#### Scenario: Offline
- **WHEN** the Mac is offline
- **THEN** Blur Text and Recognize Text still work
