# Key/value editor: typing stops after the first letter, suggestions missing

Status 2026-11-01: steps 1 to 3 done in 0.65.3 (a GlobalKey on the field plus a stable Column shape; common header names for an empty key; Add moved to the top, new row focused). The test fails on the old code (field state replaced) and passes now. Not checked on a physical phone keyboard; step 4 is the release.

## What was reported

1. When a header is added, the suggestions and the "add" affordances do not appear.
2. On a phone, once the first letter of the key is typed no more letters can be added.

## Review

The editor is `KeyValueEditor` (`widgets/kv_editor.dart`), used by headers, params and form bodies. Each key and value is a `SyncedTextField` (`widgets/synced_field.dart`).

### Cause of 2: the text field is rebuilt when suggestions appear

`_SyncedTextFieldState.build` returns the bare `TextField` when there is nothing to show under it, and `Column([field, info])` when there is. The first letter makes header-name chips appear (`matchSuggestions` returns nothing for empty text), so the tree changes from `TextField` to `Column > TextField` at that moment. Flutter cannot move a widget from the root of a subtree into a `Column`, so the `TextField` and its `EditableText` are disposed and a new one is built. The `FocusNode` is shared, so the new field keeps focus on a computer. On a phone the old field closes its keyboard connection (the IME session) and the new one has to open it again; the keyboard drops or ignores the following key presses, so no more letters can be added.

Reproduced: a widget test (360 dp wide, header suggestions on) enters "C" in a new key field; the chips appear and the `EditableTextState` is a different object afterwards. The same happens when the chips go away (the exact header name is typed, or the field loses focus), and for the value field when `content-type` suggestions come and go, for `{{` variable completion, and in the GraphQL and script editors that use the same widget.

### Cause of 1 (two readings; the plan covers both)

- Suggestions only show once a letter is typed. A new, empty key shows nothing, so the field looks like it has no completion. `matchSuggestions` returns an empty list for empty text on purpose, but for a header key an empty field is exactly when a list of common names helps. After fix 2 this is the one the person sees first.
- The "add" button is the last item in a `ListView` that sits under the "generated headers" panel. With the keyboard open on a small phone it can be scrolled out of view, and with the first row in the stacked layout (under 360 dp) the value field and the chips push it further down. It needs to stay reachable.

I could not tell from the report which of these is meant, or whether it is something else (for example the file/text switch icon, which is shown only for form bodies). Please confirm; the plan does the first two anyway because they are real.

## Plan

### Step 1: keep the text field when suggestions come and go (fixes 2)

- `SyncedTextField.build` always returns the same shape: a `Column` with the field first and the info line as an optional second child, so Flutter keeps the `TextField` state. The field gets a `GlobalKey` owned by the state as well, so a parent change cannot rebuild it either. With `expands`, the field stays inside `Expanded` in both cases.
- `mainAxisSize.min` stays so a row is as tall as its content; no height jump other than the chip line itself.
- Tests (`synced_field_test.dart`): the `EditableTextState` is the same object before and after chips appear and disappear; text entered letter by letter in a key field gives the whole word (360 dp and 800 dp); focus stays on the field; the same for value, `{{` completion, script and GraphQL (`completer`) modes.
- Check on a device or emulator: type a whole header name on an Android phone and on an iPhone simulator with the software keyboard.

### Step 2: suggestions for a new, empty header (fixes 1, first reading)

- For a field with fixed `suggestions` (header names) and focus, an empty text shows the most common names (the first eight of the list, which is ordered by use). `matchSuggestions` keeps returning nothing for empty text (other callers rely on it); the empty case is handled in `_info` next to `matchSuggestionsOrAll`.
- Value suggestions (for `content-type`) show for an empty value in the same way.
- Tests: focusing an empty key shows eight chips; typing narrows them; choosing one fills the key and keeps focus; no chips for fields without suggestions.

### Step 3: the add button stays reachable (fixes 1, second reading)

- Put the "Add" button above the rows' end in a pinned bar, or keep it at the end but make the list scroll the new row into view and leave room for the keyboard (`scrollPadding` and `ensureVisible` on the new row's key field).
- When "Add" is tapped the new row's key field gets focus so the person can type at once, and the list scrolls to it.
- Tests: tapping Add on a 360 x 640 screen with the keyboard inset focuses the new key field, and the Add button is on screen (`tester.getRect` inside the viewport).

### Step 4: release

- `fix` bump to 0.65.3, changelog, notarised DMG before pushing (standing rule), iOS and Android builds.

## Risks

- `SyncedTextField` is used in many places (URL bar, scripts, GraphQL, environment variables). The change is to the shape of one build method, so the test above runs against each mode. The URL bar already worked; it must not regress.
- Whether the keyboard really drops can only be shown on a device. The state test proves the field is rebuilt; the device check proves the symptom is gone. If it persists after Step 1, the next suspect is `didUpdateWidget` replacing the controller value on every parent rebuild (it sets the selection to the end of the text), which also moves the caret when text is typed in the middle.

## Follow-up 2026-11-01 (0.65.4): the keyboard kept disappearing

0.65.3 fixed the field being rebuilt by its own suggestions, but on a phone the keyboard still closed when a header field was tapped. Second cause: `ScrollIfShort` (`widgets/ui/scroll_if_short.dart`) wraps each request tab. It returned the child directly when the tab had at least 420 dp (headers) and a `SingleChildScrollView` around it when it had less. Tapping a field opens the keyboard, which takes room from the tab, so the tab switched shape, Flutter rebuilt the whole form, the focused field was lost and the keyboard closed; the room came back and it flipped again. Fix: one shape, always a scroll view whose child is at least as tall as the tab and at least `needed` tall, so only the height changes. Test: `scroll_if_short_test.dart` (the form's text field keeps its state and focus while the room changes; it fails on the old code).
