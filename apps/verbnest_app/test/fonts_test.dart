import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/theme.dart';
import 'package:yaml/yaml.dart';

void main() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;

  Map<String, List<String>> families() {
    final fonts = (pubspec['flutter'] as YamlMap)['fonts'] as YamlList;
    return {
      for (final f in fonts)
        (f as YamlMap)['family'] as String: [
          for (final x in f['fonts'] as YamlList)
            (x as YamlMap)['asset'] as String,
        ],
    };
  }

  test('Inter and JetBrains Mono are declared and their files exist', () {
    final f = families();
    expect(f.keys, containsAll(['Inter', 'JetBrains Mono']));
    expect(f['Inter'], hasLength(4));
    expect(f['JetBrains Mono'], hasLength(2));
    for (final asset in [...f['Inter']!, ...f['JetBrains Mono']!]) {
      final file = File(asset);
      expect(file.existsSync(), isTrue, reason: asset);
      // A TrueType file starts with 0x00010000.
      expect(file.readAsBytesSync().sublist(0, 4), [0, 1, 0, 0], reason: asset);
    }
  });

  test('both licences ship with the fonts and are bundled as assets', () {
    final assets = [
      for (final a in (pubspec['flutter'] as YamlMap)['assets'] as YamlList)
        '$a',
    ];
    for (final licence in [
      'assets/fonts/Inter-LICENSE.txt',
      'assets/fonts/JetBrainsMono-OFL.txt',
    ]) {
      expect(assets, contains(licence));
      expect(
        File(licence).readAsStringSync(),
        contains('SIL Open Font License'),
      );
    }
  });

  test('the theme uses Inter and code uses JetBrains Mono', () {
    expect(
      buildTheme(Brightness.light).textTheme.bodyMedium?.fontFamily,
      'Inter',
    );
    expect(
      buildTheme(Brightness.dark).textTheme.titleMedium?.fontFamily,
      'Inter',
    );
    final mono = monoStyle();
    expect(mono.fontFamily, 'JetBrains Mono');
    expect(mono.fontFamilyFallback, contains('monospace'));
  });

  testWidgets('the font files and licences load from the asset bundle', (
    t,
  ) async {
    for (final a in [
      'assets/fonts/Inter-LICENSE.txt',
      'assets/fonts/JetBrainsMono-OFL.txt',
    ]) {
      expect(await rootBundle.loadString(a), isNotEmpty, reason: a);
    }
  });
}
