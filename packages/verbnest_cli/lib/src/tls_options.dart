import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_runner/verbnest_runner.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

/// A bad TLS option or unreadable certificate file: exit code 2.
class TlsUsageError implements Exception {
  TlsUsageError(this.message);

  final String message;
}

/// Adds the certificate options of `verbnest run` (FR-HTTP-013c).
/// With [appNetwork] false only the options that need no workspace.
void addTlsOptions(ArgParser p, {bool appNetwork = true}) {
  p
    ..addMultiOption(
      'ca',
      help: 'Trust this CA certificate (PEM or DER) as well. Repeatable.',
      valueHelp: 'file',
    )
    ..addOption(
      'cert',
      help:
          'Client certificate to present: a PEM file (with --key) or a PKCS#12 '
          'bundle.',
      valueHelp: 'file',
    )
    ..addOption('key', help: 'Private key for a PEM --cert.', valueHelp: 'file')
    ..addOption(
      'cert-host',
      help:
          'Hosts the --cert goes to: api.example.com, *.example.com or * '
          '(default), with an optional :port.',
      defaultsTo: '*',
      valueHelp: 'pattern',
    )
    ..addOption(
      'cert-passphrase-env',
      help: 'Name of the environment variable that holds the key passphrase.',
      valueHelp: 'VAR',
    )
    ..addOption(
      'cert-passphrase-file',
      help: 'File whose first line is the key passphrase.',
      valueHelp: 'file',
    )
    ..addOption(
      'network-config',
      help: 'A file made by Settings > Network > Export for the command line.',
      valueHelp: 'file',
    )
    ..addOption(
      'network-config-passphrase-env',
      help: 'Name of the environment variable that holds its passphrase.',
      valueHelp: 'VAR',
    );
  if (appNetwork) {
    p
      ..addFlag(
        'app-network',
        help:
            'Use the proxy, CAs and client certificates saved in the app for this '
            'workspace. Keys and passphrases also need --vault.',
        negatable: false,
      )
      ..addOption(
        'app-data-dir',
        help: 'With --app-network: the app\'s data folder (where local.db is).',
        valueHelp: 'dir',
      );
  }
}

/// The TLS material and proxy the options ask for.
class TlsSetup {
  const TlsSetup({this.tls, this.proxy, this.notes = const []});

  final TlsConfig? tls;
  final ProxyConfig? proxy;

  /// One line each about where entries came from; never a secret.
  final List<String> notes;
}

Uint8List _read(String path, String what) {
  try {
    return File(path).readAsBytesSync();
  } on FileSystemException catch (e) {
    throw TlsUsageError('Cannot read $what "$path": ${e.message}');
  }
}

String? _passphrase(ArgResults r, Map<String, String> env) {
  final name = r['cert-passphrase-env'] as String?;
  final file = r['cert-passphrase-file'] as String?;
  if (name != null && file != null) {
    throw TlsUsageError(
      'Use --cert-passphrase-env or --cert-passphrase-file, not both.',
    );
  }
  if (name != null) {
    final v = env[name];
    if (v == null) {
      throw TlsUsageError('--cert-passphrase-env: $name is not set.');
    }
    return v;
  }
  if (file != null) {
    final text = String.fromCharCodes(_read(file, 'passphrase file'));
    return text.split(RegExp(r'\r?\n')).first;
  }
  return null;
}

/// The default places the app keeps `local.db`, most likely first.
List<String> appDataDirs(Map<String, String> env) {
  final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
  if (Platform.isMacOS) {
    return [
      '$home/Library/Application Support/com.omni.verbnest',
      '$home/Library/Containers/com.omni.verbnest/Data/Library/Application Support/com.omni.verbnest',
    ];
  }
  if (Platform.isWindows) {
    final appData = env['APPDATA'] ?? '$home\\AppData\\Roaming';
    return ['$appData\\Omni Technical Solutions Pty Ltd\\VerbNest'];
  }
  final data = env['XDG_DATA_HOME'] ?? '$home/.local/share';
  return ['$data/com.omni.verbnest'];
}

/// Builds the TLS configuration and proxy from the options. [vaultSecrets]
/// are the secrets read with `--vault`, if it was given. Warnings (an expired
/// certificate) go to [warn].
Future<TlsSetup> buildTlsSetup(
  ArgResults r, {
  required String? workspaceId,
  required Map<String, String> environment,
  required SecretStore? vaultSecrets,
  required void Function(String) warn,
}) async {
  final cas = <Uint8List>[];
  final certs = <ClientCertificate>[];
  final notes = <String>[];
  ProxyConfig? proxy;

  // 1. Files named on the command line win ties.
  for (final path in r['ca'] as List<String>) {
    final bytes = _read(path, 'CA file');
    try {
      parseCertificates(bytes);
    } on CertFormatException catch (e) {
      throw TlsUsageError('--ca $path: ${e.message}');
    }
    cas.add(bytes);
  }
  final certPath = r['cert'] as String?;
  final keyPath = r['key'] as String?;
  if (certPath == null && (keyPath != null)) {
    throw TlsUsageError('--key needs --cert.');
  }
  if (certPath != null) {
    final cert = _read(certPath, 'certificate');
    final key = keyPath == null ? null : _read(keyPath, 'key file');
    final pass = _passphrase(r, environment) ?? '';
    final check = checkClientCertificate(
      certificate: cert,
      privateKey: key,
      passphrase: pass,
    );
    if (!check.ok) throw TlsUsageError('--cert $certPath: ${check.message}');
    for (final w in check.warnings) {
      final name = switch (w) {
        CertWarning.expired => 'has expired',
        CertWarning.notYetValid => 'is not valid yet',
        CertWarning.expiresSoon => 'expires within 30 days',
        CertWarning.selfSigned => null,
      };
      if (name != null) {
        warn('Warning: the client certificate $certPath $name.');
      }
    }
    certs.add(
      ClientCertificate(
        hostPattern: r['cert-host'] as String,
        certificate: cert,
        privateKey: key,
        passphrase: pass,
        label: certPath.split(RegExp(r'[\\/]')).last,
      ),
    );
    notes.add('client certificate $certPath for ${r['cert-host']}');
  } else if (r['cert-passphrase-env'] != null ||
      r['cert-passphrase-file'] != null) {
    throw TlsUsageError('A passphrase option needs --cert.');
  }

  // 2. An export file made by the app.
  final exportPath = r['network-config'] as String?;
  if (exportPath != null) {
    final envName = r['network-config-passphrase-env'] as String?;
    if (envName == null) {
      throw TlsUsageError(
        '--network-config needs --network-config-passphrase-env VAR.',
      );
    }
    final pass = environment[envName];
    if (pass == null) {
      throw TlsUsageError(
        '--network-config-passphrase-env: $envName is not set.',
      );
    }
    try {
      final cfg = await NetworkExport.decrypt(
        _read(exportPath, 'network export'),
        pass,
      );
      _take(cfg, cas, certs, notes, 'export file $exportPath');
      proxy ??= cfg.proxy;
    } on NetworkExportError catch (e) {
      throw TlsUsageError('--network-config: ${e.message}');
    }
  }

  // 3. What the app saved on this computer.
  if (r.options.contains('app-network') && (r['app-network'] as bool)) {
    final cfg = _readAppNetwork(r, workspaceId!, environment, vaultSecrets);
    final skipped = cfg.clientCerts
        .where((c) => c.enabled && c.needsKey)
        .length;
    _take(cfg, cas, certs, notes, 'the app');
    if (skipped > 0) {
      warn(
        'Warning: $skipped client certificate(s) in the app need their key: '
        'add --vault.',
      );
    }
    proxy ??= cfg.proxy;
  }

  final tls = cas.isEmpty && certs.isEmpty
      ? null
      : TlsConfig(caCertificates: cas, clientCertificates: certs);
  return TlsSetup(tls: tls, proxy: proxy, notes: notes);
}

/// Adds the usable entries of [cfg] and a note about them.
void _take(
  NetworkConfig cfg,
  List<Uint8List> cas,
  List<ClientCertificate> certs,
  List<String> notes,
  String from,
) {
  final tls = cfg.tls;
  if (tls != null) {
    cas.addAll(tls.caCertificates);
    // An entry without its key cannot be used; the app's list shows it, here
    // it is left out (the caller warns).
    certs.addAll(
      tls.clientCertificates.where(
        (c) =>
            c.isNone ||
            c.privateKey != null ||
            !String.fromCharCodes(c.certificate.take(200))
                .contains('-----BEGIN'),
      ),
    );
  }
  final n = cfg.clientCerts.where((c) => c.enabled && !c.none).length;
  notes.add(
    '$from: ${cfg.cas.length} CA(s), $n client certificate(s)'
    '${cfg.proxy == null ? '' : ', a proxy'}',
  );
}

NetworkConfig _readAppNetwork(
  ArgResults r,
  String workspaceId,
  Map<String, String> env,
  SecretStore? vaultSecrets,
) {
  final given = r['app-data-dir'] as String?;
  final candidates = given != null ? [given] : appDataDirs(env);
  String? db;
  for (final d in candidates) {
    final f = '$d${Platform.pathSeparator}local.db';
    if (File(f).existsSync()) {
      db = f;
      break;
    }
  }
  if (db == null) {
    throw TlsUsageError(
      '--app-network: no local.db found in ${candidates.join(' or ')}. '
      'Open the app once, or give --app-data-dir.',
    );
  }
  final LocalStore local;
  try {
    local = LocalStore.open(db);
  } on Object catch (e) {
    throw TlsUsageError('--app-network: cannot open $db: $e');
  }
  try {
    final raw = local.kv(workspaceId, networkKvKey);
    if (raw == null) return const NetworkConfig();
    // The app keeps secrets in the system store, or here when that did not
    // work; the system store wins.
    final secrets = <String, String>{
      ...LocalDbSecretStore(local).values(workspaceId, networkKind, 'config'),
      ...?vaultSecrets?.values(workspaceId, networkKind, 'config'),
    };
    return NetworkConfigStore.readJson(NetworkConfigStore.decode(raw), secrets);
  } finally {
    local.close();
  }
}
