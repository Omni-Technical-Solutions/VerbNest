import 'package:material_ui/material_ui.dart';

/// Spacing, radii and motion timings shared by every screen.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// Material 3 shape scale (extra small 4, small 8, medium 12, large 16, extra
/// large 28), so every corner in the app is one of these steps.
abstract final class Radii {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 28;
}

abstract final class Motion {
  // Material 3 motion tokens: short for small state changes, medium for
  // elements entering or leaving, with the standard easing.
  static const fast = Durations.short3;
  static const base = Durations.medium1;
  static const slow = Durations.medium3;
  static const curve = Easing.standard;

  /// Zero when the platform asks for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}

/// Family of the UI text. Bundled (`assets/fonts`), so it is the same on every
/// platform; a script it lacks falls back to the system font.
const kUiFamily = 'Inter';

/// Font family for code, headers and URLs. Bundled.
const kMonoFamily = 'JetBrains Mono';

/// Used for a character the bundled mono font does not have, then the generic
/// `monospace` so there is always a match.
const kMonoFallback = ['SF Mono', 'Menlo', 'Consolas', 'monospace'];

/// Digits of equal width, so timings and sizes do not jitter as they change.
const kTabularFigures = [FontFeature.tabularFigures()];

/// Fixed-width text style for code, headers and URLs.
///
/// The code viewer sizes its columns from this family, so change both
/// together.
TextStyle monoStyle({double? fontSize, Color? color, FontWeight? weight}) =>
    TextStyle(
      fontFamily: kMonoFamily,
      fontFamilyFallback: kMonoFallback,
      fontSize: fontSize,
      color: color,
      fontWeight: weight,
    );

/// Meaning-based colours (HTTP methods, status classes, outcomes) that
/// follow the light or dark theme instead of fixed swatches.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.get,
    required this.post,
    required this.put,
    required this.patch,
    required this.delete,
    required this.otherMethod,
    required this.success,
    required this.info,
    required this.warning,
    required this.danger,
    required this.favourite,
    required this.synString,
    required this.synNumber,
    required this.synLiteral,
    required this.searchMark,
    required this.onSearchMark,
  });

  final Color get;
  final Color post;
  final Color put;
  final Color patch;
  final Color delete;
  final Color otherMethod;
  final Color success;
  final Color info;
  final Color warning;
  final Color danger;
  final Color favourite;
  final Color synString;
  final Color synNumber;
  final Color synLiteral;
  final Color searchMark;
  final Color onSearchMark;

  static const light = AppColors(
    get: Color(0xFF2E7D32),
    post: Color(0xFFB04F00),
    put: Color(0xFF1565C0),
    patch: Color(0xFF8E24AA),
    delete: Color(0xFFC62828),
    otherMethod: Color(0xFF616161),
    success: Color(0xFF2E7D32),
    info: Color(0xFF1565C0),
    warning: Color(0xFFB04F00),
    danger: Color(0xFFC62828),
    favourite: Color(0xFFF9A825),
    synString: Color(0xFF2E7D32),
    synNumber: Color(0xFFB04F00),
    synLiteral: Color(0xFF8E24AA),
    searchMark: Color(0xFFFFE082),
    onSearchMark: Colors.black,
  );

  static const dark = AppColors(
    get: Color(0xFF81C784),
    post: Color(0xFFFFB74D),
    put: Color(0xFF64B5F6),
    patch: Color(0xFFCE93D8),
    delete: Color(0xFFEF9A9A),
    otherMethod: Color(0xFFBDBDBD),
    success: Color(0xFF81C784),
    info: Color(0xFF64B5F6),
    warning: Color(0xFFFFB74D),
    danger: Color(0xFFEF9A9A),
    favourite: Color(0xFFFFCA28),
    synString: Color(0xFF81C784),
    synNumber: Color(0xFFFFB74D),
    synLiteral: Color(0xFFCE93D8),
    searchMark: Color(0xFFFFE082),
    onSearchMark: Colors.black,
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  Color method(String m) => switch (m.toUpperCase()) {
    'GET' => get,
    'POST' => post,
    'PUT' => put,
    'PATCH' => patch,
    'DELETE' => delete,
    _ => otherMethod,
  };

  Color status(int code) {
    if (code >= 500) return danger;
    if (code >= 400) return warning;
    if (code >= 300) return info;
    return success;
  }

  @override
  AppColors copyWith({Color? get, Color? post, Color? put, Color? patch}) =>
      AppColors(
        get: get ?? this.get,
        post: post ?? this.post,
        put: put ?? this.put,
        patch: patch ?? this.patch,
        delete: delete,
        otherMethod: otherMethod,
        success: success,
        info: info,
        warning: warning,
        danger: danger,
        favourite: favourite,
        synString: synString,
        synNumber: synNumber,
        synLiteral: synLiteral,
        searchMark: searchMark,
        onSearchMark: onSearchMark,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      get: l(get, other.get),
      post: l(post, other.post),
      put: l(put, other.put),
      patch: l(patch, other.patch),
      delete: l(delete, other.delete),
      otherMethod: l(otherMethod, other.otherMethod),
      success: l(success, other.success),
      info: l(info, other.info),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      favourite: l(favourite, other.favourite),
      synString: l(synString, other.synString),
      synNumber: l(synNumber, other.synNumber),
      synLiteral: l(synLiteral, other.synLiteral),
      searchMark: l(searchMark, other.searchMark),
      onSearchMark: l(onSearchMark, other.onSearchMark),
    );
  }
}

/// Accent colours the user can pick; the theme is generated from the seed.
abstract final class AppAccents {
  static const seeds = <Color>[
    // The icon's orange; the first accent and the default.
    Color(0xFFEB6A1A),
    Color(0xFF2979FF),
    Color(0xFF00BFA5),
    Color(0xFF7C4DFF),
    Color(0xFFE91E63),
    Color(0xFF43A047),
  ];

  static Color seed(int index) =>
      seeds[index >= 0 && index < seeds.length ? index : 0];
}
