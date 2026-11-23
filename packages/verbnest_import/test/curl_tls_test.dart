import 'package:test/test.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_import/verbnest_import.dart';

/// Certificate options in cURL commands (FR-HTTP-013e).
void main() {
  group('import', () {
    test('--cert, --key, --cert-type and --cacert become notes', () {
      final r = parseCurl(
        'curl --cert client.pem --key client.key --cert-type PEM '
        '--cacert ca.pem https://api.test/x',
      );
      expect(r.warnings, hasLength(2));
      expect(r.warnings[0], contains('client certificate client.pem'));
      expect(r.warnings[0], contains('key client.key'));
      expect(r.warnings[0], contains('Settings > Network'));
      expect(r.warnings[1], contains('CA ca.pem'));
    });

    test('a passphrase is never kept, in --cert or --pass', () {
      final a = parseCurl('curl --cert bundle.p12:s3cret https://api.test/');
      expect(a.warnings.join(), isNot(contains('s3cret')));
      expect(a.warnings.single, contains('bundle.p12'));
      expect(a.warnings.single, contains('passphrase was not imported'));
      final b = parseCurl('curl -E c.pem --pass hunter2 https://api.test/');
      expect(b.warnings.join(), isNot(contains('hunter2')));
      expect(b.warnings.single, contains('passphrase was not imported'));
    });

    test('a Windows path keeps its drive colon', () {
      final r = parseCurl(r"curl --cert 'C:\certs\c.pem' https://api.test/");
      expect(r.warnings.single, contains(r'C:\certs\c.pem'));
      expect(r.warnings.single, isNot(contains('passphrase')));
    });

    test('--key without --cert is noted; -k still turns verification off', () {
      final r = parseCurl('curl -k --key k.pem https://api.test/');
      expect(r.warnings.single, contains('need --cert'));
      expect(r.item.settings.verifyTls, isFalse);
    });

    test('no certificate options, no notes', () {
      expect(parseCurl('curl https://api.test/').warnings, isEmpty);
    });
  });

  group('export', () {
    const item = HttpRequestItem(id: 'r', name: 'r', url: 'https://api.test/x');

    test('cURL names placeholder files and never a key', () {
      final out = toCurl(item, clientCertificate: true, customCa: true);
      expect(out, contains('--cert client-cert.pem --key client-key.pem'));
      expect(out, contains('--cacert ca.pem'));
      final plain = toCurl(item);
      expect(plain, isNot(contains('--cert')));
      expect(plain, isNot(contains('--cacert')));
    });

    test('the other languages get a comment', () {
      for (final l in [
        CodeLanguage.javascriptFetch,
        CodeLanguage.pythonRequests,
        CodeLanguage.dartHttp,
      ]) {
        final out = generateCode(l, item, clientCertificate: true);
        expect(out, contains('a client certificate'), reason: '$l');
        expect(
          out.split('\n').first,
          startsWith(l == CodeLanguage.pythonRequests ? '#' : '//'),
        );
        expect(generateCode(l, item), isNot(contains('client certificate')));
      }
    });

    test('an exported command imports back with the same notes', () {
      final r = parseCurl(toCurl(item, clientCertificate: true));
      expect(r.warnings.single, contains('client-cert.pem'));
    });
  });
}
