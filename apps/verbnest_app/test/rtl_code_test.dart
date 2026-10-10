import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/widgets/code_view.dart';

void main() {
  testWidgets('code stays left to right in a right-to-left app', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: CodeView(text: '{"a": 1}', json: true)),
        ),
      ),
    );
    final ctx = t.element(find.byType(LayoutBuilder).first);
    expect(Directionality.of(ctx), TextDirection.ltr);
  });
}
