import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:verbnest_runner/verbnest_runner.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

NetworkConfig _config() => NetworkConfig(
  proxyEnabled: true,
  proxyHost: 'proxy.test',
  proxyPort: 3128,
  proxyPassword: 'proxy-secret',
  bypass: 'localhost,*.internal',
  cas: [
    CaEntry('corp.pem', Uint8List.fromList([1, 2, 3])),
  ],
  clientCerts: [
    ClientCertEntry(
      id: 'a',
      pattern: 'api.test',
      name: 'API',
      certificate: Uint8List.fromList([4, 5, 6]),
      privateKey: Uint8List.fromList([7, 8, 9]),
      passphrase: 'key-pass',
    ),
    ClientCertEntry(
      id: 'b',
      pattern: '*',
      name: 'Bundle',
      certificate: Uint8List.fromList([10, 11]),
      enabled: false,
    ),
    ClientCertEntry(
      id: 'c',
      pattern: 'internal.test:8443',
      name: 'No client certificate',
      certificate: Uint8List(0),
      none: true,
    ),
  ],
);

void main() {
  test('settings and secrets round trip through the stores', () {
    final local = LocalStore.memory();
    addTearDown(local.close);
    final secrets = LocalDbSecretStore(local);
    final store = NetworkConfigStore(local, secrets, 'ws1');
    expect(store.read().clientCerts, isEmpty);
    store.write(_config());
    final back = store.read();
    expect(back.proxyHost, 'proxy.test');
    expect(back.proxyPort, 3128);
    expect(back.proxyPassword, 'proxy-secret');
    expect(back.cas.single.name, 'corp.pem');
    expect(back.cas.single.bytes, [1, 2, 3]);
    expect(back.clientCerts.map((c) => c.id), ['a', 'b', 'c']);
    expect(back.clientCerts[0].privateKey, [7, 8, 9]);
    expect(back.clientCerts[0].passphrase, 'key-pass');
    expect(back.clientCerts[1].enabled, isFalse);
    expect(back.clientCerts[1].privateKey, isNull);
    expect(back.clientCerts[2].none, isTrue);
    // Another workspace sees nothing.
    expect(NetworkConfigStore(local, secrets, 'ws2').read().cas, isEmpty);
  });

  test('keys, passphrases and the proxy password are not in the JSON', () {
    final local = LocalStore.memory();
    addTearDown(local.close);
    final store = NetworkConfigStore(local, LocalDbSecretStore(local), 'ws1');
    store.write(_config());
    final raw = local.kv('ws1', networkKvKey)!;
    expect(raw, isNot(contains('proxy-secret')));
    expect(raw, isNot(contains('key-pass')));
    expect(raw, isNot(contains(base64Encode([7, 8, 9]))));
    expect(raw, contains(base64Encode([4, 5, 6])));
  });

  test('removing an entry removes its secrets', () {
    final local = LocalStore.memory();
    addTearDown(local.close);
    final secrets = LocalDbSecretStore(local);
    final store = NetworkConfigStore(local, secrets, 'ws1');
    store.write(_config());
    expect(secrets.values('ws1', networkKind, 'config'), contains('key.a'));
    store.write(_config().copyWith(clientCerts: const []));
    expect(
      secrets.values('ws1', networkKind, 'config'),
      isNot(contains('key.a')),
    );
    expect(
      secrets.values('ws1', networkKind, 'config'),
      contains('proxyPassword'),
    );
  });

  test('data written before enabled/none existed reads as enabled', () {
    final old = {
      'certs': [
        {
          'id': 'x',
          'pattern': '*',
          'name': 'old',
          'cert': base64Encode([1]),
        },
      ],
    };
    final c = NetworkConfigStore.readJson(old, {
      'key.x': base64Encode([2]),
    });
    expect(c.clientCerts.single.enabled, isTrue);
    expect(c.clientCerts.single.none, isFalse);
    expect(c.clientCerts.single.privateKey, [2]);
  });

  test('the TLS config and the proxy follow the settings', () {
    final c = _config();
    final tls = c.tls!;
    expect(tls.caCertificates, hasLength(1));
    expect(tls.clientCertificateFor('api.test')!.label, 'API');
    // The "*" entry is switched off and the :8443 pattern is a none entry.
    expect(tls.clientCertificateFor('other.test'), isNull);
    expect(tls.selectFor('internal.test', port: 8443)!.isNone, isTrue);
    expect(c.proxy!.bypass, ['localhost', '*.internal']);
    expect(const NetworkConfig().tls, isNull);
    expect(const NetworkConfig().proxy, isNull);
  });
}
