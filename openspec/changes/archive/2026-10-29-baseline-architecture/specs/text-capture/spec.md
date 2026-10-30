# Spec Delta

## Purpose

Copies the text or QR code contents of a dragged screen area to the clipboard without opening the editor.

## ADDED Requirements

### Requirement: Read an area to the clipboard
Capture Text SHALL let the user drag over an area and SHALL put a QR code's contents on the clipboard if one is found, else the recognized text, one line per text line.

#### Scenario: Area with text
- **WHEN** the user drags over two lines reading "one" and "two"
- **THEN** the clipboard holds "one\ntwo"

#### Scenario: Area with a QR code
- **WHEN** the area holds a QR code for a URL
- **THEN** the clipboard holds that URL

### Requirement: Notice of the result
After Capture Text, a floating notice SHALL say what was copied, or "No text found", SHALL let clicks pass through, and SHALL go away by itself.

#### Scenario: Nothing found
- **WHEN** the area has no text and no QR code
- **THEN** the notice says "No text found" and the clipboard is unchanged

### Requirement: On-device only
Text and QR recognition SHALL run on the Mac with no network access.

#### Scenario: Offline
- **WHEN** the Mac has no network connection
- **THEN** Capture Text still works
