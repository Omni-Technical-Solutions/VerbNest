# UI modernisation plan (Material 3)

Status at v0.46.0. v0.45.0 laid a foundation (design tokens, rounded inputs,
split panes, undo, command palette grouping). This plan brings the UI in line
with the Material 3 specification (m3.material.io) on phones, tablets and
desktop, and adds a visual regression net. Each phase is one release: its own
commit, version bump, CHANGELOG entry, context update and tests. Analyze and
all tests must pass before each commit.

## Standards baseline

The target is **Material 3** as shipped by Flutter 3.47.5 and the `material_ui`
package (Material was split out of the framework; the app still imports
`package:flutter/material.dart`).

| Area | Material 3 rule | Where the app differs today |
| --- | --- | --- |
| Window size classes | Compact < 600, Medium 600-839, Expanded 840-1199, Large 1200-1599, Extra-large 1600+ dp | Code uses 600 and 1024; `ux.md` uses 600 and 1200. Three sources disagree. |
| Navigation | Navigation bar on Compact, rail on Medium and up, navigation drawer on Large and up | Bar and rail only; no drawer |
| Canonical layouts | List-detail on Expanded and up, supporting pane on Large and up | Medium has no list pane; iPad portrait (1032 pt) gets the desktop layout |
| Colour | `ColorScheme.fromSeed` roles, including the surface-container roles, with contrast levels | Seed gives a brown primary that does not match the orange icon; about 20 hard-coded colours |
| Type | Display, headline, title, body, label roles, each with a size, weight and tracking | Default scale, no role tuning, no bundled font |
| Shape | Scale of 0, 4, 8, 12, 16, 28 dp and full | Tokens 6, 10, 16, which are off the scale |
| Elevation | Tonal surfaces first, shadow second | Heavy outlined cards in Settings |
| State layers | Hover 8%, focus and pressed 10%, drag 16% | Mostly default; not reviewed per control |
| Motion | `Durations` (short1 to extraLong4) and `Easing` (standard, emphasized) tokens | Own 120, 200 and 320 ms with `easeOutCubic` |
| Touch targets | At least 48 x 48 dp | Not audited |
| Components | Segmented button, search anchor, filled tonal button, bottom and side sheets, primary and secondary tabs | Dialogs only; custom pill toggles |

**Material 3 Expressive.** Not in this SDK: no button groups, spring motion
scheme, loading indicator or floating toolbar. Only the `expressive` colour
variant (`DynamicSchemeVariant.expressive`) exists. The plan therefore targets
standard Material 3, keeps every Expressive-style choice behind the theme
(shape, motion and colour tokens in one place), and re-checks the SDK before
each release.

## Review findings

Evidence: the rendered screens in `docs/release/screenshots/` (iPhone, iPad,
Android, macOS) and a read of `lib/src`.

**What works.** Design tokens exist. Dark theme, reduced motion, RTL and a
golden test kit are in place. Desktop (1440 px) reads well.

**Problems, most visible first.**

1. **The request editor does not fit a phone.** At 402 pt the controls take
   four stacked rows. The URL field shrinks to about 3 characters (`{{bas`).
   The tab row is clipped and its trailing layout icon overlaps the last tab.
   Response tabs read "Cookie", "Heade", "Tests (". A 50/50 split leaves large
   empty areas.
2. **Desktop affordances leak onto touch.** The Send button shows a `⌘↵` badge
   whose `↵` renders as a box on Apple platforms; the empty state says
   "Ctrl/Cmd + Enter" on a phone.
3. **Brand mismatch.** Bright orange icon, muddy brown UI accent, no logo in
   the app.
4. **Breakpoints disagree** with the spec and with Material 3 (table above).
5. **Dialogs everywhere, sheets nowhere.** About 20 `showDialog` calls and no
   bottom sheets, so the palette, search, code, runner and examples open as
   centred desktop dialogs on phones.
6. **Little layout awareness.** About 8 of roughly 50 UI files look at width;
   about 20 fixed widths of 100 px or more. The environment table truncates to
   `baseUr`, `https://`, `Curr…`. Settings is a very wide column of outlined
   cards.
7. **Typography is defaults**, with small response text.
8. **Hard-coded colours remain** (about 20 sites outside `app_tokens.dart`).
9. **Platform feel is uniform** and safe-area, predictive-back and
   edge-to-edge were never reviewed.
10. **No visual regression net.** Goldens use the Ahem font; the screenshot
    harness is not compared to a baseline.

## Decisions needed from the owner

- Brand colour: the icon's orange as the seed (recommended), or keep the
  current brown.
- Bundle fonts (Inter plus JetBrains Mono, both OFL, about 1.5 MB) or stay on
  system fonts.
- Android Material You dynamic colour: opt-in, or skip.

## Phase 0: Move to `material_ui` (chore)

Material left the framework. Do this first so later work targets the package
that will receive fixes.

- 0a. `dart fix --apply --code=migrate_design_widgets` (also moves Cupertino
  to `cupertino_ui`); switch localisation delegates to the package versions.
- 0b. Check third-party packages that import `package:flutter/material.dart`;
  use `MaterialUiCompatibilityBridge` only if one breaks.
- Done when: analyze clean, all tests pass, release builds of macOS, iOS and
  Android succeed with no visual change (compare screenshots).
- Risk: a mechanical change touching many files; keep it a commit of its own.

## Phase 1: Fit phones (patch, v0.46.1)

Fixes findings 1 and 2. No visual redesign yet, so it ships fast and improves
the store screenshots.

- 1a. Compact request editor: method and Send on one row, URL full width on its
  own row, favourite, Examples and environment behind one overflow menu.
- 1b. Scrollable tab bars (request and response) with an edge fade, no overlap
  with the layout toggle; hide the layout toggle on Compact.
- 1c. Hide keyboard hints when there is no hardware keyboard; replace the `↵`
  glyph with one the mono font has.
- 1d. Compact environments and key/value editors stack name above value.
- 1e. Response pane on Compact follows its content (collapsed until a send).
- Done when: no overflow at 320, 360, 402 and 600 wide; the URL shows at least
  20 characters on a 402 pt phone; screenshots regenerated and read by eye.
- Risk: widget tests find controls by key; keep keys stable.

## Phase 2: Material 3 visual system (minor, v0.47.0)

Fixes findings 3, 7 and 8, and the colour, type, shape, elevation, state and
motion rows of the baseline.

- 2a. Colour: seed from the icon orange; use the surface-container roles for
  panes, cards and the sidebar; test text and badge contrast against WCAG AA
  in light and dark; keep the accent picker; offer the `expressive` variant
  as a Settings choice only if it passes the contrast test.
- 2b. Shape: replace the 6, 10, 16 radii with the Material 3 scale (4, 8, 12,
  16, 28) and map every component to a step.
- 2c. Type: define the role-based text theme (title, body and label sizes),
  bundle fonts if approved, tabular figures for timings and sizes, larger
  response body text.
- 2d. Elevation and state: tonal surfaces and filled cards instead of heavy
  outlines; verify hover, focus and pressed layers on every control; 48 dp
  minimum targets on touch.
- 2e. Motion: replace the custom durations and curve with the SDK `Durations`
  and `Easing` tokens; keep reduced-motion behaviour.
- 2f. Components: `SegmentedButton` for Pretty, Raw and Hex and for the theme
  choice; `FilledTonalButton` for secondary actions; primary tabs for the
  request editor and secondary tabs inside panels.
- 2g. Logo in the empty state and About; move the remaining hard-coded colours
  into `AppColors` and add a test that fails on new `Color(0x…)` or `Colors.x`
  outside the tokens file.
- Done when: goldens regenerated in both themes, contrast test passes, no
  hard-coded colours outside tokens.
- Risk: every golden changes at once; do this phase alone and review the new
  goldens by eye before accepting them.

## Phase 3: Adaptive layout (minor, v0.48.0)

Fixes findings 4, 5 and 6.

- 3a. One `LayoutClass` with the five Material 3 window size classes; update
  `ux.md` and remove the other two breakpoint sets.
- 3b. Compact: navigation bar, one pane, request and response as a segmented
  control ("Request | Response").
- 3c. Medium: navigation rail and one pane at a time (collection list, then
  request), response as a tab.
- 3d. Expanded (iPad portrait, small windows): rail plus list-detail, with the
  collections list on the left and the request and response on the right.
- 3e. Large and Extra-large: add the navigation drawer (permanent) and move
  the response to a supporting pane beside the request; cap content width.
- 3f. A shared `showAdaptiveSheet`: bottom sheet or full-screen route on
  Compact, side sheet or dialog otherwise. Move the palette, search, code,
  runner, examples and import onto it.
- 3g. Max content width (about 720) for Settings, Environments and History.
- Done when: every screen is checked at 360, 402, 600, 840, 1032, 1280 and
  1600 wide with no overflow, and the screenshot sets show the new layouts.
- Risk: open tab, scroll position and selection must survive a layout change
  when a window is resized or a tablet rotates.

## Phase 4: Desktop polish (minor, v0.49.0)

- 4a. Bottom status bar from `ux.md` (console toggle, cookies, proxy and TLS
  state, workspace and save state).
- 4b. Preview and pinned tabs, drag to reorder, pane layout persisted per
  workspace.
- 4c. macOS: native menu bar (File, Edit, View, Window), unified title bar,
  shortcuts shown in the menus.
- 4d. Visible focus ring and logical focus order on every control.
- Done when: a keyboard-only pass covers send, switch tab, open the palette and
  change environment with no mouse.

## Phase 5: Platform polish and accessibility (minor, v0.50.0)

Fixes finding 9.

- 5a. iOS: safe areas, swipe-back, sheet presentation, haptics on send and
  copy, Dynamic Type up to the largest setting.
- 5b. Android: edge-to-edge, predictive back, optional Material You colour (if
  approved).
- 5c. Accessibility: semantic labels on icon-only buttons, text scale 200%
  without clipping, TalkBack and VoiceOver walkthrough of the send flow.
- Done when: text scale 2.0 shows no clipped or overlapping text on the main
  screens, and both screen readers can send a request unaided.

## Phase 6: Visual regression (chore)

Fixes finding 10. Start alongside phase 2 so it guards every later phase.

- 6a. Load real fonts in goldens (as the screenshot harness already does).
- 6b. Golden matrix: key screens in each of the five size classes, light and
  dark, plus Arabic (RTL).
- 6c. An overflow test that pumps each main screen at the widths above and
  fails on any `RenderFlex` overflow.
- 6d. A script compares new device screenshots with the committed ones and
  lists the screens that changed.
- Done when: CI fails on a layout overflow or an unreviewed visual change.

## Order and effort

| Phase | Release | Size | Why this order |
| --- | --- | --- | --- |
| 0 Move to `material_ui` | chore | S | Mechanical; later work targets the supported package |
| 1 Fit phones | 0.46.1 | S | Biggest user-visible defect, cheap, improves store images |
| 6 Visual regression (start) | chore | S | Net in place before the large visual changes |
| 2 Material 3 visual system | 0.47.0 | M | Changes every screen once, then stays stable |
| 3 Adaptive layout | 0.48.0 | L | Largest structural change; builds on stable tokens |
| 4 Desktop polish | 0.49.0 | M | Independent of mobile work |
| 5 Platform polish and accessibility | 0.50.0 | M | Best done once layouts have settled |

## Not in scope

New features, a rewrite of the editors, web, replacing Material with a custom
widget set, and Material 3 Expressive components until the SDK ships them.
