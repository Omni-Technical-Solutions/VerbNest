import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/state/var_text.dart';
import 'package:verbnest_app/src/widgets/kv_editor.dart';
import 'package:verbnest_app/src/widgets/synced_field.dart';
import 'package:verbnest_core/verbnest_core.dart';

/// Typing a header: the text field must survive the suggestions appearing
/// and going away. On a phone a rebuilt field closes the keyboard connection
/// and no more letters can be typed.
Future<void> _pump(
  WidgetTester t,
  List<KeyValue> Function() rows,
  void Function(List<KeyValue>) set, {
  double width = 360,
  double height = 640,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late StateSetter update;
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (c, s) {
            update = s;
            return KeyValueEditor(
              idPrefix: 'h',
              rows: rows(),
              keySuggestions: headerNames,
              valueSuggestions: const {'content-type': contentTypes},
              onChanged: (r) => update(() => set(r)),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  for (final width in [320.0, 360.0, 800.0]) {
    testWidgets('the key field is not rebuilt while typing ($width dp)', (
      t,
    ) async {
      var rows = [const KeyValue(key: '')];
      await _pump(t, () => rows, (r) => rows = r, width: width);
      final field = find.byKey(const ValueKey('h-key-0'));
      final inner = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      // Taken before focus: the suggestions appear with focus and with the
      // first letter, and that must not rebuild the field.
      final before = t.state<EditableTextState>(inner);
      await t.tap(inner);
      await t.pump();
      expect(identical(t.state<EditableTextState>(inner), before), isTrue);
      var typed = '';
      for (final ch in 'Content-Type'.split('')) {
        typed += ch;
        await t.enterText(inner, typed);
        await t.pump();
        // The chips come and go as the text changes; the field stays.
        expect(identical(t.state<EditableTextState>(inner), before), isTrue);
      }
      expect(rows.single.key, 'Content-Type');
    });
  }

  testWidgets('a new empty key offers the common header names', (t) async {
    var rows = [const KeyValue(key: '')];
    await _pump(t, () => rows, (r) => rows = r);
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('h-key-0')),
        matching: find.byType(EditableText),
      ),
    );
    await t.pump();
    expect(find.byKey(const ValueKey('suggest-Content-Type')), findsOneWidget);
    expect(find.byKey(const ValueKey('suggest-Authorization')), findsOneWidget);
    // Narrowing, then choosing one fills the key.
    await t.tap(find.byKey(const ValueKey('suggest-Authorization')));
    await t.pump();
    expect(rows.single.key, 'Authorization');
  });

  testWidgets('a field without suggestions shows no chips when empty', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncedTextField(value: '', onChanged: (_) {}, hint: 'x'),
        ),
      ),
    );
    await t.tap(find.byType(EditableText));
    await t.pump();
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('Add focuses the new key and stays on screen', (t) async {
    var rows = [
      for (var i = 0; i < 12; i++) KeyValue(key: 'k$i', value: 'v$i'),
    ];
    await _pump(t, () => rows, (r) => rows = r, height: 400);
    // With the keyboard up (less height) Add is still on screen.
    t.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(t.view.resetViewInsets);
    await t.pump();
    final add = find.byKey(const Key('h-add'));
    expect(add, findsOneWidget);
    expect(t.getRect(add).top, greaterThanOrEqualTo(0));
    await t.tap(add);
    await t.pumpAndSettle();
    expect(rows.length, 13);
    final last = find.descendant(
      of: find.byKey(const ValueKey('h-key-12')),
      matching: find.byType(EditableText),
    );
    expect(last, findsOneWidget);
    expect(t.state<EditableTextState>(last).widget.focusNode.hasFocus, isTrue);
  });
}
