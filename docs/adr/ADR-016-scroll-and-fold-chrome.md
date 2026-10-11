# ADR-016: Scroll and fold chrome rather than one page scroll

Status: accepted (v0.53.0 to v0.57.0)

## Context
The editor stacked toolbar, URL row, request/response switch and panes in a fixed-height column. On small phones, in landscape and with the keyboard up, the chrome took most of the screen and the panes overflowed or shrank to slivers.

## Decision
Keep inner panes (code view, tables) as their own scrollers, and make the chrome give way instead of making the whole response one page scroll:
- the URL bar is pinned (a persistent sliver header);
- the toolbar folds on inner scroll and when the keyboard opens;
- panes have a minimum height (about 240 dp) and the page scrolls past it;
- short windows (< 480 dp tall) use side-by-side panes and fold the toolbar into the URL row;
- forms use `ScrollIfShort`.

## Consequences
One scroll owner at a time, so a vertical code view does not fight a page scroll. Layout is checked by the device matrix (sizes x keyboard x large text), so a new size is one line of test data. Soft wrap and the pane swipe were left out at first and added in 0.59.0: wrap re-lays rows out freely only for bodies within 2000 lines and 20000 characters per line (otherwise rows stay fixed height); the swipe is limited to the pane switch.
