import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_http/verbnest_http.dart';

import 'network_state.dart';
import 'session.dart';

/// Workspace-wide HTTP defaults (FR-HTTP-007), stored in the workspace
/// settings so they travel with it.
class HttpDefaultsNotifier extends Notifier<HttpSettings> {
  @override
  HttpSettings build() {
    final s = ref.read(repositoryProvider).settings;
    const d = HttpSettings();
    final net = ref.watch(networkProvider);
    return HttpSettings(
      proxy: net.proxy,
      useSystemProxy: net.useSystemProxy,
      tls: net.tls,
      timeout: Duration(
        milliseconds: s['timeoutMs'] as int? ?? d.timeout.inMilliseconds,
      ),
      verifyTls: s['verifyTls'] as bool? ?? d.verifyTls,
      followRedirects: s['followRedirects'] as bool? ?? d.followRedirects,
      maxRedirects: s['maxRedirects'] as int? ?? d.maxRedirects,
    );
  }

  void update({Duration? timeout, bool? verifyTls, bool? followRedirects}) {
    final next = HttpSettings(
      proxy: state.proxy,
      useSystemProxy: state.useSystemProxy,
      tls: state.tls,
      timeout: timeout ?? state.timeout,
      verifyTls: verifyTls ?? state.verifyTls,
      followRedirects: followRedirects ?? state.followRedirects,
      maxRedirects: state.maxRedirects,
    );
    final repo = ref.read(repositoryProvider);
    repo.settings = {
      ...repo.settings,
      'timeoutMs': next.timeout.inMilliseconds,
      'verifyTls': next.verifyTls,
      'followRedirects': next.followRedirects,
      'maxRedirects': next.maxRedirects,
    };
    state = next;
  }
}

final httpDefaultsProvider =
    NotifierProvider<HttpDefaultsNotifier, HttpSettings>(
      HttpDefaultsNotifier.new,
    );

/// Whether sending with undefined `{{variables}}` asks first (FR-VAR-006).
class WarnUnresolvedNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(repositoryProvider).settings['warnUnresolved'] as bool? ?? true;

  void set(bool value) {
    final repo = ref.read(repositoryProvider);
    repo.settings = {...repo.settings, 'warnUnresolved': value};
    state = value;
  }
}

final warnUnresolvedProvider = NotifierProvider<WarnUnresolvedNotifier, bool>(
  WarnUnresolvedNotifier.new,
);
