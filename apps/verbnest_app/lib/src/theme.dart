import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';

import 'theme/app_tokens.dart';

export 'theme/app_tokens.dart';

ThemeData buildTheme(
  Brightness brightness, {
  Color? seed,
  bool compact = false,

  /// A scheme from the system (Material You). Used as is when given.
  ColorScheme? dynamicScheme,
}) {
  final dark = brightness == Brightness.dark;
  // `vibrant` keeps the orange orange; the default variant turns it brown and
  // `expressive` turns it purple.
  final scheme =
      dynamicScheme ??
      ColorScheme.fromSeed(
        seedColor: seed ?? AppAccents.seed(0),
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
      );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.md),
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.md),
    borderSide: BorderSide(color: c, width: w),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: kUiFamily,
    colorScheme: scheme,
    visualDensity: compact
        ? VisualDensity.compact
        : VisualDensity.adaptivePlatformDensity,
    extensions: [dark ? AppColors.dark : AppColors.light],
    // Android's predictive back gesture previews the page underneath. Every
    // platform is listed: a platform missing from the map falls back to the
    // zoom transition, which would take away iOS swipe-back.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
      },
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: border(scheme.outlineVariant),
      enabledBorder: border(scheme.outlineVariant),
      focusedBorder: border(scheme.primary, 2),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 2),
    ),
    // Buttons keep the Material 3 default (fully rounded).
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: shape,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(shape: shape),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: scheme.outlineVariant,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    listTileTheme: ListTileThemeData(
      shape: shape,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.secondaryContainer,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(Radii.sm),
    ),
  );
}
