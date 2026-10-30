# Spec Delta

## Purpose

Lets the user choose how the editor arranges its tools and options around the picture.

## ADDED Requirements

### Requirement: Four layouts
The editor SHALL offer Classic (one toolbar, options float over the picture's top right), Two rows (toolbar plus an options strip), Sidebars (tools left, options right, output actions on top) and Canvas first (floating tool dock at the bottom). Classic SHALL be the default.

#### Scenario: Every layout works
- **WHEN** any layout is chosen
- **THEN** the canvas, every tool, the tool options, colors and the selection bar are reachable

### Requirement: Live switching
Changing the layout in Settings SHALL rearrange the open editor immediately.

#### Scenario: Switch while editing
- **WHEN** the user changes the layout with the editor open
- **THEN** the editor rearranges without losing the capture or its edits

### Requirement: Visual language
The editor chrome SHALL be dark with custom line icons, and tooltips SHALL appear where they do not cover the chrome: below in bars, beside the rail, above the dock.

#### Scenario: Dock tooltip
- **WHEN** the user hovers a tool in the Canvas first dock
- **THEN** its tooltip appears above the dock
