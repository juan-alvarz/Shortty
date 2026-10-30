# Spec Delta

## Purpose

Lets the user take a screenshot of an area, a window or a whole display from the menu bar or a shortcut, immediately or after a countdown.

## ADDED Requirements

### Requirement: Capture a region
The system SHALL let the user drag over an area of the screen and capture exactly that area.

#### Scenario: Drag an area
- **WHEN** the user starts Capture Region and drags over an area
- **THEN** the system captures that area and hands it to the after-capture flow

#### Scenario: Cancel the selection
- **WHEN** the user presses Esc while selecting
- **THEN** no capture is taken and nothing opens

#### Scenario: Switch to window picking
- **WHEN** the user presses Space while selecting an area
- **THEN** the selector switches to clicking a window, which captures that window

### Requirement: Selector works over other apps
The area selector SHALL appear above every app and show its crosshair even while another app is frontmost.

#### Scenario: Another app in front
- **WHEN** a capture starts while another app is active
- **THEN** the selector overlay shows the crosshair without bringing Shortty forward

### Requirement: Repeat the last region
The system SHALL capture the same area as the last region capture without selecting, and SHALL remember that area across relaunches.

#### Scenario: Repeat after relaunch
- **WHEN** the user runs Repeat Last Region after relaunching Shortty
- **THEN** the area from the last region capture before the relaunch is captured

#### Scenario: Nothing to repeat yet
- **WHEN** the user runs Repeat Last Region before any region was picked
- **THEN** the area selector appears, as for Capture Region

### Requirement: Capture a window
The system SHALL capture a clicked window, and SHALL capture the frontmost app's front window instantly for Capture Active Window, both without the window shadow.

#### Scenario: Click a window
- **WHEN** the user starts Capture Window and clicks a window
- **THEN** that window is captured without its shadow

#### Scenario: Active window
- **WHEN** the user runs Capture Active Window
- **THEN** the front window of the app in use is captured with no selection step

### Requirement: Capture a screen
The system SHALL capture the whole display under the pointer.

#### Scenario: Multiple displays
- **WHEN** the user runs Capture Screen with the pointer on the second display
- **THEN** the second display is captured

### Requirement: Lazy shots
Lazy Region SHALL let the user pick the area first and capture it after the configured delay; Lazy Screen SHALL capture the display under the pointer after the delay. While counting down, the remaining seconds SHALL show next to the menu bar icon and the menu SHALL offer Cancel Lazy Shot.

#### Scenario: Countdown then capture
- **WHEN** the user picks an area with Lazy Region and the delay is 3 seconds
- **THEN** the area stays outlined, the menu bar shows 3, 2, 1, and then exactly that area is captured

#### Scenario: Cancel a countdown
- **WHEN** the user chooses Cancel Lazy Shot during the countdown
- **THEN** no capture is taken

### Requirement: Capture sound
The system SHALL play the capture sound when a screenshot is taken, unless the user turned it off in Settings.

#### Scenario: Sound off
- **WHEN** Play sound when capturing is off and the user captures
- **THEN** no sound plays

### Requirement: Screen Recording permission
Captures SHALL rely on the macOS Screen Recording permission and SHALL keep working across updates of a correctly installed app without asking again.

#### Scenario: First capture
- **WHEN** the user captures for the first time
- **THEN** macOS asks for Screen Recording permission for Shortty
