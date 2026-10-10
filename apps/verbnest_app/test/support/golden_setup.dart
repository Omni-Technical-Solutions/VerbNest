import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads Roboto and the Material icon font from `test/fonts`, so goldens show
/// real text and icons instead of Ahem boxes. The fonts are checked in so the
/// result does not depend on the machine (Roboto: Apache 2.0, see
/// `test/fonts/Roboto_LICENSE.txt`).
Future<void> loadGoldenFonts() async {
  Future<ByteData> bytes(String name) async =>
      ByteData.sublistView(await File('test/fonts/$name').readAsBytes());

  final roboto = FontLoader('Roboto')
    ..addFont(bytes('Roboto-Regular.ttf'))
    ..addFont(bytes('Roboto-Medium.ttf'))
    ..addFont(bytes('Roboto-Bold.ttf'));
  await roboto.load();
  // The code view asks for `monospace`; Roboto stands in so text is real.
  final mono = FontLoader('monospace')..addFont(bytes('Roboto-Regular.ttf'));
  await mono.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
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
