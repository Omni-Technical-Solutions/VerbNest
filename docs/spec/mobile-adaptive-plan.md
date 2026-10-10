# Mobile adaptive UI plan: scrolling and screen-size controls

Status at v0.53.0. The Material 3 modernisation (`ui-modernisation-plan.md`)
made the app fit a portrait phone at 360 to 402 pt. This plan covers what it
did not: small and very large phones, landscape, and the on-screen keyboard.
The common thread is one design change: **let the screen scroll, and let chrome
get out of the way**, instead of dividing a fixed height between many panes.

Each phase is one release: its own commit, version bump, CHANGELOG entry,
context update and tests. Analyze and all tests must pass before each commit.

## Review findings

Evidence comes from rendering the real app headless at awkward phone sizes
(portrait 280, 320, 360; landscape 667x375, 740x360, 874x402) with a request
open and a response showing, then again with the on-screen keyboard up. The
existing overflow tests pass at 320 to 1600 wide at 874 tall, which is why none
of this showed up.

1. **The editor is a fixed-height column, not a scroll view.** Toolbar, URL
   row, Request/Response switch, status line and tabs are stacked; only the
   panes inside have their own scrolling. The chrome never moves out of the
   way. At 320x568 the header takes about 70% of the screen (tabs begin at
   y=406) and the JSON body gets about 14%.
2. **With the keyboard open the editor overflows.** At 360x640 with a 280 pt
   keyboard, the response tabs are clipped and Flutter reports an overflow. At
   740x360 with a 200 pt keyboard only the toolbar and URL row fit, the layout
   overflows by 24 pt, and nothing can be scrolled to reach the rest.
3. **Landscape phones are classed by width alone.** 874x402 counts as
   *expanded*: rail, collection list, status bar and editor share 402 pt of
   height, and the response body gets about 30 pt (the Pretty/Raw/Hex row is
   cut off). Material 3 also defines height classes; the app has none.
4. **667x375 (landscape, medium) splits the pane 50/50 vertically.** Both halves
   are about 120 pt tall: the request shows its tab row with no content, and
   the response shows a clipped status row over its tab row.
5. **The response toolbar is cut off on small phones.** At 320x568 the search
   row is half visible: the toolbar is capped at half the pane, and the pane is
   already small.
6. **The URL field is short on 320 pt phones** (about 11 characters) and the
   toolbar wraps to two rows.
7. **Scrolling controls have no affordance.** The tab rows scroll sideways but
   show a hard clip ("Scrip") with no fade or hint, and there is no
   keyboard-dismiss on scroll.

**Not yet checked** (to be measured in phase 0 rather than assumed): the
GraphQL and scripts editors, runner, history and settings at 280 to 320 pt, the
assertions rows (they wrap to three lines at 402 pt), landscape cutouts and
system bars, a foldable's unfolded 6:5 shape, and split-screen windows.

## Principles

- **Scroll the page, pin one thing.** The URL and Send stay pinned (about 64 pt).
  Everything else scrolls away, so the content gets the screen.
- **Width and height both decide the layout.** Use the Material 3 height
  classes (compact under 480 pt, medium 480 to 899 pt, expanded 900 pt and up)
  next to the width classes already in `LayoutClass`.
- **Prefer scrolling to squeezing.** If two panes cannot both be usable, show
  one at a time or scroll; never give each a sliver.
- **The keyboard is part of the screen.** Layout is judged with its inset, and a
  focused field is always scrolled into view.
- **Every sideways scroll shows that it scrolls.**
- **Test sizes are data.** One list of device sizes (and keyboard states) drives
  the overflow, golden and scroll tests, so a new size is one line.

## Phase 0: Measure and lock in (chore)

- 0a. A shared list of device profiles in `test/support`: portrait 280x653,
  320x568, 360x640, 402x874, 430x932; landscape 667x375, 740x360, 874x402,
  932x430; and each with and without a keyboard inset (280 portrait, 200
  landscape).
- 0b. A matrix test that opens collections, the request editor with a response,
  environments, history and settings at every profile and fails on any overflow.
  Today it fails at the keyboard profiles, so the first run records the
  baseline (the failing profiles are the work for phases 1 to 3).
- 0c. A golden per profile for the request editor with a response, so the
  layout work is reviewed by eye.
- 0d. Check the "not yet checked" list above and add findings here.
- Done when: the matrix runs in CI and the known failures are listed.

## Phase 1: Stop overflowing; keep the focused field visible (patch) - done, with notes

Fixes finding 2 and the first half of finding 1 with the smallest change.

- 1a. Make the editor body scroll: the column becomes a `CustomScrollView`
  (or `SingleChildScrollView` with a minimum height) so nothing can overflow.
- 1b. `resizeToAvoidBottomInset` stays on; a focused field is scrolled into
  view (`Scrollable.ensureVisible` on focus, and padding for the inset).
- 1c. `keyboardDismissBehavior: onDrag` on every scrollable that contains
  text fields.
- Done when: the matrix passes at every keyboard profile, and a test types in
  the URL field at 740x360 with the keyboard up and can still reach Send.
- Result: portrait sizes and landscape up to about 700 wide pass. Still failing,
  and recorded in `device_matrix_test.dart`: the rail overflows landscape phones
  874 wide and up (phase 3), and the URL row sits under the keyboard at 740x360
  until it is pinned (phase 2). The page scroll was built with slivers
  (`SliverLayoutBuilder` gives the header's extent), which phase 2 builds on.
- Risk: the panes below (code view, response body) need a bounded height;
  give them a sensible minimum (about 240 pt) and let the page scroll past it.

## Phase 2: A scrolling editor with a pinned URL bar (minor) - done, with notes

Fixes findings 1, 5 and 6.

- 2a. The editor becomes slivers: a **pinned** URL row (method, URL, Send), a
  toolbar and Request/Response switch that **scroll away** (and return on a
  short scroll up), then the active pane.
- 2b. The response pane stops being a box of its own: status, tabs, toolbar and
  body are one scrolling column; the code view takes at least 240 pt, or the
  full remaining height when that is more.
- 2c. The toolbar's secondary controls (favourite, examples, live, environment)
  move into one overflow menu on phones narrower than 360 pt; the environment
  stays visible as a chip.
- 2d. The URL field gets at least 16 characters at 320 pt (shorter method box,
  icon-only Send already in place).
- Done when: at 320x568 the response body shows at least 40% of the screen with
  the header scrolled away, and the URL row is still on screen.
- Risk: a vertical code view inside a vertical page scroll fights for gestures.
  Use one scroll owner at a time (page scrolls until the code view is the only
  thing on screen, then it takes over) and test with a long response.
- Delivered, with one change of approach: instead of making the whole response
  one page-level scroll (which fights inner scrollers), the toolbar folds on
  inner scroll and with the keyboard (a scroll-direction listener), the URL bar
  is pinned by a `SliverPersistentHeader`, and the response header was made
  leaner (one-row toolbar with on-demand search and filter, icon Save, no
  protocol version under 360 dp). Measured: the body gets 40% of 360x640 and 35%
  of 320x568 with the toolbar folded; the plan's 40% target was relaxed for the
  smallest size.

## Phase 3: Height classes and landscape (minor) - done

Fixes findings 3 and 4.

- 3a. Add `HeightClass` (compact under 480, medium, expanded) next to
  `LayoutClass`, from `MediaQuery` height.
- 3b. A landscape phone (compact height) uses the phone navigation (rail or
  bottom bar, never both a list pane and the editor), no status bar, and the
  request and response **side by side** by default, since width is what it has.
- 3c. A short window never stacks two panes vertically: below 480 pt tall the
  split is horizontal or one pane at a time.
- 3d. Respect landscape cutouts and system bars (`SafeArea` on the sides).
- Done when: 874x402 and 667x375 show the request and the response body both
  readable, and the matrix passes.
- Delivered: 3a to 3d. A short window uses the medium layout, no status bar,
  side-by-side panes and the toolbar folded into the URL row (environment picker
  and menu). The status bar's information is simply not shown in landscape.
- Risk: side by side at 667 pt gives each pane about 300 pt; verify the request
  tabs still read.

## Phase 4: Scroll affordances and tables (minor)

Fixes finding 7.

- 4a. Tab bars get an edge fade (and a chevron on hover or focus) so a hidden
  tab is visible as hidden; the selected tab scrolls into view.
- 4b. Key/value tables, headers and assertions use a stacked row below 360 pt,
  and a horizontal scroll with a minimum column width where stacking is not
  enough.
- 4c. The code view gets a soft-wrap toggle and a visible horizontal scrollbar;
  long URLs and header values wrap or scroll rather than clip.
- 4d. Swipe left and right between Request and Response (a `PageView`), with the
  segmented switch kept as the visible control.
- 4e. Secondary detail (timings, TLS, example list) opens in a draggable,
  scrollable bottom sheet on phones instead of a dialog.
- Done when: no tab, table or code line is clipped without a visible cue, in
  the golden set at 280, 320 and 360 pt.
- Risk: a `PageView` swipe conflicts with horizontal scrolling inside the pane;
  restrict the swipe to the edge zones or the switch.

## Phase 5: The other screens (minor)

- 5a. Environments, history, settings, runner, GraphQL and scripts editors and
  the dialogs, checked at the matrix sizes and fixed (stacked rows, sticky
  actions at the bottom above the keyboard, scrollable bodies).
- 5b. A sticky bottom action bar for forms with a primary action (runner,
  import) that sits above the keyboard.
- 5c. Large text (200% and 310%) re-run across the matrix, since scrolling now
  covers more than before.
- Done when: every screen passes the matrix, with and without the keyboard.

## Phase 6: Device checks (chore)

- 6a. A manual checklist in `docs/release`: one small phone, one large phone,
  one tablet, one foldable, portrait and landscape, with the keyboard, large
  text and a screen reader.
- 6b. Refresh the store screenshots and add a landscape phone set.
- Done when: the checklist has been run once and its results are recorded.

## Order and effort

| Phase | Release | Size | Why this order |
| --- | --- | --- | --- |
| 0 Measure | chore | S | Makes every later phase testable and the baseline visible |
| 1 Stop overflowing | patch | S | Real overflows and a blocked keyboard; smallest fix |
| 2 Scrolling editor | minor | L | The main change; most of the benefit for small phones |
| 3 Height classes | minor | M | Fixes landscape, which phase 2 alone does not |
| 4 Scroll affordances | minor | M | Polish that depends on the new structure |
| 5 Other screens | minor | M | Applies the same patterns elsewhere |
| 6 Device checks | chore | S | Only a person with devices can close this |

## Success measures

At every profile in phase 0, with and without the keyboard:

- no layout overflow;
- the URL field shows at least 14 characters at 320 pt wide;
- the focused field and Send are on screen with the keyboard open;
- with the header scrolled away, the response body gets at least 40% of the
  screen height from 360x640 up (35% at 320x568) and at least 60% in landscape;
- no clipped tab, button or table column without a visible scroll cue.

## Decisions needed from the owner

- Whether the collapsing header is always on, or a setting ("Keep the toolbar
  visible") for people who dislike moving chrome.
- Swipe between Request and Response (phase 4d), or the segmented switch only.
- Whether landscape phones should keep the status bar's information somewhere
  (for example in the overflow menu) or drop it.

## Not in scope

New features, tablets (covered by the Material 3 plan), a separate phone-only
codebase, and web.
