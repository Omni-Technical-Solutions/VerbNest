# UX & Responsive Layout

## 1. Principles
1. **Adaptive, not shrunk.** Width and height classes drive structure, not just scaling.
2. **The request is the unit of work.** Everything (env, auth, scripts, response) is one tap/click from the request.
3. **Always show what will be sent.** Unresolved variables, active environment and TLS-off state are always visible.
4. **Thumb-reachable on phones** (send button, env switcher bottom area), **keyboard-first on desktop**.
5. Material 3 base (seed #EB6A1A, vibrant scheme; opt-in Material You colours on Android) with bundled Inter and JetBrains Mono fonts and platform touches: native menu bar on macOS, Cupertino-style back gestures and sheets on iOS, title-bar integration on Windows/Linux via `window_manager`.

## 2. Layout classes

Width and height both decide the layout (`LayoutClass`, `HeightClass`).

| Width class | Width | Typical devices | Structure |
|---|---|---|---|
| Compact | < 600 dp | Phones (portrait) | Single pane, stack navigation, bottom navigation bar |
| Medium | 600–839 dp | Foldables, tablets portrait, small windows | Navigation rail, list pane; request opens over it |
| Expanded | 840–1199 dp | Tablets landscape, desktop windows | Rail + sidebar + tabbed editor; status bar |
| Large | 1200–1599 dp | Desktop | Permanent navigation drawer (labelled) instead of the rail |
| Extra large | ≥ 1600 dp | Large monitors | As large, with wider panes |

| Height class | Height | Effect |
|---|---|---|
| Compact | < 480 dp | Landscape phones: uses the medium layout, no status bar, request and response side by side, toolbar folded into the URL row |
| Medium | 480–899 dp | Default |
| Expanded | ≥ 900 dp | Default; more room for stacked panes |

Rules that apply at every size:
- **Scroll and fold chrome, do not squeeze panes.** The URL bar is pinned; the toolbar folds away on scroll and when the keyboard is up; a pane never gets less than about 240 dp (the page scrolls instead). See ADR-016.
- Tab rows that scroll sideways fade at the edge that hides content; key/value rows stack under 360 dp.
- Forms and tab bodies use `ScrollIfShort`, so large text, a short window or the keyboard scroll them instead of overflowing.
- Detail views (timings, TLS, variables in effect) open as a draggable bottom sheet on compact widths and a dialog with a Close button elsewhere; dialogs scroll when the window is short.
- Long response lines can wrap (Wrap button; bodies up to 2000 lines). On a phone, a swipe on the Request/Response switch changes pane.
- The status bar shows from 840 dp wide, and not in short windows.

### 2.1 Expanded and larger (desktop, large tablet)
```
┌────┬──────────────┬─────────────────────────────────────────────────────┐
│ R  │ Sidebar      │ [tab] [tab*] [tab] [+]                 env: [dev ▼] │
│ a  │ ┌──────────┐ │ ┌─────────────────────────────────────────────────┐ │
│ i  │ │ search   │ │ │ [POST▼] {{baseUrl}}/pets                [Send]  │ │
│ l  │ └──────────┘ │ ├─────────────────────────────────────────────────┤ │
│    │ ▸ Petstore   │ │ Params  Auth  Headers(3)  Body  Scripts  Tests   │ │
│ C  │   ▾ pets     │ │ ...editor...                                     │ │
│ E  │     GET list │ ├──────────────────────── drag ────────────────────┤ │
│ H  │     POST new │ │ 201 Created · 142 ms · 1.2 KB      [Pretty▼]     │ │
│ ⚙  │ ▸ Auth svc   │ │ Body  Headers  Cookies  Tests  Timing  Raw       │ │
│    │              │ │ ...response...                                   │ │
└────┴──────────────┴─┴─────────────────────────────────────────────────┴─┘
 Rail: Collections, Environments, History, (Runner, Mocks later), Settings
 Bottom status bar: console toggle, cookies, proxy/TLS state, workspace name and save state
```
- Panes resizable and collapsible (`multi_split_view`); layout persisted per workspace.
- Response pane position toggles between right and bottom (Ctrl/Cmd+Alt+L).
- Tabs: preview tab (italic, replaced on next single-click) vs. pinned tab (double-click or edit), like VS Code/Postman.
- Context menus on right-click; drag and drop across tree and into tabs; drop files onto body/import.

### 2.2 Medium (tablet portrait, foldable)
- Navigation rail + list pane (collections/history); the request opens over the list.
- Response appears in a **resizable bottom sheet** over the request editor with three snap points (peek: status line; half; full).
- Tabs collapse into a dropdown "Open requests (4)".

### 2.3 Compact (phone)
```
┌─────────────────────────┐   ┌─────────────────────────┐   ┌─────────────────────────┐
│ Collections     [⌕] [+] │   │ ← Create pet   [dev ▼]  │   │ ← 201 Created  142 ms   │
│ ▸ Petstore              │   │ POST ▼                  │   │ Body Headers Cookies …  │
│   ▾ pets                │   │ {{baseUrl}}/pets        │   │ {                       │
│     GET  List pets      │   │ ─────────────────────── │   │   "id": 1,              │
│     POST Create pet  ›  │ → │ Params Auth Headers Body│ → │   "name": "Rex"         │
│ ▸ Auth service          │   │ … (scrollable tabs)     │   │ }                       │
│                         │   │                         │   │                         │
│                         │   │      [ ▶ Send ]  (FAB)  │   │ [Copy] [Share] [Save]   │
├─────────────────────────┤   └─────────────────────────┘   └─────────────────────────┘
│ Collections Envs History│
│ More                    │
└─────────────────────────┘
```
- Bottom navigation: **Collections, History, Environments, More** (Runner, Settings, Cookies, Import).
- Request screen: method + URL at top (URL field expands to multi-line on focus), segmented scrollable tabs, Send as extended FAB at the bottom right; after send, response slides in as a full-screen route with swipe-back, and a mini status chip stays on the request screen.
- Key-value tables become **list of cards** with swipe-to-disable/delete and a sheet editor for each row; bulk-edit text mode available.
- Editors: full-screen editing mode for bodies and scripts, with an accessory bar above the keyboard: `{ } [ ] " : , {{ }}` and "insert variable".
- Long-press on tree items for actions (rename, duplicate, move, delete, copy as cURL).
- Paste detection: if clipboard contains `curl …` when the user opens "New request", offer to import it.

## 3. Key flows

1. **First run:** Welcome → "Start blank" / "Import (Postman, cURL, OpenAPI)" / "Open folder". No account step. Sample collection optional against the bundled echo endpoints (or the local test server on desktop).
2. **Send a request:** new request → type URL (vars autocomplete) → Send → response. Unresolved vars highlighted before sending.
3. **Switch environment:** env chip in header (all classes); prod-coloured env shows a confirmation on send for non-GET methods (setting).
4. **Import Postman:** pick file(s) or paste JSON/URL → preview tree with counts and warnings (unsupported features) → choose target workspace (or create a new one) → done; summary screen lists anything mapped lossy.
5. **Save from history:** history item → "Save to collection" → pick folder.
6. **Run collection (P1):** collection menu → Run → options sheet (iterations, delay, data file, env) → live results list → export report.
7. **WebSocket session (P1):** connect → split view: composer (bottom) + message log (top) with filters; on phones, log full screen with composer pinned above keyboard.
8. **OAuth 2.0 (P1):** Auth tab → configure → "Get new token" → system browser → callback → token stored → "Use token".

### 3.1 Results table
- A **Table** segment sits in the response body switch (Pretty, Raw, Hex, Preview, Table) and appears only when the body can be read as rows and columns. It is opt-in: Pretty stays the first view.
- The filter box feeds the table: `$.items[*]` in the filter chooses the rows, like a query. When the body holds several arrays a "Rows from" menu names them.
- Grid: pinned header (name and type) and row-number column, resizable columns (double-click fits), sort by header click (ascending, descending, off), `null` muted, numbers right-aligned, long values cut with an ellipsis, a footer ("250 rows, 8 columns", selection count, cap note).
- Select a cell, row (row number), column (header) or range; Cmd/Ctrl+C copies tab-separated; Copy as CSV, JSON, Markdown; Save as CSV. Tap, double-click or Enter opens the full value in a detail sheet (phone) or dialog (desktop).
- Read-only. Nested objects and arrays show as a one-line JSON preview; "Flatten nested keys" turns them into dotted columns.

## 4. Component inventory
- `UrlField` with variable token rendering and autocomplete overlay.
- `KeyValueEditor` (table on desktop/tablet, card list on compact).
- `CodeEditor` wrapper around re_editor (languages: JSON, XML, HTML, JS, GraphQL, YAML, text) with variable overlay, search, fold, format.
- `ResponseViewer` (pretty, raw, hex, preview, tree).
- `EnvSwitcher`, `VariableQuickLook`.
- `AuthEditor` (form per auth type, generated from a descriptor so new types are cheap to add).
- `MessageLog` (virtualised, shared by WebSocket/SSE/Socket.IO/gRPC streams/MQTT).
- `TreeView` with drag & drop and keyboard navigation.
- `AdaptiveScaffold` choosing compact/medium/expanded shell.

## 5. Keyboard shortcuts (desktop & iPad hardware keyboard)

| Action | Windows/Linux | macOS |
|---|---|---|
| Send | Ctrl+Enter | Cmd+Enter |
| New request | Ctrl+N | Cmd+N |
| Save | Ctrl+S | Cmd+S |
| Close tab | Ctrl+W | Cmd+W |
| Next / prev tab | Ctrl+Tab / Ctrl+Shift+Tab | Ctrl+Tab / Ctrl+Shift+Tab |
| Search / command palette | Ctrl+K / Ctrl+Shift+P | Cmd+K / Cmd+Shift+P |
| Focus URL | Ctrl+L | Cmd+L |
| Toggle sidebar | Ctrl+B | Cmd+B |
| Switch environment | Ctrl+E | Cmd+E |
| Toggle console | Ctrl+Alt+C | Cmd+Opt+C |

Shortcuts configurable in Settings (P1).

## 6. Visual & accessibility
- Method colours (GET green, POST amber, PUT blue, PATCH purple, DELETE red, others grey) always paired with text (not colour alone).
- Status colours 2xx green, 3xx blue, 4xx amber, 5xx red, with text.
- Minimum touch target 48 dp; desktop density "comfortable/compact" toggle.
- All interactive widgets have `Semantics` labels; editor content exposed to screen readers line-by-line; response status announced via live region after send.
- Respects OS text scale up to 200 % without clipping on compact layouts (horizontal scroll inside editors only).
- High-contrast theme variant (P1).
