import 'dart:convert';
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
      'tls-min',
      help: 'Refuse servers that cannot do at least this TLS version.',
      allowed: ['1.2', '1.3'],
      valueHelp: '1.2|1.3',
    )
    ..addMultiOption(
      'pin',
      help:
          'Expect this server key (SHA-256 of the public key, or of the '
          'certificate): host[:port]=hash. Repeatable.',
      valueHelp: 'host=sha256',
    )
    ..addOption(
      'pin-file',
      help:
          'Keep pins in this file: read at the start, and a server seen for '
          'the first time is added to it.',
      valueHelp: 'file',
    )
    ..addFlag(
      'trust-changed',
      help: 'Accept a changed key for a pin that was recorded, and update it.',
      negatable: false,
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
  TlsSetup({
    this.tls,
    this.proxy,
    this.notes = const [],
    List<PinEntry>? pinMismatches,
  }) : pinMismatches = pinMismatches ?? [];

  final TlsConfig? tls;

  /// Pinned servers that showed another key during the run (exit code 3).
  final List<PinEntry> pinMismatches;
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
  final pins = <PinEntry>[];
  String? appMin;
  var pinByDefault = true;

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
      pins.addAll(cfg.pins);
      appMin ??= cfg.minTls == null ? null : _versionText(cfg.minTls!);
      pinByDefault = pinByDefault && cfg.pinByDefault;
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
    pins.addAll(cfg.pins);
    appMin ??= cfg.minTls == null ? null : _versionText(cfg.minTls!);
    pinByDefault = pinByDefault && cfg.pinByDefault;
    if (skipped > 0) {
      warn(
        'Warning: $skipped client certificate(s) in the app need their key: '
        'add --vault.',
      );
    }
    proxy ??= cfg.proxy;
  }

  final mismatches = <PinEntry>[];
  final book = _pins(r, pins, notes, mismatches);
  final minTls = switch (r['tls-min'] as String? ?? appMin) {
    '1.3' => TlsVersion.v13,
    '1.2' => TlsVersion.v12,
    _ => null,
  };
  final tls =
      cas.isEmpty && certs.isEmpty && book.entries.isEmpty && minTls == null
      ? null
      : TlsConfig(
          caCertificates: cas,
          clientCertificates: certs,
          pins: book,
          pinByDefault: pinByDefault,
          minimumVersion: minTls,
        );
  return TlsSetup(
    tls: tls,
    proxy: proxy,
    notes: notes,
    pinMismatches: mismatches,
  );
}

/// The pins in force: those of the export file or the app, those in
/// `--pin-file`, and `--pin` ones (which win). With `--pin-file` a pin
/// recorded on first use is saved there.
PinBook _pins(
  ArgResults r,
  List<PinEntry> given,
  List<String> notes,
  List<PinEntry> mismatches,
) {
  final byKey = <String, PinEntry>{
    for (final p in given) '${p.host}:${p.port}': p,
  };
  final file = r['pin-file'] as String?;
  if (file != null && File(file).existsSync()) {
    try {
      final j = jsonDecode(File(file).readAsStringSync()) as Map;
      for (final p in (j['pins'] as List? ?? const [])) {
        final e = PinEntry.fromJson(p as Map);
        byKey['${e.host}:${e.port}'] = e;
      }
    } on Object catch (e) {
      throw TlsUsageError('--pin-file $file: not a pin file ($e)');
    }
  }
  for (final text in r['pin'] as List<String>) {
    final i = text.indexOf('=');
    if (i <= 0) {
      throw TlsUsageError('--pin $text: expected host[:port]=sha256.');
    }
    final hash = normalizeFingerprint(text.substring(i + 1));
    if (!RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$').hasMatch(hash)) {
      throw TlsUsageError(
        '--pin $text: that is not a SHA-256 (64 hex digits).',
      );
    }
    var host = text.substring(0, i).toLowerCase();
    var port = 443;
    final c = host.lastIndexOf(':');
    if (c > 0 && int.tryParse(host.substring(c + 1)) != null) {
      port = int.parse(host.substring(c + 1));
      host = host.substring(0, c);
    }
    byKey['$host:$port'] = PinEntry(
      host: host,
      port: port,
      spki: hash,
      leaf: hash,
      manual: true,
    );
  }
  final book = PinBook(byKey.values)
    ..trustChanges = r['trust-changed'] as bool
    ..onMismatch = (pin, _) => mismatches.add(pin);
  if (file != null) {
    book.onChanged = (all) {
      File(file).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
          'pins': [for (final p in all) p.toJson()],
        })}\n',
      );
    };
  }
  if (book.entries.isNotEmpty) {
    notes.add('${book.entries.length} pinned server(s)');
  }
  return book;
}

String _versionText(TlsVersion v) => v == TlsVersion.v13 ? '1.3' : '1.2';

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
