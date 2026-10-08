import 'package:verbnest_core/verbnest_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2025, 1, 1, 12);
  Uri u(String s) => Uri.parse(s);

  group('hardening', () {
    test('public suffix, control characters and huge Max-Age', () {
      final jar = CookieJar();
      expect(
        jar.storeFromResponse(u('https://evil.co.uk/'), [
          'a=1; Domain=co.uk',
          'b=1\u0001x',
          'c=1; Max-Age=99999999999999',
        ], now: now),
        1,
      );
      expect(jar.matching(u('https://other.co.uk/'), now: now), isEmpty);
    });
  });

  group('storing', () {
    test('a host-only cookie goes back to that host only', () {
      final jar = CookieJar();
      jar.storeFromResponse(u('http://a.test/x'), ['id=1'], now: now);
      expect(jar.cookieHeader(u('http://a.test/y'), now: now), 'id=1');
      expect(jar.cookieHeader(u('http://sub.a.test/'), now: now), isNull);
      expect(jar.cookieHeader(u('http://b.test/'), now: now), isNull);
    });

    test(
      'Domain makes it visible to subdomains; foreign domains are refused',
      () {
        final jar = CookieJar();
        jar.storeFromResponse(u('https://api.a.test/'), [
          's=1; Domain=.a.test',
          'bad=1; Domain=other.test',
          'ip=1; Domain=test',
        ], now: now);
        expect(jar.cookies.map((c) => c.name), ['s']);
        expect(jar.cookieHeader(u('https://www.a.test/'), now: now), 's=1');
        expect(jar.cookieHeader(u('https://a.test/'), now: now), 's=1');
      },
    );

    test('path scoping and default path', () {
      final jar = CookieJar();
      jar.storeFromResponse(u('http://a.test/app/page'), [
        'd=1',
        'p=2; Path=/api',
      ], now: now);
      expect(jar.cookies.firstWhere((c) => c.name == 'd').path, '/app');
      expect(jar.cookieHeader(u('http://a.test/app/x'), now: now), 'd=1');
      expect(jar.cookieHeader(u('http://a.test/apple'), now: now), isNull);
      expect(jar.cookieHeader(u('http://a.test/api/v1'), now: now), 'p=2');
    });

    test('longer paths are listed first', () {
      final jar = CookieJar();
      jar.storeFromResponse(u('http://a.test/'), ['a=1; Path=/'], now: now);
      jar.storeFromResponse(u('http://a.test/'), ['b=2; Path=/x/y'], now: now);
      expect(jar.cookieHeader(u('http://a.test/x/y/z'), now: now), 'b=2; a=1');
    });

    test('Secure cookies need https, except on loopback', () {
      final jar = CookieJar();
      jar.storeFromResponse(u('http://a.test/'), ['s=1; Secure'], now: now);
      expect(jar.isEmpty, isTrue);
      jar.storeFromResponse(u('https://a.test/'), ['s=1; Secure'], now: now);
      expect(jar.cookieHeader(u('http://a.test/'), now: now), isNull);
      expect(jar.cookieHeader(u('https://a.test/'), now: now), 's=1');
      jar.storeFromResponse(u('http://127.0.0.1:8080/'), [
        'l=1; Secure',
      ], now: now);
      expect(jar.cookieHeader(u('http://127.0.0.1:8080/'), now: now), 'l=1');
    });

    test('a new value replaces the old and keeps the creation time', () {
      final jar = CookieJar();
      jar.storeFromResponse(u('http://a.test/'), ['k=1'], now: now);
      jar.storeFromResponse(u('http://a.test/'), [
        'k=2',
      ], now: now.add(const Duration(minutes: 1)));
      expect(jar.cookies.single.value, '2');
      expect(jar.cookies.single.createdAt, now);
    });
  });

  group('expiry', () {
    test('Max-Age wins over Expires and zero deletes', () {
      final jar = CookieJar();
      jar.storeFromResponse(u('http://a.test/'), [
        'k=1; Max-Age=60; Expires=Wed, 01 Jan 2020 00:00:00 GMT',
      ], now: now);
      expect(jar.cookieHeader(u('http://a.test/'), now: now), 'k=1');
      expect(
        jar.cookieHeader(
          u('http://a.test/'),
          now: now.add(const Duration(seconds: 61)),
        ),
        isNull,
      );
      jar.storeFromResponse(u('http://a.test/'), ['k=1; Max-Age=0'], now: now);
      expect(jar.isEmpty, isTrue);
    });

    test('a past Expires deletes an existing cookie', () {
      final jar = CookieJar();
      jar.storeFromResponse(u('http://a.test/'), ['k=1'], now: now);
      jar.storeFromResponse(u('http://a.test/'), [
        'k=; Expires=Thu, 01 Jan 1970 00:00:00 GMT',
      ], now: now);
      expect(jar.isEmpty, isTrue);
    });

    test('date formats', () {
      final want = DateTime.utc(2015, 10, 21, 7, 28);
      expect(parseCookieDate('Wed, 21 Oct 2015 07:28:00 GMT'), want);
      expect(parseCookieDate('Wednesday, 21-Oct-15 07:28:00 GMT'), want);
      expect(parseCookieDate('Wed Oct 21 07:28:00 2015'), want);
      expect(parseCookieDate('nonsense'), isNull);
    });
  });

  test('JSON round trip and change notifications', () {
    final jar = CookieJar();
    var changes = 0;
    jar.onChanged = () => changes++;
    jar.storeFromResponse(u('https://a.test/'), [
      'k=1; Path=/p; Secure; HttpOnly; SameSite=Lax; Max-Age=100',
    ], now: now);
    expect(changes, 1);
    final back = CookieJar.fromJson(jar.toJson());
    final c = back.cookies.single;
    expect(
      (c.name, c.path, c.secure, c.httpOnly, c.sameSite, c.expires != null),
      ('k', '/p', true, true, 'Lax', true),
    );
    jar.remove(jar.cookies.single);
    expect(changes, 2);
    jar.clear();
    expect(changes, 2, reason: 'nothing to clear');
  });
}
