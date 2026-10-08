import 'package:flutter/material.dart';

/// Spacing, radii and motion timings shared by every screen.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

abstract final class Radii {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;

  /// Zero when the platform asks for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}

/// Font family for code, headers and URLs. System-installed monospaced fonts
/// are preferred; the generic `monospace` last so there is always a match.
const kMonoFamily = 'monospace';

/// Preferred monospaced families, first available wins. No font is bundled,
/// so this only picks a nicer face when the machine already has one.
const kMonoFallback = ['JetBrains Mono', 'SF Mono', 'Menlo', 'Consolas'];

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
    post: Color(0xFFEF6C00),
    put: Color(0xFF1565C0),
    patch: Color(0xFF8E24AA),
    delete: Color(0xFFC62828),
    otherMethod: Color(0xFF616161),
    success: Color(0xFF2E7D32),
    info: Color(0xFF1565C0),
    warning: Color(0xFFEF6C00),
    danger: Color(0xFFC62828),
    favourite: Color(0xFFF9A825),
    synString: Color(0xFF2E7D32),
    synNumber: Color(0xFFEF6C00),
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
    Color(0xFFFF6C37),
    Color(0xFF2979FF),
    Color(0xFF00BFA5),
    Color(0xFF7C4DFF),
    Color(0xFFE91E63),
    Color(0xFF43A047),
  ];

  static Color seed(int index) =>
      seeds[index >= 0 && index < seeds.length ? index : 0];
}
