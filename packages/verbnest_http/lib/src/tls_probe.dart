import 'dart:async';
import 'dart:io';

import 'cert_inspect.dart';
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
  var rejected = false;
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
    final done = Completer<void>();
    socket.listen(
      (_) {},
      onError: (Object e) {
        rejected = true;
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        rejected = true;
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    await done.future.timeout(settle, onTimeout: () {});
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
    );
  } finally {
    socket.destroy();
  }
}
