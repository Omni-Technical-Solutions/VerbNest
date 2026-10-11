import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'session.dart';

/// The app language; null follows the system.
///
/// A saved language the app no longer ships (Arabic was removed in v0.58.0) is
/// ignored, so a workspace that had it selected opens in English instead of
/// failing. The saved value is left alone.
class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() {
    final code = ref.read(repositoryProvider).settings['language'];
    if (code is! String || code.isEmpty) return null;
    final shipped = AppLocalizations.supportedLocales.any(
      (l) => l.languageCode == code,
    );
    return shipped ? Locale(code) : null;
  }

  void set(Locale? locale) {
    final repo = ref.read(repositoryProvider);
    final next = {...repo.settings};
    if (locale == null) {
      next.remove('language');
    } else {
      next['language'] = locale.languageCode;
    }
    repo.settings = next;
    state = locale;
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(
  LocaleNotifier.new,
);
