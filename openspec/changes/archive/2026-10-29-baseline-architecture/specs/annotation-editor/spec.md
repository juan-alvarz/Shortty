# Spec Delta

## Purpose

Lets the user mark up a capture with shapes, text and effects that stay editable until export.

## ADDED Requirements

### Requirement: One editor window
Every capture SHALL open in the same editor window, starting clean with no annotations from the previous capture.

#### Scenario: Second capture
- **WHEN** a capture arrives while the editor shows another one
- **THEN** the window is reused and shows only the new capture

### Requirement: Drawing tools
The editor SHALL offer Select, Pencil, Arrow, Text, Rectangle, Ellipse, Numbered steps, Magnifier, Blur, Spotlight, Recognize Text, Text Card, Crop and Ruler, each with a single-letter key (V P A T R O N M B S X K C U).

#### Scenario: Tool key
- **WHEN** the user presses A with nothing being typed
- **THEN** the Arrow tool is selected

#### Scenario: Keys shown on demand
- **WHEN** the user holds ⌘ alone
- **THEN** each tool button shows its key until ⌘ is released

### Requirement: Annotations stay editable
Every annotation SHALL stay selectable after it is drawn so the user can move, resize, recolor, restyle, duplicate, reorder or delete it.

#### Scenario: Recolor later
- **WHEN** the user selects an existing rectangle and picks another color
- **THEN** only that rectangle changes color

#### Scenario: Area selection
- **WHEN** the user drags over empty space with Select
- **THEN** the annotations inside are selected together, except inserted pictures

### Requirement: Shape modifiers
Shift SHALL constrain drawing: Pencil draws a straight line (Shift+Control snaps to 45°), Arrow snaps to 45°, Rectangle and Ellipse draw a square or circle, corner resize keeps proportions.

#### Scenario: Square
- **WHEN** the user draws a rectangle holding Shift
- **THEN** it is a square

### Requirement: Arrows
Arrows SHALL come in four styles and SHALL bend when the middle handle is dragged.

#### Scenario: Bend an arrow
- **WHEN** the user drags an arrow's middle handle sideways
- **THEN** the arrow curves through that point and its ends stay put

### Requirement: Text annotations
Text SHALL be a callout (bubble with a pointer), a label (filled box) or plain letters, typed in place. A drag with the Text tool SHALL aim the pointer from where the text goes to its target. Text left empty SHALL disappear and leave no undo step.

#### Scenario: Aimed callout
- **WHEN** the user drags with the Text tool and types two lines
- **THEN** the callout's pointer stays on the target as lines are added

#### Scenario: Shortcuts while typing
- **WHEN** the user types V into a text box
- **THEN** the letter is typed and the tool does not change

### Requirement: Numbered steps
Clicking with Numbered steps SHALL add badges numbered 1, 2, 3…, each pointing from its corner and aimable by dragging its tip. Deleting a step SHALL renumber the rest.

#### Scenario: Renumber
- **WHEN** the user deletes step 2 of 3
- **THEN** the remaining steps read 1 and 2

### Requirement: Magnifier, blur and spotlight
The Magnifier SHALL show a 2× copy of an area beside it, joined by a line. Blur SHALL pixelate an area; Erase SHALL fill it with one surrounding color. Spotlight SHALL dim everything outside its areas with one shared dim and outline each area; annotations drawn on top stay bright.

#### Scenario: Overlapping spotlights
- **WHEN** two spotlights overlap
- **THEN** the outside is dimmed once, not twice

### Requirement: Crop without loss
Crop SHALL show only the chosen box after it is applied, and Reset or undo SHALL bring back the whole picture.

#### Scenario: Undo a crop
- **WHEN** the user applies a crop and presses ⌘Z
- **THEN** the whole picture is shown again

### Requirement: Ruler
The Ruler SHALL measure from the pointer to the nearest edges sideways and up and down, in pixels. Holding 1 SHALL measure sideways only; holding 2 up and down only.

#### Scenario: Sideways only
- **WHEN** the user holds 1 with the Ruler
- **THEN** only the horizontal measurement shows

### Requirement: Insert pictures
The user SHALL be able to add pictures by pasting, picking files, capturing a new area or dropping image files on the canvas. Inserted pictures SHALL keep their proportions and be scaled down to fit when larger than the canvas.

#### Scenario: Paste text
- **WHEN** the clipboard holds only text and the user presses ⌘V
- **THEN** nothing is inserted

### Requirement: Undo and redo
Every edit SHALL be undoable with ⌘Z and redoable with ⌘⇧Z. A continuous drag (mouse or slider) SHALL be one undo step.

#### Scenario: Slider drag
- **WHEN** the user drags the thickness slider through several values
- **THEN** one ⌘Z restores the thickness from before the drag

### Requirement: Colors and thickness
The editor SHALL offer 10 preset colors, R/G/B sliders, a hex field and a screen eyedropper. Each tool SHALL remember its own thickness.

#### Scenario: Per-tool thickness
- **WHEN** the user sets the Pencil to 10 and switches to Rectangle and back
- **THEN** the Pencil is still 10

### Requirement: Growing canvas
Drawing or typing past the capture's edges SHALL grow the canvas and the export to fit; the added area SHALL be filled with the image's edge color. Removing those annotations SHALL shrink it back.

#### Scenario: Draw past the edge
- **WHEN** the user draws a rectangle that extends past the right edge
- **THEN** the canvas and the export include the whole rectangle

### Requirement: Zoom
⌘+scroll, pinch and ⌘+ / ⌘- SHALL zoom around the pointer, ⌘0 SHALL fit the picture, and plain scrolling SHALL scroll without zooming.

#### Scenario: Fit
- **WHEN** the user presses ⌘0
- **THEN** the whole canvas fits the window

### Requirement: Selection bar and keys
A selected annotation SHALL get a small bar with its color, Duplicate, Bring to front, Send to back and Delete. Arrow keys SHALL nudge it 1 px (Shift: 10 px), ⌫ deletes, ⌘D duplicates, ⌘] and ⌘[ reorder.

#### Scenario: Reorder is undoable
- **WHEN** the user brings a shape to the front and presses ⌘Z
- **THEN** the previous order returns

### Requirement: Closing the editor
Esc SHALL return to Select, and on Select clear the selection. A quick second Esc or ⌘W SHALL close the editor; a single Esc SHALL never close it.

#### Scenario: Single Esc
- **WHEN** the user presses Esc once on Select with nothing selected
- **THEN** the window stays open
