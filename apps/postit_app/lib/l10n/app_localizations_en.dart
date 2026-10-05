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
}
