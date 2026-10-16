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

    test('more than 200 columns stay in the data and are counted', () {
      final t = tableFromJson([
        {for (var i = 0; i < 230; i++) 'c$i': i},
      ])!;
      expect(t.columnCount, 230);
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
      expect(cellText(4.0), '4.0');
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

  group('readTable', () {
    test('adds the candidate arrays and the matrix flag', () {
      final r = readTable(fixture('wrapped.json'), 'application/json');
      expect(r.table!.label, r'$.items');
      expect(r.sources.map((s) => s.path), [r'$', r'$.items', r'$.links']);
      expect(r.matrix, isFalse);
      final m = readTable(fixture('matrix.json'), 'application/json');
      expect(m.matrix, isTrue);
      expect(readTable('[]', 'application/json').table, isNull);
      expect(readTable('', 'application/json').table, isNull);
      expect(readTable('{bad', 'application/json').table, isNull);
    });

    test('a source that is not in the body is ignored', () {
      final r = readTable(
        fixture('wrapped.json'),
        'application/json',
        source: r'$.nope',
      );
      expect(r.table!.label, r'$.items');
    });

    test('XML and CSV go through the same call', () {
      expect(readTable(fixture('list.xml'), 'text/xml').table!.rowCount, 2);
      expect(readTable(fixture('pets.csv'), 'text/csv').table!.rowCount, 3);
    });

    test('looksTabular is a cheap guess from type and first character', () {
      expect(looksTabular('application/json', '  [1]'), isTrue);
      expect(looksTabular('application/json', '\n{"a":1}'), isTrue);
      expect(looksTabular('application/json', '"text"'), isFalse);
      expect(looksTabular('application/json', ''), isFalse);
      expect(looksTabular('text/csv', 'a,b'), isTrue);
      expect(looksTabular('application/xml', '<a/>'), isTrue);
      expect(looksTabular('text/html', '[1]'), isFalse);
    });

    test(
      'a large body is read in another isolate with the same result',
      () async {
        final big = jsonEncode([
          for (var i = 0; i < 12000; i++) {'id': i, 'name': 'row number $i'},
        ]);
        expect(big.length, greaterThan(tableIsolateThreshold));
        final viaIsolate = await readTableAsync(big, 'application/json');
        final direct = readTable(big, 'application/json');
        expect(viaIsolate.table!.rowCount, 12000);
        expect(viaIsolate.table!.columns.map((c) => c.name), ['id', 'name']);
        expect(viaIsolate.table!.rows.last, direct.table!.rows.last);
        // A small body does not need one.
        final small = await readTableAsync('[{"a":1}]', 'application/json');
        expect(small.table!.rowCount, 1);
      },
    );
  });

  group('speed-ups keep the results', () {
    test('sort on mixed kinds, dates and booleans', () {
      final t = tableFromJson([
        {'b': true, 'm': 3, 'd': '2026-01-02'},
        {'b': false, 'm': 'x', 'd': '2026-01-01'},
        {'b': true, 'm': 1, 'd': 'bad'},
        {'b': null, 'm': null, 'd': null},
      ])!;
      expect(t.sortOrder(0, ascending: true), [1, 0, 2, 3]);
      expect(t.sortOrder(0, ascending: false), [0, 2, 1, 3]);
      // Mixed numbers and text sort as text without errors, nulls last.
      expect(t.sortOrder(1, ascending: true).last, 3);
      expect(t.sortOrder(2, ascending: true).last, 3);
    });

    test('the row search index is reused and cells do not run together', () {
      final t = tableFromJson([
        {'a': 'ab', 'b': 'cd'},
        {'a': 'abc', 'b': 'd'},
      ])!;
      expect(t.matchingRows('bc'), [1]);
      expect(t.matchingRows('BC'), [1]);
      expect(t.matchingRows('abcd'), isEmpty);
      expect(t.matchingRows('cd'), [0]);
    });

    test('writers agree on awkward cells', () {
      final t = tableFromJson([
        {'a': 'x\ty', 'b': 'q"uote', 'c': 'line\r\nbreak'},
      ])!;
      expect(t.toTsv([0], [0, 1, 2]), 'x y\tq"uote\tline break');
      expect(
        t.toCsv([0], [0, 1, 2]),
        'a,b,c\r\nx\ty,"q""uote","line\r\nbreak"\r\n',
      );
    });
  });

  group('nothing in the body is left out', () {
    /// Every scalar string/number/bool in [v], as text, in any order.
    void leaves(Object? v, List<String> out) {
      if (v is Map) {
        v.forEach((k, x) {
          out.add('$k');
          leaves(x, out);
        });
      } else if (v is List) {
        for (final x in v) {
          leaves(x, out);
        }
      } else if (v != null) {
        out.add('$v');
      }
    }

    test('an array of objects keeps every key and value, typed', () {
      final rows = [
        {
          'id': 1,
          'price': 10.0,
          'name': 'Ünï \u{1F600}',
          'tags': ['a', 'b'],
          'o': null,
        },
        {
          'id': 2,
          'price': 2.50,
          'extra': {
            'deep': [
              1,
              2,
              {'x': true},
            ],
          },
        },
        {'id': 3, 'name': 'third', 'extra': 'text'},
      ];
      final t = tableFromJson(rows)!;
      final all = List<int>.generate(t.rowCount, (i) => i);
      final cols = List<int>.generate(t.columnCount, (i) => i);
      final back = jsonDecode(t.toJson(all, cols)) as List;
      for (var i = 0; i < rows.length; i++) {
        final out = back[i] as Map;
        rows[i].forEach((k, v) => expect(out[k], v, reason: 'row $i key $k'));
        // Keys the row did not have are null, nothing else.
        for (final e in out.entries) {
          if (!rows[i].containsKey(e.key)) expect(e.value, isNull);
        }
      }
    });

    test('a float keeps its decimal point', () {
      expect(cellText(10.0), '10.0');
      expect(cellText(2.5), '2.5');
      expect(cellText(10), '10');
      expect(cellText(1e21), '1e+21');
    });

    test('the whole body is a source: fields beside the rows are shown', () {
      final root = jsonDecode(fixture('wrapped.json'));
      final r = readTable(fixture('wrapped.json'), 'application/json');
      expect(r.sources.first.path, r'$');
      final t = readTable(
        fixture('wrapped.json'),
        'application/json',
        source: r'$',
      ).table!;
      expect(t.rows.map((r) => r[0]), ['page', 'total', 'items', 'links']);
      expect(t.rows[0][1], 1);
      // Everything in the body appears in some cell.
      final inBody = <String>[];
      leaves(root, inBody);
      final inCells = <String>[];
      for (final row in t.rows) {
        for (final c in row) {
          leaves(c, inCells);
        }
      }
      for (final x in inBody) {
        if (['page', 'total', 'items', 'links'].contains(x)) continue;
        expect(inCells, contains(x));
      }
    });

    test('more than 200 columns are all in the data; the grid shows 200', () {
      final t = tableFromJson([
        {for (var i = 0; i < 230; i++) 'c$i': i},
      ])!;
      expect(t.columnCount, 230);
      expect(t.columnsDropped, 30);
      expect(t.toCsv([0], [229]), 'c229\r\n229\r\n');
    });

    test('flatten never overwrites a column', () {
      final t = tableFromJson([
        {
          'a.b': 'literal',
          'a': {'b': 'flattened'},
        },
      ], flatten: true)!;
      final all = t.rows.single.map((v) => '$v').toList();
      expect(all, containsAll(['literal', 'flattened']));
      expect(t.columns.map((c) => c.name).toSet().length, 2);
    });

    test('XML keeps siblings, root attributes and mixed text', () {
      const xml =
          '<r v="1"><meta>m</meta><item id="1">t<sub>s</sub></item><item id="2"/></r>';
      final r = readTable(xml, 'application/xml');
      expect(r.sources.map((s) => s.path), ['/r/item', r'$']);
      final rows = r.table!;
      expect(rows.columns.map((c) => c.name), ['@id', 'sub', '#text']);
      expect(rows.rows[0], ['1', 's', 't']);
      final whole = readTable(xml, 'application/xml', source: r'$').table!;
      final cells = [for (final row in whole.rows) ...row.map(cellText)];
      expect(cells.join(' '), contains('m'));
      expect(whole.rows.map((r) => r[0]), containsAll(['@v', 'meta', 'item']));
    });

    test('CSV keeps every cell, including a short row and empty cells', () {
      final t = tableFromCsv('a,b,c\n1,,3\n4\n"x,y",z,')!;
      expect(t.rows, [
        ['1', '', '3'],
        ['4', null, null],
        ['x,y', 'z', ''],
      ]);
    });
  });
}
