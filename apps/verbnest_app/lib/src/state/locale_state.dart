import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session.dart';

/// The app language; null follows the system.
class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() {
    final code = ref.read(repositoryProvider).settings['language'];
    return code is String && code.isNotEmpty ? Locale(code) : null;
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
