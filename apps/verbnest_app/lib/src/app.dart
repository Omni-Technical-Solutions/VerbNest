import '../l10n/app_localizations.dart';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'adaptive_scaffold.dart';
import 'state/locale_state.dart';
import 'state/prefs.dart';
import 'state/theme_state.dart';
import 'theme.dart';

class VerbnestApp extends ConsumerWidget {
  const VerbnestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    final seed = AppAccents.seed(prefs.accent);
    Widget app(ColorScheme? light, ColorScheme? dark) => MaterialApp(
      title: 'VerbNest',
      // The package's delegates cover Material, Cupertino and widgets; the
      // generated list names the old flutter_localizations ones.
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: ref.watch(localeProvider),
      debugShowCheckedModeBanner: false,
      theme: buildTheme(
        Brightness.light,
        seed: seed,
        compact: prefs.compact,
        dynamicScheme: light,
      ),
      darkTheme: buildTheme(
        Brightness.dark,
        seed: seed,
        compact: prefs.compact,
        dynamicScheme: dark,
      ),
      themeMode: ref.watch(themeModeProvider),
      // On top of the system text size, not instead of it.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scale = prefs.fontScale;
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // Edge to edge: the app draws behind the system navigation bar, so
          // it is transparent and its icons follow the theme.
          value: SystemUiOverlayStyle(
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
            systemNavigationBarIconBrightness: dark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale),
            ),
            child: child!,
          ),
        );
      },
      home: const AdaptiveScaffold(),
    );
    // Material You is Android only. The builder always wraps the app there and
    // the setting only decides whether its colours are used: adding or removing
    // the wrapper when the switch flips would rebuild the whole app and send you
    // back to the first screen. Where the system offers no colours the builder
    // gives null and the accent colour is used.
    if (defaultTargetPlatform == TargetPlatform.android) {
      return DynamicColorBuilder(
        builder: (light, dark) =>
            prefs.dynamicColor ? app(light, dark) : app(null, null),
      );
    }
    return app(null, null);
  }
}
