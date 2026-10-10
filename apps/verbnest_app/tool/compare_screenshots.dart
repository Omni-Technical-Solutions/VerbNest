// Compares two folders of screenshots and lists the ones that changed.
//
// Usage: dart run tool/compare_screenshots.dart <baseline-dir> <new-dir>
//        [--tolerance=0.5]
//
// A screenshot counts as changed when its size differs or more than the
// tolerance (percent of pixels) differs by more than a few levels per channel,
// which absorbs anti-aliasing noise. Exit code 0 when nothing changed, 1 when
// something did, 2 on a usage error. Used by scripts/compare_screenshots.sh.
import 'dart:io';

import 'package:image/image.dart' as img;

/// Result of comparing one pair of images.
class ShotDiff {
  const ShotDiff(this.name, this.status, [this.percent = 0]);

  final String name;

  /// `same`, `changed`, `resized`, `new` or `missing`.
  final String status;

  /// Share of pixels that differ, 0 to 100.
  final double percent;

  bool get isChange => status != 'same';
}

/// Share of pixels (0 to 100) whose channels differ by more than [slack].
double pixelDifference(img.Image a, img.Image b, {int slack = 8}) {
  var different = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final p = a.getPixel(x, y), q = b.getPixel(x, y);
      if ((p.r - q.r).abs() > slack ||
          (p.g - q.g).abs() > slack ||
          (p.b - q.b).abs() > slack) {
        different++;
      }
    }
  }
  return 100 * different / (a.width * a.height);
}

List<ShotDiff> compareFolders(
  Directory baseline,
  Directory fresh, {
  double tolerance = 0.5,
}) {
  List<String> pngs(Directory d) => d.existsSync()
      ? [
          for (final f in d.listSync())
            if (f is File && f.path.toLowerCase().endsWith('.png'))
              f.uri.pathSegments.last,
        ]
      : <String>[];
  final names = {...pngs(baseline), ...pngs(fresh)}.toList()..sort();
  final out = <ShotDiff>[];
  for (final n in names) {
    final a = File('${baseline.path}/$n'), b = File('${fresh.path}/$n');
    if (!a.existsSync()) {
      out.add(ShotDiff(n, 'new'));
    } else if (!b.existsSync()) {
      out.add(ShotDiff(n, 'missing'));
    } else {
      final x = img.decodePng(a.readAsBytesSync());
      final y = img.decodePng(b.readAsBytesSync());
      if (x == null || y == null) {
        out.add(ShotDiff(n, 'changed', 100));
      } else if (x.width != y.width || x.height != y.height) {
        out.add(ShotDiff(n, 'resized', 100));
      } else {
        final p = pixelDifference(x, y);
        out.add(ShotDiff(n, p > tolerance ? 'changed' : 'same', p));
      }
    }
  }
  return out;
}

int main(List<String> args) {
  final paths = [
    for (final a in args)
      if (!a.startsWith('--')) a,
  ];
  final tol = args
      .where((a) => a.startsWith('--tolerance='))
      .map((a) => double.tryParse(a.substring(12)))
      .firstOrNull;
  if (paths.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/compare_screenshots.dart <baseline> <new> '
      '[--tolerance=0.5]',
    );
    return 2;
  }
  final results = compareFolders(
    Directory(paths[0]),
    Directory(paths[1]),
    tolerance: tol ?? 0.5,
  );
  var changed = 0;
  for (final r in results) {
    if (r.isChange) changed++;
    final detail = r.status == 'changed'
        ? ' (${r.percent.toStringAsFixed(1)}% of pixels)'
        : '';
    stdout.writeln('${r.status.padRight(8)} ${r.name}$detail');
  }
  stdout.writeln(
    changed == 0
        ? 'No screenshots changed (${results.length} compared).'
        : '$changed of ${results.length} screenshots changed.',
  );
  return changed == 0 ? 0 : 1;
}
