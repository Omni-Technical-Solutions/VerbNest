import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_runner/verbnest_runner.dart';

import 'file_port.dart';
import 'session.dart';

// The model and its storage live in verbnest_runner so the command line reads
// the same data; they are re-exported for the rest of the app.
export 'package:verbnest_runner/verbnest_runner.dart'
    show CaEntry, ClientCertEntry, NetworkConfig, NetworkConfigStore;

class NetworkNotifier extends Notifier<NetworkConfig> {
  NetworkConfigStore get _store {
    final s = ref.read(sessionProvider);
    return NetworkConfigStore(s.local, s.secrets, s.repo.workspaceId);
  }

  @override
  NetworkConfig build() => _store.read();

  void set(NetworkConfig next) {
    _store.write(next);
    state = next;
  }

  void update(NetworkConfig Function(NetworkConfig c) f) => set(f(state));

  /// Reads a CA file the user picks. Returns the error to show, or null.
  Future<String?> addCa(FilePort files) async {
    final f = await files.pick();
    if (f == null) return null;
    if (!_looksLikeCertificate(f.bytes)) {
      return '${f.name} is not a PEM or DER certificate';
    }
    update((c) => c.copyWith(cas: [...c.cas, CaEntry(f.name, f.bytes)]));
    return null;
  }

  /// Replaces the pin for [pin]'s host (or adds it).
  void putPin(PinEntry pin) => update(
    (c) => c.copyWith(
      pins: [
        for (final e in c.pins)
          if (e.host != pin.host || e.port != pin.port) e,
        pin,
      ],
    ),
  );

  void removePin(PinEntry pin) => update(
    (c) => c.copyWith(
      pins: [
        for (final e in c.pins)
          if (e.host != pin.host || e.port != pin.port) e,
      ],
    ),
  );

  void setPinByDefault(bool on) => update((c) => c.copyWith(pinByDefault: on));

  void setMinTls(TlsVersion? v) =>
      update((c) => c.copyWith(minTls: v, clearMinTls: v == null));

  void removeCa(int index) =>
      update((c) => c.copyWith(cas: [...c.cas]..removeAt(index)));

  void removeClientCert(String id) => update(
    (c) => c.copyWith(
      clientCerts: c.clientCerts.where((e) => e.id != id).toList(),
    ),
  );

  /// Adds a client certificate. For PKCS#12 pass only [certificate].
  void addClientCert({
    required String pattern,
    required String name,
    required Uint8List certificate,
    Uint8List? privateKey,
    String passphrase = '',
  }) => update(
    (c) => c.copyWith(
      clientCerts: [
        ...c.clientCerts,
        ClientCertEntry(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
          pattern: pattern.trim().isEmpty ? '*' : pattern.trim(),
          name: name,
          certificate: certificate,
          privateKey: privateKey,
          passphrase: passphrase,
        ),
      ],
    ),
  );
}

/// Replaces the entry with [entry]'s id (the edit dialog's save).
extension NetworkEdits on NetworkNotifier {
  void replaceClientCert(ClientCertEntry entry) => update(
    (c) => c.copyWith(
      clientCerts: [
        for (final e in c.clientCerts)
          if (e.id == entry.id) entry else e,
      ],
    ),
  );

  void setClientCertEnabled(String id, bool enabled) => update(
    (c) => c.copyWith(
      clientCerts: [
        for (final e in c.clientCerts)
          if (e.id == id) e.copyWith(enabled: enabled) else e,
      ],
    ),
  );

  /// "Send no client certificate to [pattern]": beats a broader entry.
  void addNoClientCert(String pattern) => update(
    (c) => c.copyWith(
      clientCerts: [
        ...c.clientCerts,
        ClientCertEntry(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
          pattern: pattern.trim().isEmpty ? '*' : pattern.trim(),
          name: 'No client certificate',
          certificate: Uint8List(0),
          none: true,
        ),
      ],
    ),
  );
}

/// What a saved PEM client certificate says about itself, or null for a
/// PKCS#12 bundle (its contents need the passphrase and the TLS library does
/// not expose them) and for anything unreadable.
CertInfo? clientCertInfo(ClientCertEntry entry) {
  if (entry.none || entry.privateKey == null) return null;
  try {
    return parseCertificate(entry.certificate);
  } on CertFormatException {
    return null;
  }
}

bool _looksLikeCertificate(Uint8List b) {
  final head = latin1.decode(b.take(64).toList(), allowInvalid: true);
  return head.contains('-----BEGIN') || (b.isNotEmpty && b.first == 0x30);
}

final networkProvider = NotifierProvider<NetworkNotifier, NetworkConfig>(
  NetworkNotifier.new,
);

/// The cookie jar shared by every request in the open workspace (FR-HTTP-011).
/// The state is the cookie list so views rebuild when it changes.
class CookiesNotifier extends Notifier<List<StoredCookie>> {
  late final CookieJar jar;

  @override
  List<StoredCookie> build() {
    final s = ref.read(sessionProvider);
    final ws = s.repo.workspaceId;
    final raw = s.local.kv(ws, 'cookies');
    var loaded = CookieJar();
    if (raw != null) {
      try {
        loaded = CookieJar.fromJson(jsonDecode(raw));
      } on Object {
        // A damaged jar is dropped rather than blocking sends.
      }
    }
    jar = loaded;
    final now = DateTime.now();
    for (final c in jar.cookies.where((c) => c.isExpired(now))) {
      jar.remove(c);
    }
    jar.onChanged = () {
      s.local.setKv(ws, 'cookies', jsonEncode(jar.toJson()));
      state = jar.cookies;
    };
    return jar.cookies;
  }

  void remove(StoredCookie c) => jar.remove(c);

  void removeDomain(String domain) => jar.removeDomain(domain);

  void clear() => jar.clear();
}

final cookiesProvider = NotifierProvider<CookiesNotifier, List<StoredCookie>>(
  CookiesNotifier.new,
);
