import 'dart:async';
import 'dart:io';

import 'cert_inspect.dart';
import 'keystore.dart';
import 'pin.dart';
import 'tls_config.dart';

/// What a handshake with a server showed (FR-HTTP-013c). No request is sent.
class TlsProbe {
  const TlsProbe({
    required this.server,
    required this.trusted,
    required this.hostMatches,
    required this.protocol,
    required this.clientCertificate,
    required this.clientCertificateConfigured,
    required this.rejectedClientCertificate,
    required this.time,
    this.pin = const PinCheck(PinStatus.notApplicable),
  });

  /// The server's certificate (the leaf; `dart:io` does not give the chain).
  final CertInfo server;

  /// Whether the system roots and the extra CAs trust it.
  final bool trusted;

  /// Whether it names the host that was asked for.
  final bool hostMatches;

  /// The ALPN protocol agreed, `h2` or `http/1.1`, or null.
  final String? protocol;

  /// The entry that would be presented to this host, or null.
  final ClientCertificate? clientCertificate;
  final bool clientCertificateConfigured;

  /// True when the server ended the connection (a TLS alert, or a plain close)
  /// within a moment of the handshake, before any request was sent. A server
  /// that requires a client certificate answers that way when it was given
  /// none or one it does not accept: with TLS 1.3 the client's handshake has
  /// already finished by then.
  final bool rejectedClientCertificate;
  final Duration time;

  /// How the server key compares with the pins (nothing is recorded).
  final PinCheck pin;
}

/// The handshake failed (or the certificate files could not be loaded).
class TlsProbeError implements Exception {
  const TlsProbeError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Connects to [url]'s host, performs the TLS handshake with [tls] (its CAs
/// and the client certificate that matches the host) and reports what the
/// server presented, without sending a request. Certificate problems are
/// reported in the result, not thrown, so a self-signed server can still be
/// inspected; only a failed connection or an unreadable certificate throws a
/// [TlsProbeError].
Future<TlsProbe> probeTls(
  Uri url, {
  TlsConfig? tls,
  Duration timeout = const Duration(seconds: 15),
  Duration settle = const Duration(milliseconds: 400),
}) async {
  final host = url.host;
  final port = url.hasPort ? url.port : 443;
  final sw = Stopwatch()..start();
  final entry = tls?.clientCertificateFor(host, port: port);
  if (tls != null && entry != null && entry.isKeystore) {
    return _probeViaKeystore(url, tls, entry, settle, sw);
  }
  SecurityContext? context;
  if (tls != null && !tls.isEmpty) {
    try {
      context = tls.contextFor(host, port: port);
    } on Object catch (e) {
      throw TlsProbeError('Could not load the certificates: $e');
    }
  }
  var trusted = true;
  final SecureSocket socket;
  try {
    socket = await SecureSocket.connect(
      host,
      port,
      context: context,
      supportedProtocols: const ['h2', 'http/1.1'],
      timeout: timeout,
      onBadCertificate: (_) {
        trusted = false;
        return true;
      },
    );
  } on TlsException catch (e) {
    throw TlsProbeError('TLS handshake failed: ${e.message}');
  } on SocketException catch (e) {
    throw TlsProbeError('Cannot connect to $host:$port: ${e.message}');
  } on TimeoutException {
    throw TlsProbeError('Timed out connecting to $host:$port');
  }
  final elapsed = sw.elapsed;
  try {
    final cert = socket.peerCertificate;
    if (cert == null) {
      throw const TlsProbeError('The server presented no certificate');
    }
    final CertInfo info;
    try {
      info = parseCertificate(cert.der);
    } on CertFormatException catch (e) {
      throw TlsProbeError('The server certificate is unreadable: $e');
    }
    // With TLS 1.3 the client finishes its handshake before the server has
    // looked at the client certificate, so wait a moment for an alert.
    final rejected = await _closedWithin(socket, settle);
    final chosen = tls?.clientCertificateFor(host, port: port);
    return TlsProbe(
      server: info,
      trusted: trusted,
      hostMatches: info.coversHost(host),
      protocol: socket.selectedProtocol,
      clientCertificate: chosen,
      clientCertificateConfigured: chosen != null,
      rejectedClientCertificate: rejected,
      time: elapsed,
      pin: checkPin(tls, host, port, info, verified: trusted, record: false),
    );
  } finally {
    socket.destroy();
  }
}

/// [probeTls] for a host whose client certificate is in the system keystore:
/// the platform relay does the handshake. Trust is tried first; when that
/// fails the connection is repeated without checking, so the certificate can
/// still be shown (as the plain path does), and marked untrusted.
Future<TlsProbe> _probeViaKeystore(
  Uri url,
  TlsConfig tls,
  ClientCertificate entry,
  Duration settle,
  Stopwatch sw,
) async {
  final host = url.host;
  final port = url.hasPort ? url.port : 443;
  final relay = tls.relay;
  if (relay == null || !relay.isSupported) {
    throw const TlsProbeError(
      'The client certificate is in the system keystore, which this build '
      'cannot use.',
    );
  }
  Future<RelaySession> open(bool verify) => relay.open(
    RelayRequest(
      host: host,
      port: port,
      identityId: entry.keystoreId!,
      caCertificates: tls.caCertificates,
      minimumVersion: tls.minimumVersion,
      verify: verify,
      protocols: const ['h2', 'http/1.1'],
    ),
  );
  var trusted = true;
  RelaySession session;
  try {
    session = await open(true);
  } on KeystoreError catch (first) {
    try {
      session = await open(false);
      trusted = false;
    } on KeystoreError {
      throw TlsProbeError(first.message);
    }
  }
  try {
    final der = session.serverCertificate;
    if (der == null) {
      throw const TlsProbeError('The server presented no certificate');
    }
    final CertInfo info;
    try {
      info = parseCertificate(der);
    } on CertFormatException catch (e) {
      throw TlsProbeError('The server certificate is unreadable: $e');
    }
    // Open the loopback socket and see whether the server closes at once.
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      session.port,
    );
    final closedByServer = await _closedWithin(socket, settle);
    return TlsProbe(
      server: info,
      trusted: trusted,
      hostMatches: info.coversHost(host),
      protocol: session.protocol,
      clientCertificate: entry,
      clientCertificateConfigured: true,
      rejectedClientCertificate: closedByServer,
      time: sw.elapsed,
      pin: checkPin(tls, host, port, info, verified: trusted, record: false),
    );
  } finally {
    await session.close();
  }
}

/// Whether [socket] ends (an error or a close) within [settle]; the socket is
/// left for the caller to destroy. The flag is read before returning because
/// `destroy()` ends the listener too.
Future<bool> _closedWithin(Socket socket, Duration settle) async {
  var closed = false;
  final done = Completer<void>();
  void end() {
    closed = true;
    if (!done.isCompleted) done.complete();
  }

  socket.listen(
    (_) {},
    onError: (Object e) => end(),
    onDone: end,
    cancelOnError: true,
  );
  await done.future.timeout(settle, onTimeout: () {});
  return closed;
}
