import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../tool/compare_screenshots.dart';

void main() {
  late Directory base, fresh;

  setUp(() {
    base = Directory.systemTemp.createTempSync('shots-base');
    fresh = Directory.systemTemp.createTempSync('shots-new');
    addTearDown(() {
      base.deleteSync(recursive: true);
      fresh.deleteSync(recursive: true);
    });
  });

  void write(
    Directory d,
    String name,
    int w,
    int h, {
    int color = 0xffffff,
    int dots = 0,
  }) {
    final image = img.Image(width: w, height: h);
    img.fill(
      image,
      color: img.ColorRgb8(
        (color >> 16) & 255,
        (color >> 8) & 255,
        color & 255,
      ),
    );
    // Paint [dots] black pixels so the images can differ by a known amount.
    for (var i = 0; i < dots; i++) {
      image.setPixelRgb(i % w, i ~/ w, 0, 0, 0);
    }
    File('${d.path}/$name').writeAsBytesSync(img.encodePng(image));
  }

  Map<String, ShotDiff> run({double tolerance = 0.5}) => {
    for (final r in compareFolders(base, fresh, tolerance: tolerance))
      r.name: r,
  };

  test('identical images are the same', () {
    write(base, 'a.png', 100, 100);
    write(fresh, 'a.png', 100, 100);
    expect(run()['a.png']!.status, 'same');
  });

  test('a visible difference is reported with its size', () {
    write(base, 'a.png', 100, 100);
    write(fresh, 'a.png', 100, 100, dots: 500); // 5% of the pixels
    final r = run()['a.png']!;
    expect(r.status, 'changed');
    expect(r.percent, closeTo(5, 0.01));
  });

  test('a difference under the tolerance is noise', () {
    write(base, 'a.png', 100, 100);
    write(fresh, 'a.png', 100, 100, dots: 20); // 0.2%
    expect(run()['a.png']!.status, 'same');
    expect(run(tolerance: 0.1)['a.png']!.status, 'changed');
  });

  test('tiny colour differences are ignored, large ones are not', () {
    write(base, 'a.png', 50, 50, color: 0x808080);
    write(fresh, 'a.png', 50, 50, color: 0x848484);
    expect(run()['a.png']!.status, 'same');
    write(fresh, 'a.png', 50, 50, color: 0xa0a0a0);
    expect(run()['a.png']!.status, 'changed');
  });

  test('size changes, new and missing files are reported', () {
    write(base, 'size.png', 100, 100);
    write(fresh, 'size.png', 100, 120);
    write(base, 'gone.png', 10, 10);
    write(fresh, 'added.png', 10, 10);
    final r = run();
    expect(r['size.png']!.status, 'resized');
    expect(r['gone.png']!.status, 'missing');
    expect(r['added.png']!.status, 'new');
    expect(r.values.every((d) => d.isChange), isTrue);
  });

  test('only png files are compared', () {
    File('${base.path}/notes.txt').writeAsStringSync('x');
    expect(run(), isEmpty);
  });
}
