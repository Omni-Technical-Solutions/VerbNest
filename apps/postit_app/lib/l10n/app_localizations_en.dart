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
}
