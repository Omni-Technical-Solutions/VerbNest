# ADR-020: No animation

Status: accepted (v0.64.0)

## Context
The Material 3 modernisation (v0.46 to v0.50) added transitions: cross-fades between states, a fade and scale on the Send button, sliding tab indicators and navigation selection, menus and dialogs that open over 150 to 500 ms, a pulsing placeholder while a request is in flight. The owner saw these as broken or distracting (switching the response view, and sending a request), and asked for everything to simply swap.

## Decision
Nothing in the app animates. A change of state is shown at once.

How, in layers:
- **Central:** `Motion.of` returns zero; `MaterialApp` has `themeAnimationDuration` zero and the app tells widgets `disableAnimations`; the theme has no page transitions (`_NoTransitions` on every platform), no splash, hover or press tint, and buttons change colour at once; the text cursor stays solid (`EditableText.debugDeterministicCursor`); lists have no bounce or glow.
- **Call sites:** every dialog, sheet, menu and snackbar is shown with `AnimationStyle.noAnimation`; expansion tiles and tab controllers have zero duration; page routes are `StillPageRoute` (zero duration); spinners and the progress bar are still, and the placeholder does not pulse.
- **Replaced widgets** (Material's own animate with no switch to turn that off): `StillTabBar`, `StillNavigationBar/Rail/Drawer`, `StillDropdown` (Material's `DropdownMenu` opens over 500 ms), `StillSwitch(ListTile)`, `StillCheckbox(ListTile)`, `StillChip`, `StillSlider`, `StillScrollbar` (no fade), in `lib/src/widgets/ui/`.

## How it is checked
`test/no_motion_audit_test.dart` tours the app (navigation, tabs, views, table, menus, dropdowns, dialogs, sheets, switches, sliders, text fields, scrolling, hover) and takes the screen at 76 ms and 136 ms after every action: the two must be identical. It also checks the caret does not blink. `test/no_motion_test.dart` counts running animations while a request is in flight. Counting running animations alone is not enough (a transparent tap highlight still runs a timer), so the audit compares pixels.

## What still moves, and why
- A change of accent or of light/dark: Material surfaces (`Scaffold`, cards) cross-fade their colour over 200 ms and Flutter has no switch for it.
- A touch tap in a text field shows the selection handle, which the system fades in; the on-screen keyboard and the platform back gesture are the operating system's; a flick scrolls with inertia (physics, not an animation of the UI).
- The tap highlight is invisible but still runs a short timer.

## Consequences
Hover, press and focus-ring tints are gone (keyboard focus keeps a tint); text fields show focus with the caret, not a thicker outline; the response is unchanged in content. A setting to bring motion back was not built; `Motion` keeps its Material 3 tokens so one could be.


## Update 0.64.1
Tooltips no longer fade: `StillTooltip` (a `RawTooltip` with no animation) and `StillIconButton` (label as a `Semantics` label on the icon) replace `Tooltip` and `IconButton(tooltip:)`. Still moving: the accent/theme surface cross-fade and the system's touch selection handle.
