import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/theme_controller.dart';
import 'package:music_database_app/src/widgets/cover_filters.dart';

/// [width]×[height] RGBA, each pixel from [color] (x, y) → (r, g, b).
Uint8List _image(
  int width,
  int height,
  (int, int, int) Function(int, int) color,
) {
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final (r, g, b) = color(x, y);
      final i = (y * width + x) * 4;
      out
        ..[i] = r
        ..[i + 1] = g
        ..[i + 2] = b
        ..[i + 3] = 255;
    }
  }
  return out;
}

void main() {
  test(
    'Lain crops a 16:9 frame to its middle square and turns red blue-green',
    () {
      final red = _image(32, 18, (_, _) => (220, 40, 40));
      final out = lainFilter(red, 32, 18, 1);
      expect(out.side, 18);
      var r = 0, g = 0, b = 0;
      for (var i = 0; i < out.rgba.length; i += 4) {
        r += out.rgba[i];
        g += out.rgba[i + 1];
        b += out.rgba[i + 2];
      }
      expect(b, greaterThan(r));
      expect(g, greaterThan(r));
    },
  );

  test('Lain grain is the same every time for one cover', () {
    final grey = _image(16, 16, (_, _) => (128, 128, 128));
    expect(lainFilter(grey, 16, 16, 5).rgba, lainFilter(grey, 16, 16, 5).rgba);
  });

  test(
    'Monochromatic uses only its colour, and shades are how many dots are lit',
    () {
      // Left half dark, right half light.
      final src = _image(
        16,
        16,
        (x, _) => x < 8 ? (30, 30, 30) : (230, 230, 230),
      );
      final out = monochromeFilter(src, 16, 16, 1, 0xFF33FF66);
      expect(out.side, 16);
      var litLeft = 0, litRight = 0;
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          final i = (y * 16 + x) * 4;
          final (r, g, b) = (out.rgba[i], out.rgba[i + 1], out.rgba[i + 2]);
          // Every pixel is the colour at some brightness: same proportions.
          expect(g, greaterThanOrEqualTo(r));
          expect(g, greaterThanOrEqualTo(b));
          if (g == 0xFF) x < 8 ? litLeft++ : litRight++;
        }
      }
      expect(litRight, greaterThan(litLeft * 4));
    },
  );

  test('a Monochromatic dot is a dot×dot block of the cover', () {
    final src = _image(31, 31, (_, _) => (255, 255, 255));
    // 10 dots of 3 px; the odd pixel left over is cropped.
    expect(monochromeFilter(src, 31, 31, 3, 0xFFFFFFFF).side, 30);
  });

  test('intensity 0 leaves the cover as it is, in between mixes', () {
    final src = _image(12, 12, (x, y) => (200, x * 20, y * 20));
    expect(lainFilter(src, 12, 12, 3, strength: 0).rgba, src);
    expect(monochromeFilter(src, 12, 12, 2, 0xFF33FF66, strength: 0).rgba, src);
    final full = lainFilter(src, 12, 12, 3).rgba;
    final half = lainFilter(src, 12, 12, 3, strength: 0.5).rgba;
    // Red is mostly gone from Lain; halfway keeps about half of it.
    expect(half[0], closeTo((src[0] + full[0]) / 2, 1));
  });

  test('equal settings make equal images, with a key ready at once', () {
    final file = FileImage(File('/c/a.img'));
    FilteredImage make({int size = 100}) =>
        FilteredImage(file, filter: CoverFilter.lain, size: size, seed: 1);
    expect(make(), make());
    expect(make().hashCode, make().hashCode);
    expect(make(), isNot(make(size: 200)));
    expect(
      make(),
      isNot(
        FilteredImage(
          file,
          filter: CoverFilter.lain,
          size: 100,
          seed: 1,
          strength: 0.5,
        ),
      ),
    );
    FilteredImageKey? key;
    make().obtainKey(ImageConfiguration.empty).then((k) => key = k);
    // Synchronously: the cached image can be drawn in the same frame.
    expect(key, isNotNull);
  });

  test('Monochromatic unlit dots take the background colour', () {
    final black = _image(8, 8, (_, _) => (0, 0, 0));
    final out = monochromeFilter(
      black,
      8,
      8,
      1,
      0xFF0F380F,
      backgroundArgb: 0xFF9BBC0F,
    );
    expect(out.rgba.sublist(0, 3), [0x9B, 0xBC, 0x0F]);
    final file = FileImage(File('/c/a.img'));
    expect(
      FilteredImage(file, filter: CoverFilter.monochrome, size: 8),
      isNot(
        FilteredImage(
          file,
          filter: CoverFilter.monochrome,
          size: 8,
          background: const Color(0xFF9BBC0F),
        ),
      ),
    );
  });
}
