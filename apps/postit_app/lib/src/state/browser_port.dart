import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a URL in the system browser (OAuth 2.0 sign-in). Replaceable in
/// tests.
typedef BrowserOpener = Future<void> Function(Uri url);

final browserOpenerProvider = Provider<BrowserOpener>(
  (ref) => (url) async {
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) throw StateError('no browser available');
  },
);
