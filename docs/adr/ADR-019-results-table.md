# ADR-019: Results table view

Status: accepted (v0.60.0 to v0.63.2)

## Context
People wanted to read a list response the way a database client shows a query result: rows and columns they can sort, filter, select and copy.

## Decisions
- **A custom grid, not a package.** `ResultTableView` is built from a pinned header and a lazy `ListView.builder` of fixed-height rows inside one horizontal scroller, in the style of the code view. No new dependency; one scrolling model the app already tests; hover, selection and large-text rules stay under our control.
- **The model is in `verbnest_core`** (`ResultTable`, `tableFromJson/Xml/Csv`, `readTable`, writers), pure Dart and tested on fixtures, so the CLI can use it later.
- **Read-only and opt-in.** Pretty stays the first view; the Table view is offered only for bodies that parse as a table. Cells are not editable.
- **Nested values** show as a one-line JSON preview with an optional "Flatten nested keys" (three levels).
- **Limits are display limits.** 10,000 rows, 200 columns and 4,000 characters per cell are what the grid draws; the table keeps every row and column, and search, copy and export use all of it (0.63.5 closed a gap where columns past 200 were cut from the data). The whole body is always a source, so fields beside the rows are reachable. Bodies over 5 MB are not offered a table.
- **Large bodies are read in an isolate** (above 256 KB) and only when the table is chosen. Sorting and searching are made cheap in the core (precomputed keys, a per-row search index) instead of moving them to an isolate, which would copy the whole table.
- **Selection is ours.** Text selection across a virtualised grid is not the platform's, so cell selection, keyboard movement and copy are implemented in the widget. A double click is detected by hand because a double-tap recogniser delays every click and leaves a timer running.
- **A phone's mode switch keeps three segments**; Table lives in the body menu there (a fourth segment squeezed the labels onto two lines).

## Consequences
The grid is a screen-reader table in effect (labels, selected state, activation), covered by the accessibility guidelines and the device matrix. A later feature (editing, charts) would need a different widget or a deeper rework. Found on the way: the code view's syntax colouring was quadratic on huge single lines; fixed in 0.63.2.
