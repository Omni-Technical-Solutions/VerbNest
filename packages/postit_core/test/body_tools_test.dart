import 'dart:convert';
import 'dart:typed_data';

import 'package:postit_core/postit_core.dart';
import 'package:test/test.dart';

void main() {
  group('bodyKindOf', () {
    test('reads the content type', () {
      expect(bodyKindOf('application/json; charset=utf-8'), BodyKind.json);
      expect(bodyKindOf('application/problem+json'), BodyKind.json);
      expect(bodyKindOf('text/xml'), BodyKind.xml);
      expect(bodyKindOf('application/atom+xml'), BodyKind.xml);
      expect(bodyKindOf('text/html'), BodyKind.other);
      expect(bodyKindOf(null), BodyKind.other);
    });
  });

  group('filterBody JSON', () {
    const body = '{"items":[{"id":1,"n":"a"},{"id":2,"n":"b"}],"total":2}';

    test('one match is shown on its own', () {
      expect(filterBody(body, BodyKind.json, r'$.total'), '2');
      expect(filterBody(body, BodyKind.json, r'$.items[0].n'), '"a"');
    });

    test('several matches become a list', () {
      final out = jsonDecode(filterBody(body, BodyKind.json, r'$.items[*].id'));
      expect(out, [1, 2]);
    });

    test('no match gives empty text', () {
      expect(filterBody(body, BodyKind.json, r'$.missing'), '');
    });

    test('bad body and bad path are FormatExceptions', () {
      expect(
        () => filterBody('nope', BodyKind.json, r'$.a'),
        throwsFormatException,
      );
      expect(
        () => filterBody(body, BodyKind.json, 'items'),
        throwsFormatException,
      );
    });
  });

  group('filterBody XML', () {
    const body =
        '<root><item id="1">a</item><item id="2">b</item><n>3</n></root>';

    test('selects elements, text and attributes', () {
      expect(filterBody(body, BodyKind.xml, '/root/n/text()'), '3');
      expect(filterBody(body, BodyKind.xml, '//item/text()').split('\n'), [
        'a',
        'b',
      ]);
      expect(filterBody(body, BodyKind.xml, '//item[@id="2"]/@id'), '2');
      expect(
        filterBody(body, BodyKind.xml, '/root/item[1]'),
        contains('id="1"'),
      );
    });

    test('bad body and bad path are FormatExceptions', () {
      expect(
        () => filterBody('<a>', BodyKind.xml, '/a'),
        throwsFormatException,
      );
      expect(
        () => filterBody(body, BodyKind.xml, '/root/['),
        throwsFormatException,
      );
    });
  });

  test('other bodies cannot be filtered', () {
    expect(() => filterBody('x', BodyKind.other, '/'), throwsFormatException);
  });

  group('hexDump', () {
    test('formats offset, hex and text columns', () {
      final dump = hexDump(Uint8List.fromList(utf8.encode('Hello, PostIt!\n')));
      expect(dump, startsWith('00000000  48 65 6c 6c 6f 2c 20 50'));
      expect(dump, contains('|Hello, PostIt!.|'));
    });

    test('pads a short last row and numbers rows in hex', () {
      final dump = hexDump(Uint8List(20)).trimRight().split('\n');
      expect(dump, hasLength(2));
      expect(dump[1], startsWith('00000010  00 00 00 00   '));
    });

    test('truncates large bodies with a note', () {
      final dump = hexDump(Uint8List(100), maxBytes: 32);
      expect(dump, contains('68 more bytes not shown'));
    });

    test('empty body is empty', () {
      expect(hexDump(Uint8List(0)), '');
    });
  });
}
