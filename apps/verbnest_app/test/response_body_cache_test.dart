import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/widgets/response_body_cache.dart';
import 'package:verbnest_core/verbnest_core.dart' show BodyKind;
import 'package:verbnest_http/verbnest_http.dart';

HttpResponseRecord _json(String text) {
  const zero = Duration.zero;
  final body = Uint8List.fromList(utf8.encode(text));
  return HttpResponseRecord(
    status: 200,
    reason: 'OK',
    httpVersion: '1.1',
    headers: const [('content-type', 'application/json')],
    body: body,
    wireBodySize: body.length,
    timings: const Timings(
      dns: zero,
      connect: zero,
      tls: zero,
      ttfb: zero,
      download: zero,
      total: zero,
    ),
    finalUrl: Uri.parse('http://x/'),
    sent: SentRequest(
      head: 'GET / HTTP/1.1\r\n',
      body: Uint8List(0),
      url: Uri.parse('http://x/'),
    ),
  );
}

void main() {
  test('text is kept until the response or the toggle changes', () {
    final cache = ResponseBodyCache();
    final r = _json('{"a":1}');
    final pretty = cache.text(r, pretty: true);
    expect(pretty, contains('\n'));
    expect(identical(cache.text(r, pretty: true), pretty), isTrue);
    expect(cache.text(r, pretty: false), '{"a":1}');
  });

  test('a bad filter gives an empty result and its message', () {
    final cache = ResponseBodyCache();
    final r = _json('{"a":[1,2]}');
    expect(cache.filtered(r, BodyKind.json, r'$.a[0]'), '1');
    expect(cache.filterError, isNull);
    expect(cache.filtered(r, BodyKind.json, r'$.a['), '');
    expect(cache.filterError, isNotNull);
  });

  test('a small body is read as a table at once and the result is reused', () {
    final cache = ResponseBodyCache();
    final r = _json('[{"a":1},{"a":2}]');
    TableInfo read() => cache.table(
      r,
      r.bodyText,
      BodyKind.json,
      source: null,
      flatten: false,
      headerRow: false,
      tableOn: false,
      onReady: () => fail('a small body is not read later'),
    );
    final info = read();
    expect(info.table?.rowCount, 2);
    expect(info.canTable, isTrue);
    expect(identical(read(), info), isTrue);
  });

  test('text that is not a table has no table view', () {
    final cache = ResponseBodyCache();
    final r = _json('"just text"');
    final info = cache.table(
      r,
      r.bodyText,
      BodyKind.json,
      source: null,
      flatten: false,
      headerRow: false,
      tableOn: false,
      onReady: () {},
    );
    expect(info.canTable, isFalse);
  });
}
