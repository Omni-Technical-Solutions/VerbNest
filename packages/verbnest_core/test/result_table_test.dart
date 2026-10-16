import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:verbnest_core/verbnest_core.dart';

String fixture(String name) =>
    File('test/fixtures/tables/$name').readAsStringSync();

void main() {
  group('JSON', () {
    test('an array of objects: a column per key, ragged rows padded', () {
      final t = tableFromJson(jsonDecode(fixture('pets.json')))!;
      expect(t.columns.map((c) => c.name), [
        'id',
        'name',
        'species',
        'age',
        'vaccinated',
        'owner',
      ]);
      expect(t.rowCount, 3);
      expect(t.rows[1][3], 2.5);
      expect(t.rows[0][5], isNull);
      expect(t.columns.map((c) => c.type), [
        ColumnType.number,
        ColumnType.text,
        ColumnType.text,
        ColumnType.number,
        ColumnType.boolean,
        ColumnType.text,
      ]);
    });

    test('keys that first appear later still get a column, in order', () {
      final t = tableFromJson([
        {'a': 1},
        {'b': 2, 'a': 3},
        {'c': 4},
      ])!;
      expect(t.columns.map((c) => c.name), ['a', 'b', 'c']);
      expect(t.rows, [
        [1, null, null],
        [3, 2, null],
        [null, null, 4],
      ]);
    });

    test('an object holding arrays uses the largest array of records', () {
      final root = jsonDecode(fixture('wrapped.json'));
      final sources = findTableSources(root);
      expect(sources.map((s) => s.path), [r'$.items', r'$.links']);
      final t = tableFromJson(root)!;
      expect(t.label, r'$.items');
      expect(t.rowCount, 2);
      expect(t.columns.map((c) => c.name), ['id', 'address', 'tags']);
      expect(t.columns[1].type, ColumnType.json);
    });

    test('a source path picks another array', () {
      final t = tableFromJson(
        jsonDecode(fixture('wrapped.json')),
        source: r'$.links',
      )!;
      expect(t.columns.map((c) => c.name), ['rel']);
    });

    test('flatten turns nested objects into dotted columns', () {
      final t = tableFromJson(
        jsonDecode(fixture('wrapped.json')),
        flatten: true,
      )!;
      expect(t.columns.map((c) => c.name), [
        'id',
        'address.city',
        'address.zip',
        'tags',
      ]);
      expect(t.rows[1][2], isNull);
      expect(t.rows[0][1], 'Perth');
    });

    test('flatten stops at three levels', () {
      final t = tableFromJson([
        {
          'a': {
            'b': {
              'c': {'d': 1},
            },
          },
        },
      ], flatten: true)!;
      expect(t.columns.map((c) => c.name), ['a.b.c']);
      expect(t.rows.single.single, {'d': 1});
    });

    test('array of arrays: numbered columns, or the first row as header', () {
      final root = jsonDecode(fixture('matrix.json'));
      expect(tableFromJson(root)!.columns.map((c) => c.name), ['1', '2']);
      final t = tableFromJson(root, firstRowHeader: true)!;
      expect(t.columns.map((c) => c.name), ['id', 'name']);
      expect(t.rowCount, 2);
    });

    test('a single object is a Key / Value table', () {
      final t = tableFromJson(jsonDecode(fixture('single.json')))!;
      expect(t.columns.map((c) => c.name), ['Key', 'Value']);
      expect(t.rows.map((r) => r.first), ['status', 'count', 'nested']);
    });

    test('an array of primitives is one Value column', () {
      final t = tableFromJson([1, 2, 3])!;
      expect(t.columns.single.name, 'Value');
      expect(t.columns.single.type, ColumnType.number);
    });

    test('empty and scalar bodies are not tables', () {
      expect(tableFromJson(<Object?>[]), isNull);
      expect(tableFromJson(null), isNull);
      expect(tableFromJson('just text'), isNull);
      expect(tableFromJson(42), isNull);
      expect(
        tableFromJson(jsonDecode('{"items":[]}'), source: r'$.nope'),
        isNull,
      );
    });

    test('more than 200 columns are cut and counted', () {
      final t = tableFromJson([
        {for (var i = 0; i < 230; i++) 'c$i': i},
      ])!;
      expect(t.columnCount, ResultTable.maxColumns);
      expect(t.columnsDropped, 30);
    });

    test('odd key names make a bracket source path', () {
      final s = findTableSources({
        'my key': [
          {'a': 1},
        ],
      });
      expect(s.single.path, "\$['my key']");
      final t = tableFromJson({
        'my key': [
          {'a': 1},
        ],
      }, source: s.single.path)!;
      expect(t.rowCount, 1);
    });
  });

  group('types', () {
    test('dates are detected and sort as dates', () {
      final t = tableFromJson([
        {'d': '2026-10-02T10:00:00Z'},
        {'d': '2026-09-30'},
        {'d': '2026-10-01 08:00'},
      ])!;
      expect(t.columns.single.type, ColumnType.date);
      expect(t.sortOrder(0, ascending: true), [1, 2, 0]);
    });

    test('an all-null column is empty', () {
      final t = tableFromJson([
        {'a': null},
        {'a': null},
      ])!;
      expect(t.columns.single.type, ColumnType.empty);
    });

    test('mixed numbers and text fall back to text', () {
      final t = tableFromJson([
        {'a': 1},
        {'a': 'x'},
      ])!;
      expect(t.columns.single.type, ColumnType.text);
    });
  });

  group('sort and filter', () {
    final t = tableFromJson([
      {'n': 10, 's': 'banana'},
      {'n': 9, 's': 'Apple'},
      {'n': null, 's': 'cherry'},
      {'n': 100, 's': null},
      {'n': 9, 's': 'apple2'},
    ])!;

    test('numbers sort as numbers, nulls last both ways, ties keep order', () {
      expect(t.sortOrder(0, ascending: true), [1, 4, 0, 3, 2]);
      expect(t.sortOrder(0, ascending: false), [3, 0, 1, 4, 2]);
    });

    test('text sorts without regard to case', () {
      expect(t.sortOrder(1, ascending: true), [1, 4, 0, 2, 3]);
    });

    test('filter matches any cell, case-insensitively', () {
      expect(t.matchingRows('APPLE'), [1, 4]);
      expect(t.matchingRows('100'), [3]);
      expect(t.matchingRows('  '), [0, 1, 2, 3, 4]);
      expect(t.matchingRows('zzz'), isEmpty);
    });
  });

  group('XML', () {
    test('repeated elements are rows; attributes and children are columns', () {
      final t = tableFromXml(fixture('list.xml'))!;
      expect(t.columns.map((c) => c.name), ['@id', 'name', 'species']);
      expect(t.rows, [
        ['1', 'Rex', 'dog'],
        ['2', 'Tom', null],
      ]);
      expect(t.label, '/pets/pet');
    });

    test('no repeats: Key / Value of the root children', () {
      final t = tableFromXml('<r><a>1</a><b>2</b></r>')!;
      expect(t.rows, [
        ['a', '1'],
        ['b', '2'],
      ]);
    });

    test('bad XML is not a table', () {
      expect(tableFromXml('<a><b></a>'), isNull);
      expect(tableFromXml('<a/>'), isNull);
    });
  });

  group('CSV', () {
    test('quotes, commas, line breaks inside quotes and short rows', () {
      final t = tableFromCsv(fixture('pets.csv'))!;
      expect(t.columns.map((c) => c.name), ['id', 'name', 'note']);
      expect(t.rows, [
        ['1', 'Rex', 'likes, commas'],
        ['2', 'Tom', 'line one\nline two'],
        ['3', 'Ziggy', null],
      ]);
    });

    test('doubled quotes, BOM, CRLF and a missing final newline', () {
      final rows = parseCsvRows('﻿a,b\r\n"say ""hi""",2');
      expect(rows, [
        ['a', 'b'],
        ['say "hi"', '2'],
      ]);
    });

    test('TSV and no header', () {
      final t = tableFromCsv(fixture('pets.tsv'), delimiter: '\t')!;
      expect(t.columns.map((c) => c.name), ['id', 'name']);
      final n = tableFromCsv('1,2\n3,4', header: false)!;
      expect(n.columns.map((c) => c.name), ['1', '2']);
      expect(n.rowCount, 2);
    });

    test('empty text is not a table', () {
      expect(tableFromCsv(''), isNull);
    });
  });

  group('tableFromBody', () {
    test('picks the reader from the content type', () {
      expect(
        tableFromBody(fixture('pets.json'), 'application/json')!.rowCount,
        3,
      );
      expect(tableFromBody(fixture('list.xml'), 'text/xml')!.rowCount, 2);
      expect(
        tableFromBody(fixture('pets.csv'), 'text/csv; charset=utf-8')!.rowCount,
        3,
      );
      expect(
        tableFromBody(
          fixture('pets.tsv'),
          'text/tab-separated-values',
        )!.rowCount,
        2,
      );
      expect(tableFromBody('plain', 'text/plain'), isNull);
      expect(tableFromBody('{bad', 'application/json'), isNull);
      expect(
        tableFromBody('[1]', 'application/json', source: r'$[?(@.a)]'),
        isNull,
      );
    });
  });

  group('copy and export', () {
    final t = tableFromJson(jsonDecode(fixture('pets.json')))!;

    test('TSV keeps one line per row and drops tabs and breaks', () {
      final tsv = t.toTsv([0, 2], [1, 3], header: true);
      expect(tsv, 'name\tage\nRex\t4\nZiggy, the "great"\t');
      final multi = tableFromCsv(fixture('pets.csv'))!;
      expect(multi.toTsv([1], [2]), 'line one line two');
    });

    test('CSV quotes what needs it and ends with CRLF', () {
      final csv = t.toCsv([2], [0, 1]);
      expect(csv, 'id,name\r\n3,"Ziggy, the ""great"""\r\n');
      expect(parseCsvRows(csv), [
        ['id', 'name'],
        ['3', 'Ziggy, the "great"'],
      ]);
    });

    test('JSON keeps types', () {
      final out = jsonDecode(t.toJson([1], [0, 3, 4, 5])) as List;
      expect(out.single, {
        'id': 2,
        'age': 2.5,
        'vaccinated': false,
        'owner': 'Ann',
      });
    });

    test('Markdown escapes pipes and line breaks', () {
      final m = tableFromJson([
        {'a': 'x|y', 'b': 'l1\nl2'},
      ])!;
      expect(
        m.toMarkdown([0], [0, 1]),
        '| a | b |\n| --- | --- |\n| x\\|y | l1 l2 |',
      );
    });
  });

  group('cell text', () {
    test('plain, preview and full forms', () {
      expect(cellText(null), '');
      expect(cellText(4.0), '4');
      expect(cellText(2.5), '2.5');
      expect(cellText(true), 'true');
      expect(cellText({'a': 1}), '{"a":1}');
      expect(cellPreview(null), 'null');
      expect(cellPreview({'a': 1, 'b': 2}), '{2 keys} {"a":1,"b":2}');
      expect(cellPreview([1]), '[1 item] [1]');
      expect(cellFull({'a': 1}), '{\n  "a": 1\n}');
    });
  });

  test('100,000 rows build, sort and filter quickly', () {
    final rows = [
      for (var i = 0; i < 100000; i++) {'id': i, 'name': 'row ${i % 977}'},
    ];
    final sw = Stopwatch()..start();
    final t = tableFromJson(rows)!;
    t.sortOrder(1, ascending: false);
    t.matchingRows('row 97');
    sw.stop();
    expect(t.rowCount, 100000);
    expect(sw.elapsedMilliseconds, lessThan(5000));
  });
}
