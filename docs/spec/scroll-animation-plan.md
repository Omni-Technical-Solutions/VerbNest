# Plan: no animation while scrolling a response

Status: S0, S2 and S3 done in 0.59.4 (measured by tests: the copy-path icon appeared during wheel scrolling and the physics were not clamping); S1 done for desktop only (no scroll fold on desktop platforms), touch folds when the scroll ends (0.59.5), not during the drag. Report: "there seems to be animation
when scrolling through request results". Scrolling the response should only
move the content; nothing around it should move, resize, fade or flicker.

## Review

What scrolls: the response body is `CodeView` (a virtualised `ListView.builder`
inside a horizontal `SingleChildScrollView`, with a `Scrollbar`), inside the
response pane, inside the request editor's page-level `CustomScrollView`
(`request_editor.dart`).

### Cause confirmed in the code

**1. The toolbar folds with a size animation while you scroll (phones and
short windows).** `_RequestEditorState._onScroll` listens to every vertical
scroll of a pane at depth > 0. While a finger drags downwards it sets
`_hiddenByScroll = true`; scrolling back up (or reaching the top) sets it to
false. The toolbar is wrapped in an `AnimatedSize` (about 200 ms), so each
change of direction resizes the whole page, and the response pane (which is
laid out from the space that is left) is resized *during* the drag. The content
under the finger jumps and animates. It also flips back whenever the finger
changes direction by more than 2 px, so a normal "scroll down, nudge back"
triggers it twice. This was a deliberate feature (phase 2 of the mobile plan:
fold the toolbar to give the body room) and is the most likely thing seen on a
phone or in a narrow window.

### Suspected causes (to confirm by measuring, phase S0)

**2. Hover rebuilds in the code view (desktop, mouse wheel).**
`CodeView` wraps every row in a `MouseRegion` whose `onEnter`/`onExit` call
`setState` (`_hoverRow`). With a wheel or trackpad the pointer stays still and
rows move under it, so enter/exit fire continuously during the scroll. Each
fires a `setState` that rebuilds the whole list, and the hovered row swaps its
line number for the "copy JSON path" icon, so the gutter visibly flickers while
scrolling. This is the most likely cause on the Mac.

**3. The scrollbar fades.** `thumbVisibility` is on only when a line runs past
the edge; otherwise the (desktop) scrollbar thumb fades in and out around each
scroll (`scrollbarTheme` in `theme.dart`). Normal behaviour, but it reads as
animation if the thumb is thick or the fade is long.

**4. Overscroll effects.** On macOS and iOS the default physics bounce at the
ends of the response; on Android the stretch effect shows. A fast scroll to the
end of a long result shows a rubber-band animation.

**5. Hover and focus animations on the fold arrows** (`InkWell` ink and
hover fade on each fold chevron as rows pass under the pointer).

**6. Selection.** `SelectionArea` around the list can start a selection drag
and auto-scroll when the pointer is held down at an edge.

Ruled out by reading: the `AnimatedSwitcher` around the response only runs when
the response state changes (sending, error, empty, response), not on scroll;
the pane switch swipe (0.59.0) only reacts to horizontal drags on the switch.

## Plan

### S0. Measure first (chore, no release)
- Ask which platform and how it looks (phone, narrow window or wide desktop;
  mouse wheel, trackpad or touch; what moves: the toolbar, the gutter, the
  scrollbar, the end bounce). This picks the order below; with no answer, do
  S1 and S2, which cover the two likeliest cases.
- Add a widget test that scrolls a long response (2000 lines) and records, per
  scroll step: the pane's height, the number of times `CodeView` rebuilds, and
  whether the toolbar's size changed. Expected today: the toolbar size changes
  on a drag (cause 1) and `CodeView` rebuilds on every pointer enter/exit
  (cause 2). This test then becomes the regression guard for S1 and S2.
- Done when: each suspected cause is confirmed or ruled out with a number.

### S1. The toolbar must not change size while scrolling (patch)
Choose one (recommended: a):
- a. **Fold only at rest, not during the drag.** Keep the feature but apply the
  change when the scroll ends (`ScrollEndNotification`) and only when the pane
  is at the top, so the content never resizes under a finger; or
- b. **Stop folding on scroll.** Keep folding only for the keyboard and short
  windows, and let the page scroll the toolbar away naturally (the toolbar is
  already a sliver).
- Tests: no toolbar size change during a drag; the keyboard fold still works;
  the 35%/40% body-height measures in `editor_chrome_test.dart` are re-checked,
  since they were met with the scroll fold.
- Done when: dragging up and down a long response changes nothing but the
  content.

### S2. The code view must not rebuild or flicker on scroll (patch)
- Move the hover state out of `setState` on the whole view: use a
  `ValueNotifier<int?>` and a small `ValueListenableBuilder` in each row's
  gutter only, so hover repaints one row instead of the list.
- Ignore hover while the list is scrolling (track `ScrollStartNotification` /
  `ScrollEndNotification`), and show the copy-path icon only after the pointer
  has really moved onto the row, so rows passing under a still pointer do not
  swap their line number.
- Tests: scrolling 2000 lines causes no `CodeView` rebuild from hover; the copy
  icon still appears on a pointer move and the copy-path tests pass.

### S3. Calm the scrollbar and overscroll (patch, only if S0 shows them)
- Scrollbar: shorter fade, no animation of thickness, `thumbVisibility` always
  on for the code view on desktop.
- Physics: `ClampingScrollPhysics` for the code view on every platform (no
  bounce) and no stretch indicator on the response (`ScrollBehavior` with
  `buildOverscrollIndicator` returning the child).

### S4. Release (chore)
- Full test run, CHANGELOG entry, context entry, version bump (patch), commit
  and tag, rebuild packages for the release workflow. Owner: confirm on the
  Mac and on a phone that the motion is gone.

## Order and size

| # | Phase | Release | Size | Why |
| --- | --- | --- | --- | --- |
| S0 | Measure | chore | S | Confirms which causes are real |
| S1 | Toolbar fold | patch | S | Confirmed in code; biggest visible movement |
| S2 | Code view hover | patch | S | Likeliest desktop cause |
| S3 | Scrollbar and bounce | patch | S | Only if measured |
| S4 | Release | chore | S | Packages |

## Decision needed

S1: fold at rest (keeps the extra room the fold gave phones) or remove the
scroll fold altogether (simplest, no resize ever). Recommended: fold at rest.

## Risks

- Removing the scroll fold gives the response less room on a 320 pt phone
  (the 35% target was met only with the fold); S1 option a keeps the room.
- Disabling hover during scroll must not break the keyboard and touch paths to
  copy-path (long-press/tap on touch).
