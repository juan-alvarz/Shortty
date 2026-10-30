# Spec Delta

## MODIFIED Requirements

### Requirement: Editor opens in front
The editor window SHALL open in front of the current app after a capture and receive keyboard focus, even though Shortty was in the background.

#### Scenario: Capture from another app
- **WHEN** the user captures with a shortcut while another app is in front
- **THEN** the editor appears in front and accepts keyboard shortcuts

#### Scenario: Editor left open while using another app
- **WHEN** the editor stays open, the user works in another app, then captures again
- **THEN** the editor takes keyboard focus and T selects the Text tool instead of typing into the other app

#### Scenario: Click back into the editor
- **WHEN** the editor stays open, the user works in another app, then clicks the editor
- **THEN** the editor takes keyboard focus and its shortcuts work

## ADDED Requirements

### Requirement: Area selector takes keys
The area selector SHALL receive Esc and Space even when the editor is open and another app is active.

#### Scenario: Esc with the editor open
- **WHEN** the editor is open, another app is active, and the user starts Capture Region and presses Esc
- **THEN** the selection is cancelled
