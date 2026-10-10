import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the app's bundled fonts (Inter and JetBrains Mono from
/// `assets/fonts`) and the Material icon font (from `test/fonts`), so goldens
/// show real text and icons instead of Ahem boxes. The machine's own fonts are
/// never used, so the result does not depend on it.
Future<void> loadGoldenFonts() async {
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());

  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(bytes('assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
  final mono = FontLoader('JetBrains Mono');
  for (final f in ['Regular', 'Bold']) {
    mono.addFont(bytes('assets/fonts/JetBrainsMono-$f.ttf'));
  }
  await mono.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('test/fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

/// Compares goldens with a small tolerance. Text anti-aliasing differs a
/// little between macOS and Linux, and the goldens are made on one and checked
/// on the other. A real layout or colour change moves far more than 0.5%.
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile, {this.tolerance = 0.005});

  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

/// Call from `setUpAll` in a golden test file.
void useTolerantGoldens(String testFile) {
  goldenFileComparator = TolerantGoldenComparator(Uri.parse(testFile));
}
