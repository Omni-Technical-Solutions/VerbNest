import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:verbnest_http/src/models.dart';
import 'package:verbnest_http/src/redirects.dart';

/// The redirect rules on their own: which request follows a response, and
/// which headers survive the hop (credentials never cross origins).
HttpResponseRecord response(int status, {String? location, Uri? from}) {
  const zero = Duration.zero;
  final url = from ?? Uri.parse('https://api.example.com/start');
  return HttpResponseRecord(
    status: status,
    reason: '',
    httpVersion: '1.1',
    headers: [if (location != null) ('Location', location)],
    body: Uint8List(0),
    wireBodySize: 0,
    timings: const Timings(
      dns: zero,
      connect: zero,
      tls: zero,
      ttfb: zero,
      download: zero,
      total: zero,
    ),
    finalUrl: url,
    sent: SentRequest(head: '', body: Uint8List(0), url: url),
  );
}

HttpRequestSpec request({
  String method = 'POST',
  List<Header> headers = const [],
  HttpSettings settings = const HttpSettings(),
}) => HttpRequestSpec(
  method: method,
  url: Uri.parse('https://api.example.com/start'),
  headers: headers,
  body: [1, 2, 3],
  settings: settings,
);

List<String> names(HttpRequestSpec? s) => [
  for (final h in s!.headers) h.$1.toLowerCase(),
];

void main() {
  test('a response that is not a redirect ends the chain', () {
    expect(nextHop(request(), response(200, location: '/x')), isNull);
    expect(nextHop(request(), response(302)), isNull, reason: 'no Location');
  });

  test('following can be switched off', () {
    final spec = request(settings: const HttpSettings(followRedirects: false));
    expect(nextHop(spec, response(302, location: '/x')), isNull);
  });

  test('301, 302 and 303 turn a POST into a GET without its body', () {
    for (final status in [301, 302, 303]) {
      final next = nextHop(request(), response(status, location: '/next'))!;
      expect(next.method, 'GET', reason: '$status');
      expect(next.body, isNull, reason: '$status');
      expect(next.url.toString(), 'https://api.example.com/next');
    }
  });

  test('307 and 308 keep the method and the body', () {
    for (final status in [307, 308]) {
      final next = nextHop(request(), response(status, location: '/next'))!;
      expect(next.method, 'POST');
      expect(next.body, [1, 2, 3]);
    }
  });

  test('HEAD stays HEAD on 301 and 302', () {
    final next = nextHop(
      request(method: 'HEAD'),
      response(302, location: '/next'),
    )!;
    expect(next.method, 'HEAD');
  });

  test('credentials never follow a redirect to another origin', () {
    final spec = request(
      method: 'GET',
      headers: [
        ('Authorization', 'Bearer t'),
        ('Proxy-Authorization', 'Basic x'),
        ('Cookie', 'a=b'),
        ('X-Api-Key', 'k'),
        ('Accept', 'application/json'),
      ],
    );
    final next = nextHop(spec, response(302, location: 'https://evil.test/'));
    expect(names(next), ['accept']);
  });

  test('a custom credential header also stays home, even if not stripping', () {
    // stripAuthCrossOrigin: false lets custom headers through, but the common
    // credential carriers still never cross origins.
    final spec = request(
      method: 'GET',
      headers: [
        ('Authorization', 'Bearer t'),
        ('Cookie', 'a=b'),
        ('X-Id', '1'),
      ],
      settings: const HttpSettings(stripAuthCrossOrigin: false),
    );
    final next = nextHop(spec, response(302, location: 'https://evil.test/'));
    expect(names(next), ['x-id']);
  });

  test('a change of scheme or port is another origin', () {
    final spec = request(
      method: 'GET',
      headers: [('Authorization', 'Bearer t')],
    );
    for (final target in [
      'http://api.example.com/',
      'https://api.example.com:8443/',
    ]) {
      expect(names(nextHop(spec, response(302, location: target))), isEmpty);
    }
  });

  test('the same origin keeps its headers, minus Host', () {
    final spec = request(
      method: 'GET',
      headers: [('Authorization', 'Bearer t'), ('Host', 'api.example.com')],
    );
    final next = nextHop(spec, response(302, location: '/other'));
    expect(names(next), ['authorization']);
  });
}
