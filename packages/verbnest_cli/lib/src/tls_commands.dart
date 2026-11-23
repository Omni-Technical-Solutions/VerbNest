import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:verbnest_http/verbnest_http.dart';

import 'tls_options.dart';

const _tlsUsage = '''
verbnest tls inspect <certificate> [--key <file>] [--passphrase-env VAR]
verbnest tls check <url> [certificate options] [--strict]

`inspect` prints what a certificate says: subject, issuer, validity, key,
names and fingerprints. For a PKCS#12 bundle, or a PEM with --key, it also
checks that the file loads (a passphrase comes from --passphrase-env).
Exit 0 when the file is readable, 2 when it is not.

`check` connects to the URL's host, performs the TLS handshake (with the CA
and client certificate options below, like `verbnest run`) and prints the
server certificate, whether it is trusted and names the host, and the client
certificate that was offered. No request is sent. Exit 0 on success, 1 when
the handshake fails or the server turns the client certificate down, 2 when a
certificate file is unreadable; with --strict, 1 also when the server
certificate is not trusted or does not name the host.
''';

ArgParser _inspectParser() => ArgParser()
  ..addOption(
    'key',
    help: 'Private key of a PEM certificate.',
    valueHelp: 'file',
  )
  ..addOption(
    'passphrase-env',
    help: 'Environment variable with the key or bundle passphrase.',
    valueHelp: 'VAR',
  )
  ..addFlag('help', abbr: 'h', negatable: false);

ArgParser _checkParser() {
  final p = ArgParser()
    ..addFlag(
      'strict',
      help: 'Fail when the server certificate is untrusted or wrong for the host.',
      negatable: false,
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  addTlsOptions(p, appNetwork: false);
  return p;
}

/// `verbnest tls ...` (FR-HTTP-013c). Returns the exit code.
Future<int> runTlsCommand(
  List<String> args,
  IOSink out,
  IOSink err,
  Map<String, String> environment,
) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    out.writeln(_tlsUsage);
    return args.isEmpty ? 2 : 0;
  }
  try {
    switch (args.first) {
      case 'inspect':
        return _inspect(args.skip(1), out, err, environment);
      case 'check':
        return await _check(args.skip(1), out, err, environment);
    }
  } on FormatException catch (e) {
    err.writeln(e.message);
    return 2;
  } on TlsUsageError catch (e) {
    err.writeln(e.message);
    return 2;
  }
  err.writeln('Unknown command "tls ${args.first}". Try: verbnest tls --help');
  return 2;
}

String _date(DateTime d) => d.toUtc().toIso8601String().substring(0, 10);

void _print(IOSink out, CertInfo c, {String indent = ''}) {
  final now = DateTime.now();
  final left = c.daysLeft(now);
  final status = c.isExpired(now)
      ? 'EXPIRED ${-left} day(s) ago'
      : c.isNotYetValid(now)
      ? 'not valid yet'
      : '$left day(s) left';
  out
    ..writeln('$indent Subject:  ${c.subject}')
    ..writeln(
      '$indent Issuer:   ${c.issuer}${c.selfSigned ? ' (self-signed)' : ''}',
    )
    ..writeln('$indent Serial:   ${c.serialHex}')
    ..writeln(
      '$indent Valid:    ${_date(c.notBefore)} to ${_date(c.notAfter)} ($status)',
    )
    ..writeln('$indent Key:      ${c.keyAlgorithm}');
  if (c.names.isNotEmpty) {
    out.writeln('$indent Names:    ${c.names.join(', ')}');
  }
  out
    ..writeln('$indent SHA-256:  ${c.sha256}')
    ..writeln('$indent Key SHA-256: ${c.spkiSha256}');
}

int _inspect(
  Iterable<String> args,
  IOSink out,
  IOSink err,
  Map<String, String> env,
) {
  final r = _inspectParser().parse(args);
  if (r['help'] as bool) {
    out.writeln(_tlsUsage);
    return 0;
  }
  if (r.rest.length != 1) {
    err.writeln('Expected one certificate file. Try: verbnest tls --help');
    return 2;
  }
  final path = r.rest.single;
  final Uint8List raw;
  try {
    raw = File(path).readAsBytesSync();
  } on FileSystemException catch (e) {
    err.writeln('Cannot read "$path": ${e.message}');
    return 2;
  }
  final bytes = raw;
  final keyPath = r['key'] as String?;
  final envName = r['passphrase-env'] as String?;
  final pass = envName == null ? '' : (env[envName] ?? '');
  if (envName != null && !env.containsKey(envName)) {
    err.writeln('--passphrase-env: $envName is not set.');
    return 2;
  }
  final isPem = String.fromCharCodes(bytes.take(200)).contains('-----BEGIN');
  if (isPem) {
    final List<CertInfo> chain;
    try {
      chain = parseCertificates(bytes);
    } on CertFormatException catch (e) {
      err.writeln('$path: ${e.message}');
      return 2;
    }
    for (var i = 0; i < chain.length; i++) {
      if (chain.length > 1) {
        out.writeln('Certificate ${i + 1} of ${chain.length}');
      }
      _print(out, chain[i]);
    }
    if (keyPath != null) {
      final Uint8List key;
      try {
        key = File(keyPath).readAsBytesSync();
      } on FileSystemException catch (e) {
        err.writeln('Cannot read "$keyPath": ${e.message}');
        return 2;
      }
      final c = checkClientCertificate(
        certificate: bytes,
        privateKey: key,
        passphrase: pass,
      );
      if (!c.ok) {
        err.writeln('$keyPath: ${c.message}');
        return 2;
      }
      out.writeln('The key matches the certificate.');
    }
    return 0;
  }
  // PKCS#12 or DER.
  try {
    final chain = parseCertificates(bytes);
    for (final c in chain) {
      _print(out, c);
    }
    return 0;
  } on CertFormatException {
    // Not DER: try it as a PKCS#12 bundle.
  }
  final c = checkClientCertificate(certificate: bytes, passphrase: pass);
  if (!c.ok) {
    err.writeln('$path: ${c.message}');
    return 2;
  }
  out.writeln('$path is a PKCS#12 bundle and opens with that passphrase.');
  out.writeln(
    '(The certificate inside is not shown: the TLS library does not expose it.)',
  );
  return 0;
}

Future<int> _check(
  Iterable<String> args,
  IOSink out,
  IOSink err,
  Map<String, String> env,
) async {
  final parser = _checkParser();
  final r = parser.parse(args);
  if (r['help'] as bool) {
    out.writeln(_tlsUsage);
    out.writeln(parser.usage);
    return 0;
  }
  if (r.rest.length != 1) {
    err.writeln('Expected one URL. Try: verbnest tls --help');
    return 2;
  }
  var text = r.rest.single;
  if (!text.contains('://')) text = 'https://$text';
  final url = Uri.tryParse(text);
  if (url == null || url.host.isEmpty) {
    err.writeln('"${r.rest.single}" is not a URL.');
    return 2;
  }
  final setup = await buildTlsSetup(
    r,
    workspaceId: null,
    environment: env,
    vaultSecrets: null,
    warn: err.writeln,
  );
  final TlsProbe p;
  try {
    p = await probeTls(url, tls: setup.tls);
  } on TlsProbeError catch (e) {
    err.writeln(e.message);
    return 1;
  }
  final port = url.hasPort ? url.port : 443;
  out.writeln(
    'Connected to ${url.host}:$port in ${p.time.inMilliseconds} ms'
    '${p.protocol == null ? '' : ' (${p.protocol})'}',
  );
  out.writeln('Server certificate:');
  _print(out, p.server, indent: ' ');
  out.writeln(
    ' Trusted:  ${p.trusted ? 'yes' : 'no (not by the system roots or --ca)'}',
  );
  out.writeln(' Names ${url.host}: ${p.hostMatches ? 'yes' : 'NO'}');
  final cc = p.clientCertificate;
  out.writeln(
    cc == null
        ? 'Client certificate: none configured for this host'
        : 'Client certificate: offered "${cc.label.isEmpty ? cc.hostPattern : cc.label}"',
  );
  var code = 0;
  if (p.rejectedClientCertificate) {
    out.writeln(
      'The server closed the connection right after the handshake: it '
      'probably needs a client certificate it was not given, or does not '
      'accept the one offered.',
    );
    code = 1;
  }
  if (r['strict'] as bool && (!p.trusted || !p.hostMatches)) {
    err.writeln(
      '--strict: the server certificate is not trusted or does not name the host.',
    );
    code = 1;
  }
  return code;
}
