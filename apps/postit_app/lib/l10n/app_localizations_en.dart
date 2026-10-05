// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navCollections => 'Collections';

  @override
  String get navHistory => 'History';

  @override
  String get navEnvironments => 'Environments';

  @override
  String get navSettings => 'Settings';

  @override
  String get selectOrCreateRequest => 'Select or create a request';

  @override
  String get paletteHint => 'Type a command or request name';

  @override
  String get paletteNothing => 'Nothing matches';

  @override
  String get cmdNewRequest => 'New request';

  @override
  String get cmdSend => 'Send request';

  @override
  String get cmdSearch => 'Search workspace…';

  @override
  String get cmdToggleSidebar => 'Toggle sidebar';

  @override
  String get cmdCloseTab => 'Close tab';

  @override
  String cmdGoTo(String place) {
    return 'Go to $place';
  }

  @override
  String get closeTab => 'Close tab';

  @override
  String get language => 'Language';

  @override
  String get systemDefault => 'System default';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get secretsProtected => 'Secrets are kept in the system secret store';

  @override
  String get secretsUnprotected =>
      'Secrets are stored unencrypted on this device';

  @override
  String get secretsUnavailableHint =>
      'The system secret store is not available (on Linux, install and unlock a keyring service).';

  @override
  String get defaultTimeout => 'Default timeout (seconds)';

  @override
  String get verifyTls => 'Verify TLS certificates';

  @override
  String get verifyTlsHint => 'Turning this off is unsafe on public networks';

  @override
  String get warnUnresolved => 'Warn before sending with undefined variables';

  @override
  String get followRedirects => 'Follow redirects';

  @override
  String get appearanceSection => 'Appearance (this device)';

  @override
  String get historySection => 'History (this device)';

  @override
  String get historyBodies => 'Keep request and response bodies';

  @override
  String get historyBodiesHint => 'Off stores only URLs, headers and status';

  @override
  String get historyDays => 'Delete history older than (days, 0 = never)';

  @override
  String get historyMax => 'Keep at most this many entries';

  @override
  String get close => 'Close';

  @override
  String get rtConnect => 'Connect';

  @override
  String get rtConnecting => 'Connecting…';

  @override
  String get rtDisconnect => 'Disconnect';

  @override
  String get rtClear => 'Clear';

  @override
  String get rtMessageHint => 'Message';

  @override
  String get rtSendTooltip => 'Send message';

  @override
  String get mockTitle => 'Mock server';

  @override
  String get mockEmpty =>
      'No request here has a saved example. Save a response as an example first.';

  @override
  String get mockPort => 'Port';

  @override
  String get mockStart => 'Start';

  @override
  String get mockStop => 'Stop';

  @override
  String mockServing(String url) {
    return 'Serving on $url';
  }

  @override
  String get mockPortInvalid => 'Port must be 0-65535';

  @override
  String mockListenFailed(int port, String error) {
    return 'Cannot listen on port $port: $error';
  }

  @override
  String mockRouteSubtitle(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count examples',
      one: '1 example',
    );
    return '$name, $_temp0';
  }

  @override
  String get mockHeaderHint =>
      'Send an X-PostIt-Example header to pick an example by name.';
}
