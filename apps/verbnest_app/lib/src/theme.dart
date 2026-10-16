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

  // No colour animation on a button, and no hover or press tint: Material fades
  // those in over 200 ms and offers no switch to turn that off. The keyboard
  // focus tint stays (it is how a keyboard user sees where they are).
  final still = ButtonStyle(
    animationDuration: Duration.zero,
    overlayColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? scheme.onSurface.withValues(alpha: 0.12)
          : Colors.transparent,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: kUiFamily,
    colorScheme: scheme,
    visualDensity: compact
        ? VisualDensity.compact
        : VisualDensity.adaptivePlatformDensity,
    extensions: [dark ? AppColors.dark : AppColors.light],
    // Pages swap at once on every platform. Every platform is listed: a
    // platform missing from the map falls back to the zoom transition.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _NoTransitions(),
        TargetPlatform.iOS: _NoTransitions(),
        TargetPlatform.macOS: _NoTransitions(),
        TargetPlatform.windows: _NoTransitions(),
        TargetPlatform.linux: _NoTransitions(),
        TargetPlatform.fuchsia: _NoTransitions(),
      },
    ),
    // No ripple, splash, hover or press tint on a press.
    splashFactory: NoSplash.splashFactory,
    hoverColor: Colors.transparent,
    highlightColor: Colors.transparent,
    // Buttons change colour at once, not over 200 ms.
    filledButtonTheme: FilledButtonThemeData(style: still),
    outlinedButtonTheme: OutlinedButtonThemeData(style: still),
    textButtonTheme: TextButtonThemeData(style: still),
    elevatedButtonTheme: ElevatedButtonThemeData(style: still),
    iconButtonTheme: IconButtonThemeData(style: still),
    segmentedButtonTheme: SegmentedButtonThemeData(style: still),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: border(scheme.outlineVariant),
      enabledBorder: border(scheme.outlineVariant),
      // The same as the unfocused outline: Material fades a changing outline
      // over 167 ms, and the caret already shows where the focus is.
      focusedBorder: border(scheme.outlineVariant),
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
      splashFactory: NoSplash.splashFactory,
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

/// A page change with no transition: the new page is simply there.
class _NoTransitions extends PageTransitionsBuilder {
  const _NoTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
