import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/js_syntax.dart';

void main() {
  test('tokens: keywords, strings, numbers, comments, pm', () {
    const src = "const a = pm.test('x', 42); // done";
    final kinds = [for (final t in tokenizeJs(src)) t.kind];
    expect(kinds, [
      JsTokenKind.keyword,
      JsTokenKind.api,
      JsTokenKind.string,
      JsTokenKind.number,
      JsTokenKind.comment,
    ]);
    final str = tokenizeJs(src).firstWhere((t) => t.kind == JsTokenKind.string);
    expect(src.substring(str.start, str.end), "'x'");
  });

  test('unterminated string and block comment end at the text end', () {
    expect(tokenizeJs("'abc").single.end, 4);
    expect(tokenizeJs('/* open').single.kind, JsTokenKind.comment);
  });

  test('member names after a dot are not keywords', () {
    expect(tokenizeJs('obj.default'), isEmpty);
  });

  test('completion finds pm members and replaces the typed prefix', () {
    expect(scriptPrefix('x = pm.resp', 11), 'pm.resp');
    final hits = scriptCompletions('pm.response.j');
    expect(hits, ['pm.response.json']);
    final r = applyScriptCompletion('x = pm.resp', 11, 'pm.response.json');
    expect(r.text, 'x = pm.response.json');
    expect(r.caret, r.text.length);
    expect(scriptCompletions('p'), isEmpty);
  });

  test('escapes, line breaks and template literals', () {
    // An escaped quote does not end the string.
    expect(tokenizeJs(r"'a\'b' x").single.end, 6);
    // A plain string stops at the line break, a template literal does not.
    expect(tokenizeJs("'ab\ncd'").first.end, 3);
    expect(tokenizeJs('`ab\ncd`').single.end, 7);
    // Numbers take their suffix and decimals.
    expect(tokenizeJs('1.5e3n').single.end, 6);
    // A line comment stops before the line break.
    final t = tokenizeJs('// a\nlet');
    expect(
      [for (final x in t) x.kind],
      [JsTokenKind.comment, JsTokenKind.keyword],
    );
    expect(t.first.end, 4);
  });
}
