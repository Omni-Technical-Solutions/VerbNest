import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session.dart';

/// Light / dark / system, remembered in the workspace settings (FR-APP-004).
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final name = ref.read(repositoryProvider).settings['themeMode'];
    return ThemeMode.values.where((m) => m.name == name).firstOrNull ??
        ThemeMode.system;
  }

  void set(ThemeMode mode) {
    final repo = ref.read(repositoryProvider);
    repo.settings = {...repo.settings, 'themeMode': mode.name};
    state = mode;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
