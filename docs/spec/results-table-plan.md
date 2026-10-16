# Plan: view results as a table (like pgAdmin's results grid)

Status: T0 and T1 done (0.60.0), T2 done (0.61.0), T3 done (0.62.0): Table segment on tablet/desktop, a body menu on phones (Table, Wrap, Copy), search box as row filter, JSONPath filter feeds the table, Rows from / Flatten / First row header options. Decisions taken as recommended: custom grid, nested as JSON preview with a flatten option, read-only, 10,000-row cap, opt-in Table segment.

Goal: any response that is a list of records (most JSON APIs, some XML, CSV)
can be read as a grid of rows and columns, the way pgAdmin shows a query
result: fixed header, row numbers, resizable columns, sort by clicking a
header, select cells and copy them, null shown distinctly, long values cut with
a way to see them in full, and a count of rows at the bottom.

## What pgAdmin's grid does (the reference)

- A header row with column names (and the data type); a row-number column on the
  left; both stay in view while scrolling.
- Columns can be resized by dragging the header edge; double-click fits the
  content. Cells are cut to one line.
- Click a header to sort (ascending, descending, off). Click a cell, row number
  or header to select a cell, a row or a column; Shift-click extends; Cmd/Ctrl+C
  copies the selection (tab-separated, with or without the header).
- `[null]` is shown in a muted style, numbers right-aligned, text left-aligned.
- Double-click a cell (or press Enter) to see a long or JSON value in full.
- Footer: rows returned and time taken.
- Handles large results by showing rows lazily.

## What we have to build on

- `ResponseView` already has a Pretty / Raw / Hex / Preview switch, a JSONPath or
  XPath filter that returns the matches, search, copy and save.
- `verbnest_core` has `jsonPath`, `filterBody` (JSON and XML) and a CSV/JSON
  data-file reader (`data_file.dart`); no grid widget or table package exists.
- `CodeView` shows the pattern for a virtualised, horizontally scrolling view
  with a pinned gutter, hover handling and a scrollbar.
- The device matrix, goldens and large-text tests, which a new view must join.

## Design

### Where it appears
A new **Table** segment in the response body switch (Pretty, Raw, Hex,
Preview, Table), shown only when the body can be read as a table. It works on
what the filter returns, so `$.items[*]` in the filter box feeds the grid: the
filter is the "query", the table is the "result". Under 360 dp wide the segment
is an icon.

### Which bodies become a table
- **JSON, array of objects** (`[{"id":1,...},...]`): a row per object, a column
  per key (union of keys in order of first appearance; a missing key is empty).
- **JSON, object holding one array of objects** (`{"items":[...]}`, the usual
  API shape): that array is used, and a small "Rows from" selector names it
  (`$.items`); other arrays in the body are listed in the selector.
- **JSON, array of arrays**: columns are 1, 2, 3, with an option to use the
  first row as the header.
- **JSON, a single object**: two columns, Key and Value.
- **JSON, array of primitives**: one column, Value.
- **XML**: repeated sibling elements are rows; child elements and attributes
  are columns.
- **CSV / TSV** (`text/csv`, `text/tab-separated-values`): parsed with the
  existing CSV reader; first row is the header (toggle).
- Anything else, or a body that does not parse: no Table segment.

### Cell values
- null, true/false, numbers and strings show as such; `null` is muted; numbers
  are right-aligned and sorted as numbers; ISO dates are sorted as dates.
- Nested objects and arrays show as a one-line JSON preview (`{3 keys}`,
  `[5 items]`, then the start of the JSON), with a "Flatten nested keys" option
  that turns `address.city` into its own column (depth limit 3).
- Long text is cut at the column width with an ellipsis; the full value is one
  tap, Enter or double-click away.

### Widget (`ResultTable`)
Custom, in the style of `CodeView`, rather than a package: a pinned header and
row-number column, a virtualised `ListView.builder` of fixed-height rows inside
a horizontal scroller with a visible scrollbar. Reasons: no new dependency to
track, one scrolling model the app already tests, and it has to fit the
existing hover, selection and large-text rules. (Alternative:
`two_dimensional_scrollables`' `TableView`, which would give 2-D virtualisation
and pinned rows or columns for free but adds a dependency and its own
scrolling rules; decide at T0.)

- Column widths from a sample of the first 200 rows (measured text, clamped
  between 80 and 360 dp), resizable by dragging, double-click to fit.
- Sort by header click (ascending, descending, off), stable and type-aware.
- Selection: cell, row (row number), column (header), range with Shift or drag;
  arrow keys move, Cmd/Ctrl+C copies, Cmd/Ctrl+A selects all.
- A text filter box above the grid filters rows (case-insensitive, any column);
  matches are highlighted like the code view's search.
- Footer: "250 rows, 8 columns", plus the selection ("3 cells selected") and a
  "Showing the first 10,000 rows" note when capped.

### Copy and export
Copy cell / row / column / selection as TSV; "Copy with headers"; **Copy as**
CSV, JSON (the selected rows as objects) and Markdown; **Save as CSV** through
the existing file port (share sheet on phones).

### Phones
Same grid, horizontally scrollable with the row-number column pinned; tap a
cell for the detail sheet (the existing `showDetail`, a bottom sheet), long
press for a cell menu (copy cell, copy row). Header tap sorts. Touch targets are
at least 48 dp tall in a "comfortable" row height setting, 32 dp on desktop.

### Accessibility
Each cell exposes its column name and row (for example "Name, row 3 of 250,
Rex"); the header announces its sort state; arrow-key focus; large text grows
the row height instead of cutting values; colours meet the contrast tests.

### Limits
Show up to 10,000 rows, 200 columns and 4,000 characters per cell in the grid
(copy and export use the full data up to a 50 MB body); bigger bodies parse in
an isolate so the UI does not freeze.

## Phases (one commit each)

### T0. Decide and specify (chore)
- Owner decisions (below). Add requirements FR-RES-0xx and a section in
  `ux.md`. Collect fixtures: a Pet Store list, a nested API response, a CSV, an
  XML list, a 100,000-row array, a ragged array (missing keys).
- Done when: requirements and fixtures are in the repo.

### T1. Table model in `verbnest_core` (minor)
- `ResultTable` data: columns (name, inferred type), rows of typed cells.
  `tableFromJson(Object?, {path, flatten})`, `tableFromXml`, `tableFromCsv`,
  `findTableSources(Object?)` (the candidate arrays), sort and text filter
  helpers, TSV / CSV / JSON / Markdown writers, and the caps.
- Pure Dart, tested on every shape in the list above, ragged rows, duplicate
  keys, unicode, huge numbers, and 100,000 rows (timing).
- Done when: `dart test` in core passes with the fixtures.

### T2. The grid widget (minor)
- `ResultTableView`: pinned header and row numbers, virtualised rows, widths and
  resizing, sorting, cell styling, footer, scrollbars. No selection yet.
- Tests: renders the fixtures, header stays while scrolling, resize and
  sort work, no rebuild of the list on hover (use the notifier pattern from
  `CodeView`), device matrix and large-text tests, goldens (light and dark).

### T3. Wire into the response (minor)
- The Table segment, the "Rows from" selector, filter feeding the grid, table
  text filter, remembered per response, hidden when not tabular. Hex and
  Preview keep working.
- Tests: segment appears only for tabular bodies; filter changes the rows;
  switching back to Pretty keeps the filter.

### T4. Selection, copy, export (minor)
- Cell / row / column / range selection, keyboard navigation, copy as TSV,
  Copy as CSV / JSON / Markdown, Save as CSV, cell detail sheet and dialog.
- Tests: selection and copy output exactly, detail view for nested values.

### T5. Phone polish and accessibility (patch)
- Touch behaviour, 48 dp rows on touch, semantics, large text, the device
  matrix (all profiles, keyboard up), screen-reader labels.

### T6. Performance and limits (patch)
- Isolate parsing above 1 MB, the caps and their notes, a 100,000-row
  scroll test, memory check.

### T7. Docs and release (chore)
- CHANGELOG, `ux.md`, feature inventory, store text mention ("view results as
  a table"), screenshots updated, rebuild packages per the release workflow.

## Order and size

| # | Phase | Release | Size | Needs |
| --- | --- | --- | --- | --- |
| T0 | Decide and specify | chore | S | owner decisions |
| T1 | Table model | minor | M | none |
| T2 | Grid widget | minor | L | T1 |
| T3 | Wire into response | minor | M | T2 |
| T4 | Selection, copy, export | minor | L | T3 |
| T5 | Phone and accessibility | patch | M | T4 |
| T6 | Performance | patch | M | T3 |
| T7 | Docs and release | chore | S | all |

## Decisions needed from the owner

- Build the grid ourselves (recommended) or use `two_dimensional_scrollables`.
- Nested values: one-line JSON preview with an optional flatten switch
  (recommended), or always flatten.
- Read-only grid (recommended). Editing cells and re-sending is out of scope.
- Row cap of 10,000 in the grid, or higher at the cost of memory on phones.
- Whether "Table" should be chosen automatically when a response is a list of
  records (it would change what people see first), or stay opt-in (recommended).

## Risks

- A response of arrays of mixed shapes gives a ragged or empty grid; the
  "Rows from" selector and the filter are the way out, and the segment hides
  itself when nothing is tabular.
- Sorting 100,000 rows on the main thread would stall; sort and filter run on
  the typed rows and are measured in T6 (isolate if over 100 ms).
- Text selection across a virtualised grid is not the platform's text selection;
  we implement cell selection and copy ourselves, and say so in the UI.
- A fifth segment crowds the body switch on a 320 pt phone; the icon-only
  segment and the existing narrow styling are tested at 280 and 320 pt.

## Out of scope

Editing data, charts, SQL, saving a table back into a collection, joining or
combining responses, and column reordering.
