import 'package:flutter/material.dart';

import 'theme/app_tokens.dart';

export 'theme/app_tokens.dart';

ThemeData buildTheme(
  Brightness brightness, {
  Color seed = const Color(0xFFFF6C37),
  bool compact = false,
}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.md),
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.md),
    borderSide: BorderSide(color: c, width: w),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: compact
        ? VisualDensity.compact
        : VisualDensity.adaptivePlatformDensity,
    extensions: [dark ? AppColors.dark : AppColors.light],
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: border(scheme.outlineVariant),
      enabledBorder: border(scheme.outlineVariant),
      focusedBorder: border(scheme.primary, 2),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: shape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: shape),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: shape),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
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
      indicatorShape: shape,
      indicatorColor: scheme.primaryContainer,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(Radii.sm),
    ),
  );
}
