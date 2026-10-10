# Device checklist

Automated tests cover layout (the device matrix at nine phone sizes, with and
without the keyboard, and large text), but they cannot show how the app *feels*
or check what only a real device does. Run this once per release candidate and
record the result at the bottom. See `docs/spec/mobile-adaptive-plan.md`.

## Devices

Use at least one of each. Note the model and OS version you used.

- A small phone (320 to 360 pt wide, for example an iPhone SE or a small
  Android).
- A large phone (about 430 pt wide).
- A tablet.
- A foldable, folded and unfolded (if you have one).

## On each device

Portrait first, then landscape.

1. Open a request and send it. The URL bar stays at the top while you scroll the
   response; the toolbar folds away as you scroll down and returns as you scroll
   up.
2. Tap the URL field. The keyboard opens, the URL and Send stay visible, and
   dragging the page dismisses the keyboard.
3. Try every request tab (Params, Headers, Auth, Body, Scripts, Assertions,
   Settings). None is clipped, and a tab that scrolls shows a fade at its edge.
4. Open Environments, History and Settings, and edit a value with the keyboard
   up.
5. Rotate the device while a response is showing. The request and response panes
   keep their content and the selected tab.
6. Open a GraphQL request and the collection runner. The Run button stays on
   screen.
7. Open the timing details (the time chip in the response). On a phone it is a
   bottom sheet you can swipe away.

## With larger text and a screen reader

- Set the system text size to the largest setting (iOS Dynamic Type's largest
  accessibility size, Android's largest font size). Repeat steps 1 to 4. Nothing
  overlaps, and anything too tall scrolls.
- Turn on VoiceOver (iOS) or TalkBack (Android). Send a request without looking:
  every control is announced with a name, the response status is read out, and
  the tab bars can be moved through.

## Platform checks

- iOS: swipe back from the left edge to leave a request; Send and Copy give a
  light tap; the content stays clear of the Dynamic Island and the home bar.
- Android: the back gesture previews the screen underneath (Android 14 and up);
  the system navigation bar is transparent; with Settings, "Use system colours"
  on, the colours follow the wallpaper (Android 12 and up).
- Landscape with a notch: nothing sits under the cutout.

## Result

Fill in one block per run.

```text
Date:
Build:
Devices (model, OS):
Problems found (step, device, what happened):
Result: pass / pass with notes / fail
```
