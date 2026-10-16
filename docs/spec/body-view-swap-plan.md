# Body view: one-frame swaps and a sharp table (0.64.2)

Owner report (0.64.1): the table in the response body looks blurred, and changing
the body view (Pretty, Raw, Hex, Table) animates.

## Findings
- **Layout step a frame late.** Choosing Table asked the editor for the whole
  height in a post-frame callback, so frame 1 showed the table in the small pane
  and frame 2 moved the whole response up about 430 px. Captured on the macOS
  renderer: the first frame after the tap differed from the settled screen.
- **Scrollbar pops in a frame late.** The always-shown horizontal bar of the code
  view and the table is a `RawScrollbar`, which learns the content size from a
  notification sent after layout, so its thumb appeared one frame after the view.
- **Soft geometry.** Pane sizes (`total * ratio`), column widths (measured text)
  and row heights (`13 * scale * 1.9`) were fractional, putting rules, cell edges
  and text between device pixels.
- Not reproduced: on this machine (Intel Mac, Retina, debug build) the table
  captured from the real screen is sharp. No blur, opacity or scaling is applied
  to the table anywhere in the code.

## Changes
1. The room request is synchronous (same `setState` pass as the mode change) and
   only in a stacked layout; side by side the table already has the height.
2. `StillScrollbar` with `thumbVisibility` and a controller paints its own thumb
   from the controller at paint time (same frame as the content), draggable.
3. Whole pixels: `SplitView` rounds the first pane to a device pixel; the table
   rounds column widths (fit and drag) and row/header heights.

## Tests
- `test/table_room_test.dart`: after each mode tap, the first frame equals the
  settled layout, and the grid's origin is on whole pixels (1280x800, 1000x700).
  Fails on the 0.64.1 post-frame code.
- `integration_test/body_view_frames_test.dart` (run with `-d macos`): on the real
  renderer, the image of the first frame after each mode tap equals the image
  300 ms later.

## Follow-up 0.64.3: the blur was the renderer
A screen recording of the installed 0.64.2 on the owner's MacBook Pro (Intel UHD 630
+ AMD Radeon Pro 5500M) showed glyphs in the Pretty view and the table drawn as
speckled blocks ("10178" with a broken 0 and 7, "SL2" with a broken 2) that changed
between frames while nothing else moved. That is glyph atlas corruption in Impeller,
which on macOS is on by default and always draws text as signed distance fields
(`FlutterDartProject.enableSDFs` returns YES). The macOS app now sets
`FLTEnableImpeller` to false, so the engine logs "Using the Skia rendering backend
(Metal)". Guarded by `test/macos_renderer_test.dart`.
