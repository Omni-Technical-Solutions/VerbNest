import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a URL in the system browser (OAuth 2.0 sign-in). Replaceable in
/// tests.
typedef BrowserOpener = Future<void> Function(Uri url);

final browserOpenerProvider = Provider<BrowserOpener>(
  (ref) => (url) async {
    // The sign-in URL comes from request settings that can arrive in an
    // imported collection, so never hand other schemes (file:, custom app
    // links) to the operating system.
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw StateError('only http and https links can be opened');
    }
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) throw StateError('no browser available');
  },
);
