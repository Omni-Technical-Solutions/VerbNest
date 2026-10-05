import '../l10n/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'adaptive_scaffold.dart';
import 'state/locale_state.dart';
import 'state/prefs.dart';
import 'state/theme_state.dart';
import 'theme.dart';

class PostItApp extends ConsumerWidget {
  const PostItApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'PostIt',
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: ref.watch(localeProvider),
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      // On top of the system text size, not instead of it.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scale = ref.watch(prefsProvider).fontScale;
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale),
          ),
          child: child!,
        );
      },
      home: const AdaptiveScaffold(),
    );
  }
}
