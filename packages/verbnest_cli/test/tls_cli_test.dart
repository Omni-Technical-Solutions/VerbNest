import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:test_server/test_server.dart';
import 'package:verbnest_cli/verbnest_cli.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_runner/verbnest_runner.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

class _Sink implements IOSink {
  final buffer = StringBuffer();
  @override
  Encoding encoding = utf8;
  @override
  void write(Object? o) => buffer.write(o);
  @override
  void writeln([Object? o = '']) => buffer.writeln(o);
  @override
  void writeAll(Iterable<Object?> o, [String s = '']) => buffer.writeAll(o, s);
  @override
  void writeCharCode(int c) => buffer.writeCharCode(c);
  @override
  void add(List<int> data) => buffer.write(utf8.decode(data));
  @override
  void addError(Object e, [StackTrace? st]) {}
  @override
  Future<void> addStream(Stream<List<int>> s) async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> get done async {}
  @override
  String toString() => buffer.toString();
}

class _MemoryVault implements SecretVault {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// `verbnest run` and `verbnest tls` with client certificates (FR-HTTP-013c).
void main() {
  late bool available;
  late Directory dir;
  late String workspace;
  late String workspaceId;
  late SecureServerSocket server;
  late (List<int>, List<int>) client;

  setUpAll(() async => available = await TestServer.tlsAvailable);

  setUp(() async {
    if (!available) return;
    dir = Directory.systemTemp.createTempSync('verbnest-tls-cli');
    client = await TestServer.selfSignedCertificate(cn: 'cli-client');
    final (cert, key) = await TestServer.selfSignedCertificate();
    final context = SecurityContext()
      ..useCertificateChainBytes(cert)
      ..usePrivateKeyBytes(key)
      ..setTrustedCertificatesBytes(client.$1);
    server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      context,
      requestClientCertificate: true,
      requireClientCertificate: true,
    );
    server.listen((s) {
      final buf = BytesBuilder();
      s.listen((d) async {
        buf.add(d);
        if (!latin1.decode(buf.toBytes()).contains('\r\n\r\n')) return;
        final who = s.peerCertificate?.subject ?? 'none';
        s.add(
          utf8.encode(
            'HTTP/1.1 200 OK\r\nContent-Length: ${who.length}\r\nConnection: close\r\n\r\n$who',
          ),
        );
        await s.close();
      }, onError: (Object _) {});
    }, onError: (Object _) {});

    workspace = '${dir.path}/w.verbnest';
    final db = WorkspaceDatabase.open(workspace, create: true);
    final repo = WorkspaceRepository(db);
    workspaceId = repo.workspaceId;
    final col = repo.createCollection('API');
    repo.createRequest(
      col,
      HttpRequestItem(
        id: '',
        name: 'who',
        url: 'https://127.0.0.1:${server.port}/',
        assertions: const [
          Assertion(target: AssertionTarget.status, value: '200'),
          Assertion(
            target: AssertionTarget.body,
            op: AssertionOp.contains,
            value: 'cli-client',
          ),
        ],
      ),
    );
    db.close();
    File('${dir.path}/c.pem').writeAsBytesSync(client.$1);
    File('${dir.path}/k.pem').writeAsBytesSync(client.$2);
  });

  tearDown(() async {
    if (!available) return;
    await server.close();
    dir.deleteSync(recursive: true);
  });

  Future<(int, String, String)> cli(
    List<String> args, {
    Map<String, String> env = const {},
    SecretVault? vault,
  }) async {
    final out = _Sink();
    final err = _Sink();
    final code = await runCli(
      args,
      out: out,
      err: err,
      environment: env,
      vault: vault,
    );
    return (code, '$out', '$err');
  }

  List<String> run(List<String> extra) => [
    'run', workspace, '-c', 'API', '--insecure', ...extra, //
  ];

  group('verbnest run', () {
    test('without a certificate the server turns the request down', () async {
      if (!available) return markTestSkipped('openssl not found');
      final (code, out, _) = await cli(run([]));
      expect(code, 1);
      expect(out, contains('FAIL'));
    });

    test('--cert and --key present the certificate', () async {
      if (!available) return markTestSkipped('openssl not found');
      final (code, out, err) = await cli(
        run(['--cert', '${dir.path}/c.pem', '--key', '${dir.path}/k.pem']),
      );
      expect(code, 0, reason: '$out $err');
      expect(out, contains('PASS'));
      expect(err, contains('TLS: client certificate'));
    });

    test('a PKCS#12 bundle with its passphrase from the environment', () async {
      if (!available) return markTestSkipped('openssl not found');
      final p12 = await TestServer.pkcs12(client.$1, client.$2, 'bundle-pw');
      File('${dir.path}/b.p12').writeAsBytesSync(p12);
      final (code, out, err) = await cli(
        run(['--cert', '${dir.path}/b.p12', '--cert-passphrase-env', 'PW']),
        env: {'PW': 'bundle-pw'},
      );
      expect(code, 0, reason: '$out $err');
      final (bad, _, msg) = await cli(
        run(['--cert', '${dir.path}/b.p12', '--cert-passphrase-env', 'PW']),
        env: {'PW': 'wrong'},
      );
      expect(bad, 2);
      expect(msg, contains('passphrase is wrong'));
      final (unset, _, msg2) = await cli(
        run(['--cert', '${dir.path}/b.p12', '--cert-passphrase-env', 'NOPE']),
      );
      expect(unset, 2);
      expect(msg2, contains('NOPE is not set'));
    });

    test('a passphrase file uses its first line', () async {
      if (!available) return markTestSkipped('openssl not found');
      final p12 = await TestServer.pkcs12(client.$1, client.$2, 'file-pw');
      File('${dir.path}/b.p12').writeAsBytesSync(p12);
      File('${dir.path}/pw.txt').writeAsStringSync('file-pw\nsecond line\n');
      final (code, out, err) = await cli(
        run([
          '--cert',
          '${dir.path}/b.p12',
          '--cert-passphrase-file',
          '${dir.path}/pw.txt',
        ]),
      );
      expect(code, 0, reason: '$out $err');
    });

    test('--cert-host that does not match this host sends nothing', () async {
      if (!available) return markTestSkipped('openssl not found');
      final (code, _, _) = await cli(
        run([
          '--cert',
          '${dir.path}/c.pem',
          '--key',
          '${dir.path}/k.pem',
          '--cert-host',
          '*.other.test',
        ]),
      );
      expect(code, 1);
    });

    test('usage errors are exit code 2 with a reason', () async {
      if (!available) return markTestSkipped('openssl not found');
      final cases = {
        ['--key', '${dir.path}/k.pem']: '--key needs --cert',
        ['--cert', '${dir.path}/c.pem']: 'private key',
        ['--cert', '${dir.path}/nope.pem', '--key', '${dir.path}/k.pem']:
            'Cannot read',
        ['--ca', '${dir.path}/k.pem']: '--ca',
        ['--cert-passphrase-env', 'X']: 'needs --cert',
        ['--network-config', '${dir.path}/x.json']:
            '--network-config-passphrase-env',
      };
      for (final e in cases.entries) {
        final (code, _, err) = await cli(run(e.key));
        expect(code, 2, reason: '${e.key}');
        expect(err, contains(e.value), reason: '${e.key}');
      }
    });

    test('a network export file is read with its passphrase', () async {
      if (!available) return markTestSkipped('openssl not found');
      final file = await NetworkExport.encrypt(
        NetworkConfig(
          clientCerts: [
            ClientCertEntry(
              id: 'a',
              pattern: '127.0.0.1',
              name: 'From export',
              certificate: Uint8List.fromList(client.$1),
              privateKey: Uint8List.fromList(client.$2),
            ),
          ],
        ),
        'export-pw',
        iterations: 10000,
      );
      File('${dir.path}/net.json').writeAsBytesSync(file);
      final args = run([
        '--network-config',
        '${dir.path}/net.json',
        '--network-config-passphrase-env',
        'EP',
      ]);
      final (code, out, err) = await cli(args, env: {'EP': 'export-pw'});
      expect(code, 0, reason: '$out $err');
      expect(err, contains('export file'));
      final (bad, _, msg) = await cli(args, env: {'EP': 'nope'});
      expect(bad, 2);
      expect(msg, contains('passphrase is wrong'));
    });

    group('--app-network', () {
      void saveInApp(
        String appDir, {
        required bool keyInVault,
        _MemoryVault? vault,
      }) {
        Directory(appDir).createSync(recursive: true);
        final local = LocalStore.open('$appDir/local.db');
        final config = NetworkConfig(
          clientCerts: [
            ClientCertEntry(
              id: 'a',
              pattern: '127.0.0.1',
              name: 'App cert',
              certificate: Uint8List.fromList(client.$1),
              privateKey: Uint8List.fromList(client.$2),
            ),
          ],
        );
        if (keyInVault) {
          // The settings go to local.db, the key only to the system store.
          final secrets = LocalDbSecretStore(local);
          NetworkConfigStore(local, secrets, workspaceId).write(config);
          secrets.remove(workspaceId, networkKind, 'config', 'key.a');
          final blob = <String, String>{
            jsonEncode([networkKind, 'config', 'key.a']): base64Encode(
              client.$2,
            ),
          };
          vault!.data[VaultSecretStore.vaultKey(workspaceId)] = jsonEncode(
            blob,
          );
        } else {
          NetworkConfigStore(
            local,
            LocalDbSecretStore(local),
            workspaceId,
          ).write(config);
        }
        local.close();
      }

      test('reads the entries and, from local.db, their keys', () async {
        if (!available) return markTestSkipped('openssl not found');
        final app = '${dir.path}/app';
        saveInApp(app, keyInVault: false);
        final (code, out, err) = await cli(
          run(['--app-network', '--app-data-dir', app]),
        );
        expect(code, 0, reason: '$out $err');
        expect(err, contains('the app: 0 CA(s), 1 client certificate(s)'));
      });

      test('a key kept in the system store needs --vault', () async {
        if (!available) return markTestSkipped('openssl not found');
        final app = '${dir.path}/app';
        final vault = _MemoryVault();
        saveInApp(app, keyInVault: true, vault: vault);
        final (without, _, warn) = await cli(
          run(['--app-network', '--app-data-dir', app]),
          vault: vault,
        );
        expect(without, 1);
        expect(warn, contains('add --vault'));
        final (code, out, err) = await cli(
          run(['--app-network', '--app-data-dir', app, '--vault']),
          vault: vault,
        );
        expect(code, 0, reason: '$out $err');
      });

      test('no local.db is a usage error that names where it looked', () async {
        if (!available) return markTestSkipped('openssl not found');
        final (code, _, err) = await cli(
          run(['--app-network', '--app-data-dir', '${dir.path}/missing']),
        );
        expect(code, 2);
        expect(err, contains('no local.db found'));
      });
    });

    test('no key, passphrase or certificate text is in a report', () async {
      if (!available) return markTestSkipped('openssl not found');
      File('${dir.path}/pw.txt').writeAsStringSync('very-secret-passphrase\n');
      final p12 = await TestServer.pkcs12(
        client.$1,
        client.$2,
        'very-secret-passphrase',
      );
      File('${dir.path}/b.p12').writeAsBytesSync(p12);
      for (final reporter in ['json', 'junit', 'html']) {
        final out = '${dir.path}/report.$reporter';
        final (code, o, e) = await cli(
          run([
            '--cert',
            '${dir.path}/b.p12',
            '--cert-passphrase-file',
            '${dir.path}/pw.txt',
            '-r',
            reporter,
            '-o',
            out,
          ]),
        );
        expect(code, 0, reason: '$o $e');
        final text = File(out).readAsStringSync() + o + e;
        expect(text, isNot(contains('very-secret-passphrase')));
        expect(text, isNot(contains(base64Encode(client.$2).substring(0, 60))));
        expect(text, isNot(contains(base64Encode(p12).substring(0, 60))));
        expect(text, isNot(contains('BEGIN')));
      }
    });
  });

  group('verbnest tls', () {
    test('inspect shows a certificate and checks a key', () async {
      if (!available) return markTestSkipped('openssl not found');
      final (code, out, _) = await cli([
        'tls',
        'inspect',
        '${dir.path}/c.pem',
        '--key',
        '${dir.path}/k.pem',
      ]);
      expect(code, 0);
      expect(out, contains('CN=cli-client'));
      expect(out, contains('RSA 2048'));
      expect(out, contains('SHA-256:'));
      expect(out, contains('The key matches the certificate.'));
      final other = await TestServer.selfSignedCertificate(cn: 'someone-else');
      File('${dir.path}/o.pem').writeAsBytesSync(other.$2);
      final (bad, _, err) = await cli([
        'tls',
        'inspect',
        '${dir.path}/c.pem',
        '--key',
        '${dir.path}/o.pem',
      ]);
      expect(bad, 2);
      expect(err, contains('does not match'));
    });

    test('inspect: a PKCS#12 bundle, junk and a missing file', () async {
      if (!available) return markTestSkipped('openssl not found');
      File(
        '${dir.path}/b.p12',
      ).writeAsBytesSync(await TestServer.pkcs12(client.$1, client.$2, 'pw1'));
      final (ok, out, _) = await cli(
        ['tls', 'inspect', '${dir.path}/b.p12', '--passphrase-env', 'PW'],
        env: {'PW': 'pw1'},
      );
      expect(ok, 0);
      expect(out, contains('PKCS#12 bundle'));
      final (bad, _, err) = await cli(
        ['tls', 'inspect', '${dir.path}/b.p12', '--passphrase-env', 'PW'],
        env: {'PW': 'no'},
      );
      expect(bad, 2);
      expect(err, contains('wrong'));
      File('${dir.path}/junk').writeAsBytesSync([1, 2, 3, 4]);
      expect((await cli(['tls', 'inspect', '${dir.path}/junk'])).$1, 2);
      expect((await cli(['tls', 'inspect', '${dir.path}/none'])).$1, 2);
    });

    test(
      'check: the server certificate, and the client certificate it needs',
      () async {
        if (!available) return markTestSkipped('openssl not found');
        final url = 'https://127.0.0.1:${server.port}/';
        final (code, out, err) = await cli([
          'tls',
          'check',
          url,
          '--cert',
          '${dir.path}/c.pem',
          '--key',
          '${dir.path}/k.pem',
        ]);
        expect(code, 0, reason: '$out $err');
        expect(out, contains('Server certificate:'));
        expect(out, contains('CN=localhost'));
        expect(out, contains('Trusted:  no'));
        expect(out, contains('Names 127.0.0.1: yes'));
        expect(out, contains('Client certificate: offered "c.pem"'));
        final (refused, out2, _) = await cli(['tls', 'check', url]);
        expect(refused, 1);
        expect(out2, contains('needs a client certificate'));
        final (strict, _, serr) = await cli([
          'tls',
          'check',
          url,
          '--strict',
          '--cert',
          '${dir.path}/c.pem',
          '--key',
          '${dir.path}/k.pem',
        ]);
        expect(strict, 1);
        expect(serr, contains('--strict'));
      },
    );

    test('check: an unreachable host is exit code 1; bad input is 2', () async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close();
      expect((await cli(['tls', 'check', '127.0.0.1:$port'])).$1, 1);
      expect((await cli(['tls', 'check'])).$1, 2);
      expect((await cli(['tls', 'nonsense'])).$1, 2);
      expect((await cli(['tls'])).$1, 2);
    });
  });
}
