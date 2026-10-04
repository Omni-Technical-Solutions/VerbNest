import 'dart:convert';

import 'package:postit_core/postit_core.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

RunReport sample() => RunReport(
  name: 'Pets <v1> & "co"',
  startedAt: DateTime.utc(2026, 1, 1, 10),
  finishedAt: DateTime.utc(2026, 1, 1, 10, 0, 2),
  environment: 'dev',
  iterations: 2,
  entries: const [
    RunEntry(
      iteration: 1,
      requestId: 'a',
      name: 'List',
      method: 'GET',
      url: 'http://x.test/pets',
      status: 200,
      reason: 'OK',
      timeMs: 120,
      tests: [
        TestResult(name: 'status ok', status: 'pass'),
        TestResult(name: 'has <id>', status: 'fail', message: 'Got "x" & y'),
        TestResult(name: 'later', status: 'skip'),
      ],
    ),
    RunEntry(
      iteration: 1,
      requestId: 'b',
      name: 'Create',
      method: 'POST',
      url: 'http://x.test/pets',
      error: 'Connection refused',
    ),
    RunEntry(
      iteration: 2,
      requestId: 'a',
      name: 'List',
      method: 'GET',
      url: 'http://x.test/pets',
      status: 200,
      reason: 'OK',
      timeMs: 80,
    ),
    RunEntry(
      iteration: 2,
      requestId: 'c',
      name: 'Skipped one',
      method: 'GET',
      url: '',
      skipped: true,
    ),
  ],
);

void main() {
  group('data files', () {
    test('CSV with quotes, commas, newlines and short rows', () {
      final rows = parseDataFile(
        'name,note,n\r\n"Rex, Jr","say ""hi""\nthere",1\nAda,,\nShort\n\n',
        fileName: 'pets.csv',
      );
      expect(rows, [
        {'name': 'Rex, Jr', 'note': 'say "hi"\nthere', 'n': '1'},
        {'name': 'Ada', 'note': '', 'n': ''},
        {'name': 'Short', 'note': '', 'n': ''},
      ]);
    });

    test('CSV with a BOM and an unclosed quote', () {
      expect(parseDataFile('\uFEFFa,b\n1,2'), [
        {'a': '1', 'b': '2'},
      ]);
      expect(() => parseDataFile('a\n"x'), throwsFormatException);
      expect(() => parseDataFile('a,\n1,2'), throwsFormatException);
      expect(parseDataFile(''), isEmpty);
    });

    test('JSON arrays of objects turn values into text', () {
      final rows = parseDataFile(
        '[{"id":1,"ok":true,"n":null,"o":{"a":1},"s":"x"}]',
        fileName: 'd.json',
      );
      expect(rows.single, {
        'id': '1',
        'ok': 'true',
        'n': '',
        'o': '{"a":1}',
        's': 'x',
      });
    });

    test('JSON must be an array of objects', () {
      expect(
        () => parseDataFile('{"a":1}', fileName: 'x.json'),
        throwsFormatException,
      );
      expect(
        () => parseDataFile('[1]', fileName: 'x.json'),
        throwsFormatException,
      );
      expect(
        () => parseDataFile('[', fileName: 'x.json'),
        throwsFormatException,
      );
    });
  });

  group('run report', () {
    test('totals', () {
      final r = sample();
      expect(r.requests, 3);
      expect(r.skipped, 1);
      expect(r.passedTests, 1);
      expect(r.failedTests, 1);
      expect(r.errors, 1);
      expect(r.ok, isFalse);
    });

    test('JSON round trip', () {
      final back = RunReport.fromJson(
        jsonDecode(sample().toJsonText()) as Map<String, Object?>,
      );
      expect(back.entries, hasLength(4));
      expect(back.entries[1].error, 'Connection refused');
      expect(back.entries[3].skipped, isTrue);
      expect(back.environment, 'dev');
      expect(back.duration, const Duration(seconds: 2));
    });

    test('JUnit is well-formed XML with correct counts and escaping', () {
      final doc = XmlDocument.parse(sample().toJUnit());
      final root = doc.rootElement;
      expect(root.name.local, 'testsuites');
      expect(root.getAttribute('name'), r'Pets <v1> & "co"');
      expect(root.getAttribute('tests'), '6');
      expect(root.getAttribute('failures'), '1');
      expect(root.getAttribute('errors'), '1');
      expect(root.getAttribute('skipped'), '2');
      final suites = root.findElements('testsuite').toList();
      expect(suites, hasLength(2));
      final cases = suites.first.findElements('testcase').toList();
      expect(cases, hasLength(4));
      final failure = cases[1].findElements('failure').single;
      expect(failure.getAttribute('message'), 'Got "x" & y');
      expect(cases[2].findElements('skipped'), isNotEmpty);
      expect(
        cases[3].findElements('error').single.getAttribute('message'),
        'Connection refused',
      );
      for (final s in suites) {
        final n = s.findElements('testcase').length;
        expect(s.getAttribute('tests'), '$n');
      }
    });

    test('control characters never break the XML', () {
      final r = RunReport(
        name: 'n',
        startedAt: DateTime.utc(2026),
        finishedAt: DateTime.utc(2026),
        iterations: 1,
        entries: const [
          RunEntry(
            iteration: 1,
            requestId: 'a',
            name: 'bad\u0001name',
            method: 'GET',
            url: '',
            error: 'x\u0000y',
          ),
        ],
      );
      expect(() => XmlDocument.parse(r.toJUnit()), returnsNormally);
    });

    test('HTML escapes content and shows the summary', () {
      final html = sample().toHtml();
      expect(html, contains('Pets &lt;v1&gt; &amp; &quot;co&quot;'));
      expect(html, contains('has &lt;id&gt;'));
      expect(html, isNot(contains('<id>')));
      expect(html, contains('1 failed'));
      expect(html, contains('</body></html>'));
    });
  });
}
