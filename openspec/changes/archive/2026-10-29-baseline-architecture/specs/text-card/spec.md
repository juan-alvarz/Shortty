# Spec Delta

## Purpose

Turns text in a capture (code, a terminal, a chat) into a clean window-like card that keeps each word's original color.

## ADDED Requirements

### Requirement: Make a card from an area
Dragging with Text Card over text SHALL redraw it as a card whose background comes from the screenshot and whose words keep the colors they had. A click without a drag SHALL do nothing.

#### Scenario: Syntax highlighting survives
- **WHEN** the user drags Text Card over highlighted code
- **THEN** the card shows the same lines with each word in its original color on the screenshot's background

### Requirement: Tune before opening
Before the card opens, a sheet SHALL let the user change the background, text color, font size and title bar, edit the text, and recolor selected text. Confirming SHALL open the card as a new capture.

#### Scenario: Recolor a selection
- **WHEN** the user selects a word in the sheet and picks a color
- **THEN** only that word changes color in the card

### Requirement: Card rendering
The card SHALL render at 2× scale with transparent rounded corners, and with the title bar on it SHALL show window buttons. The font size and title bar choice SHALL be remembered.

#### Scenario: Title bar
- **WHEN** the title bar option is on
- **THEN** the card has a title bar with the three window buttons
