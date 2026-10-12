import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:verbnest_app/src/theme.dart';

double _lum(Color c) {
  double f(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  group('colour', () {
    for (final b in Brightness.values) {
      for (var i = 0; i < AppAccents.seeds.length; i++) {
        test('accent $i ${b.name}: text roles meet WCAG AA', () {
          final s = buildTheme(b, seed: AppAccents.seed(i)).colorScheme;
          expect(_contrast(s.primary, s.onPrimary), greaterThanOrEqualTo(4.5));
          expect(
            _contrast(s.primaryContainer, s.onPrimaryContainer),
            greaterThanOrEqualTo(4.5),
          );
          expect(_contrast(s.surface, s.onSurface), greaterThanOrEqualTo(4.5));
          // Primary is used for links, tab labels and the Send button text.
          expect(_contrast(s.surface, s.primary), greaterThanOrEqualTo(4.5));
        });
      }

      test('${b.name}: method and status colours are readable on surface', () {
        final t = buildTheme(b);
        final s = t.colorScheme;
        final c = t.extension<AppColors>()!;
        for (final m in ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OTHER']) {
          expect(
            _contrast(s.surface, c.method(m)),
            greaterThanOrEqualTo(4.5),
            reason: '$m on ${b.name}',
          );
        }
        for (final status in [200, 301, 404, 500]) {
          expect(
            _contrast(s.surface, c.status(status)),
            greaterThanOrEqualTo(4.5),
            reason: '$status on ${b.name}',
          );
        }
      });
    }

    test('the default accent is orange, not brown or purple', () {
      final hsl = HSLColor.fromColor(
        buildTheme(Brightness.light).colorScheme.primary,
      );
      expect(hsl.hue, inInclusiveRange(10, 40));
      expect(hsl.saturation, greaterThan(0.7));
    });
  });

  group('shape and motion', () {
    test('radii are steps of the Material 3 shape scale', () {
      expect(
        [Radii.xs, Radii.sm, Radii.md, Radii.lg, Radii.xl],
        [4, 8, 12, 16, 28],
      );
    });

    test('motion uses the Material 3 duration and easing tokens', () {
      expect(Motion.fast, Durations.short3);
      expect(Motion.base, Durations.medium1);
      expect(Motion.slow, Durations.medium3);
      expect(Motion.curve, Easing.standard);
    });

    test('dialogs use the extra-large corner', () {
      final shape =
          buildTheme(Brightness.light).dialogTheme.shape!
              as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(Radii.xl));
    });
  });

  test('no hard-coded colours outside the token files', () {
    // Meaning-based colours live in AppColors; everything else comes from the
    // colour scheme. `Colors.transparent` is the one allowed constant.
    final literal = RegExp(r'Color\(0x|(?<![A-Za-z])Colors\.(?!transparent)');
    const allowed = {'lib/src/theme/app_tokens.dart'};
    final offenders = <String>[];
    for (final f in Directory('lib/src').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/'); // Windows separators
      if (allowed.contains(path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (literal.hasMatch(lines[i])) offenders.add('$path:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });
}
