import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../theme_controller.dart';

/// Loads [provider] as a decoded image (the caller disposes it).
Future<ui.Image> loadUiImage(ImageProvider provider) {
  final stream = provider.resolve(ImageConfiguration.empty);
  final loaded = Completer<ui.Image>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      if (!loaded.isCompleted) loaded.complete(info.image.clone());
      info.dispose();
    },
    onError: (e, s) {
      stream.removeListener(listener);
      if (!loaded.isCompleted) loaded.completeError(e, s);
    },
  );
  stream.addListener(listener);
  return loaded.future;
}

/// [source] cropped to the middle square of [size]×[size] pixels with [filter] applied. The
/// pixel work runs in another isolate; the result sits in Flutter's image cache like any image.
@immutable
class FilteredImage extends ImageProvider<FilteredImageKey> {
  const FilteredImage(
    this.source, {
    required this.filter,
    required this.size,
    this.color = ThemeController.defaultMonochromeColor,
    this.dot = 3,
    this.seed = 0,
    this.strength = 1,
    this.background,
  });

  final ImageProvider source;
  final CoverFilter filter;
  final int size;

  /// [CoverFilter.monochrome]: the colour, and how many pixels wide one "dot" is.
  final Color color;
  final int dot;

  /// [CoverFilter.lain]: where the grain pattern starts, so one cover always looks the same.
  final int seed;

  /// 0–1: how much of the filtered look is mixed over the cover.
  final double strength;

  /// [CoverFilter.monochrome]: unlit dots' colour; `null` = the dot colour, dimmed.
  final Color? background;

  /// 0 for "none" — real colours here are opaque.
  int get _backgroundArgb => background?.toARGB32() ?? 0;

  int get _percent => (strength * 100).round();

  /// Synchronous when [source]'s key is (files, bytes in memory): an image already filtered is
  /// then taken from the cache in the same frame, instead of a frame without it.
  @override
  Future<FilteredImageKey> obtainKey(ImageConfiguration configuration) {
    FilteredImageKey keyFor(Object sourceKey) => FilteredImageKey(
      sourceKey,
      filter,
      size,
      color.toARGB32(),
      dot,
      seed,
      _percent,
      _backgroundArgb,
    );
    FilteredImageKey? ready;
    final sourceKey = source.obtainKey(configuration);
    // A SynchronousFuture runs `then` right away.
    sourceKey.then((key) => ready = keyFor(key));
    final key = ready;
    return key != null ? SynchronousFuture(key) : sourceKey.then(keyFor);
  }

  /// Equal providers for equal settings: a rebuild (e.g. play/pause) doesn't make [Image] load
  /// the cover again.
  @override
  bool operator ==(Object other) =>
      other is FilteredImage &&
      other.source == source &&
      other.filter == filter &&
      other.size == size &&
      other.color == color &&
      other.dot == dot &&
      other.seed == seed &&
      other._percent == _percent &&
      other.background == background;

  @override
  int get hashCode =>
      Object.hash(source, filter, size, color, dot, seed, _percent, background);

  @override
  ImageStreamCompleter loadImage(
    FilteredImageKey key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_load());

  Future<ImageInfo> _load() async {
    // By height, so the short side of a 16:9 thumbnail fills the square.
    final decoded = await loadUiImage(ResizeImage(source, height: size));
    final ByteData? data;
    final width = decoded.width, height = decoded.height;
    try {
      data = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      decoded.dispose();
    }
    final pixels = data!.buffer.asUint8List();
    // Plain locals, so the isolate's closure doesn't capture this provider.
    final lain = filter == CoverFilter.lain, argb = color.toARGB32();
    final dotSize = dot, grainSeed = seed, mix = _percent / 100;
    final backgroundArgb = background?.toARGB32();
    final out = await Isolate.run(
      () => lain
          ? lainFilter(pixels, width, height, grainSeed, strength: mix)
          : monochromeFilter(
              pixels,
              width,
              height,
              dotSize,
              argb,
              backgroundArgb: backgroundArgb,
              strength: mix,
            ),
    );
    final image = await _fromPixels(out.rgba, out.side);
    return ImageInfo(image: image);
  }

  static Future<ui.Image> _fromPixels(Uint8List rgba, int side) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      side,
      side,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }
}

@immutable
class FilteredImageKey {
  const FilteredImageKey(
    this.source,
    this.filter,
    this.size,
    this.color,
    this.dot,
    this.seed,
    this.percent,
    this.background,
  );

  final Object source;
  final CoverFilter filter;
  final int size;
  final int color;
  final int dot;
  final int seed;
  final int percent;
  final int background;

  @override
  bool operator ==(Object other) =>
      other is FilteredImageKey &&
      other.percent == percent &&
      other.background == background &&
      other.source == source &&
      other.filter == filter &&
      other.size == size &&
      other.color == color &&
      other.dot == dot &&
      other.seed == seed;

  @override
  int get hashCode =>
      Object.hash(source, filter, size, color, dot, seed, percent, background);
}

typedef FilteredPixels = ({Uint8List rgba, int side});

/// The colours of the Lain look, dark to light: night blue, sea green, the screens' cyan.
const _lainStops = [
  (0.0, 4, 9, 18),
  (0.42, 16, 70, 92),
  (0.78, 82, 182, 196),
  (1.0, 196, 248, 240),
];

/// Lain (1996): brightness mapped onto blue-green with a little of the cover's own blues and
/// greens (reds mostly gone), shadows crushed, film grain, scan lines, a darker rim. Below full
/// [strength] the cover shows through.
FilteredPixels lainFilter(
  Uint8List src,
  int width,
  int height,
  int seed, {
  double strength = 1,
}) {
  final side = min(width, height);
  final ox = (width - side) ~/ 2, oy = (height - side) ~/ 2;
  final out = Uint8List(side * side * 4);
  // Lines a few pixels apart whatever the size, so a small cover isn't all stripes.
  final lineEvery = max(3, side ~/ 90);
  final half = side / 2;
  for (var y = 0; y < side; y++) {
    final scan = y % lineEvery == 0 ? 0.78 : 1.0;
    for (var x = 0; x < side; x++) {
      final i = ((y + oy) * width + x + ox) * 4;
      final r = src[i], g = src[i + 1], b = src[i + 2];
      var l = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
      l = pow(((l - 0.06) / 0.86).clamp(0.0, 1.0), 1.2).toDouble();
      final (gr, gg, gb) = _gradient(l);
      final grain = (_noise(x, y, seed) - 0.5) * 38;
      final dx = (x - half) / half, dy = (y - half) / half;
      final rim = 1 - 0.38 * (dx * dx + dy * dy) / 2;
      final k = scan * rim;
      final o = (y * side + x) * 4;
      out[o] = _mix(r, (gr * 0.8 + r * 0.06 + grain) * k, strength);
      out[o + 1] = _mix(g, (gg * 0.8 + g * 0.18 + grain) * k, strength);
      out[o + 2] = _mix(b, (gb * 0.8 + b * 0.2 + grain) * k, strength);
      out[o + 3] = 255;
    }
  }
  return (rgba: out, side: side);
}

(double, double, double) _gradient(double l) {
  for (var s = 1; s < _lainStops.length; s++) {
    final (p1, r1, g1, b1) = _lainStops[s];
    if (l > p1 && s < _lainStops.length - 1) continue;
    final (p0, r0, g0, b0) = _lainStops[s - 1];
    final t = ((l - p0) / (p1 - p0)).clamp(0.0, 1.0);
    return (r0 + (r1 - r0) * t, g0 + (g1 - g0) * t, b0 + (b1 - b0) * t);
  }
  return (0, 0, 0);
}

/// Repeatable "random" 0..1 per pixel.
double _noise(int x, int y, int seed) {
  var h = (x * 374761393 + y * 668265263 + seed * 2147483647) & 0x7fffffff;
  h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
  return (h & 0xffff) / 0xffff;
}

int _byte(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

/// Bayer's 8×8 ordered-dither thresholds.
const _bayer8 = [
  0, 32, 8, 40, 2, 34, 10, 42, //
  48, 16, 56, 24, 50, 18, 58, 26,
  12, 44, 4, 36, 14, 46, 6, 38,
  60, 28, 52, 20, 62, 30, 54, 22,
  3, 35, 11, 43, 1, 33, 9, 41,
  51, 19, 59, 27, 49, 17, 57, 25,
  15, 47, 7, 39, 13, 45, 5, 37,
  63, 31, 55, 23, 61, 29, 53, 21,
];

/// One colour: every [dot]×[dot] block of [src] is one dot, lit or not (ordered dithering), so
/// grey shows as more or fewer lit dots, like a monochrome screen. Each dot has a dimmer edge, so
/// the grid shows; unlit dots are [backgroundArgb] (else they glow faintly in the dot colour).
/// Below full [strength] the cover shows through.
FilteredPixels monochromeFilter(
  Uint8List src,
  int width,
  int height,
  int dot,
  int argb, {
  int? backgroundArgb,
  double strength = 1,
}) {
  final cells = max(1, min(width, height) ~/ dot);
  final side = cells * dot;
  final ox = (width - side) ~/ 2, oy = (height - side) ~/ 2;
  final lum = Float64List(cells * cells);
  final histogram = List.filled(256, 0);
  for (var cy = 0; cy < cells; cy++) {
    for (var cx = 0; cx < cells; cx++) {
      var sum = 0.0;
      for (var py = 0; py < dot; py++) {
        for (var px = 0; px < dot; px++) {
          final i = ((oy + cy * dot + py) * width + ox + cx * dot + px) * 4;
          sum += 0.299 * src[i] + 0.587 * src[i + 1] + 0.114 * src[i + 2];
        }
      }
      final l = (sum / (dot * dot)).round().clamp(0, 255);
      lum[cy * cells + cx] = l.toDouble();
      histogram[l]++;
    }
  }
  // Stretched between the 2nd and 98th percentile, so a dull cover still uses all the shades.
  int percentile(double p) {
    final target = p * cells * cells;
    var seen = 0;
    for (var v = 0; v < 256; v++) {
      seen += histogram[v];
      if (seen >= target) return v;
    }
    return 255;
  }

  final lo = percentile(0.02);
  final hi = max(lo + 1, percentile(0.98));

  List<double> rgb(int c) => [
    ((c >> 16) & 0xff).toDouble(),
    ((c >> 8) & 0xff).toDouble(),
    (c & 0xff).toDouble(),
  ];
  List<double> between(List<double> a, List<double> b, double t) => [
    for (var k = 0; k < 3; k++) a[k] + (b[k] - a[k]) * t,
  ];
  final lit = rgb(argb);
  // Without a background colour of its own, unlit dots are the dot colour at 10 %.
  final off = backgroundArgb == null
      ? between([0, 0, 0], lit, 0.1)
      : rgb(backgroundArgb);
  final edge = between(off, lit, 0.5);
  final gap = between(off, [0, 0, 0], 0.5);

  final out = Uint8List(side * side * 4);
  for (var cy = 0; cy < cells; cy++) {
    for (var cx = 0; cx < cells; cx++) {
      // Gamma: lit dots look brighter than the same share of grey, so mid-tones need fewer.
      final l = pow(
        ((lum[cy * cells + cx] - lo) / (hi - lo)).clamp(0.0, 1.0),
        1.6,
      );
      final on = l > (_bayer8[(cy % 8) * 8 + cx % 8] + 0.5) / 64;
      for (var py = 0; py < dot; py++) {
        for (var px = 0; px < dot; px++) {
          final border = dot >= 3 && (px == dot - 1 || py == dot - 1);
          final c = on ? (border ? edge : lit) : (border ? gap : off);
          final x = cx * dot + px, y = cy * dot + py;
          final i = ((oy + y) * width + ox + x) * 4;
          final o = (y * side + x) * 4;
          out[o] = _mix(src[i], c[0], strength);
          out[o + 1] = _mix(src[i + 1], c[1], strength);
          out[o + 2] = _mix(src[i + 2], c[2], strength);
          out[o + 3] = 255;
        }
      }
    }
  }
  return (rgba: out, side: side);
}

/// [from] at strength 0, [to] at 1.
int _mix(num from, num to, double strength) =>
    _byte(from + (to - from) * strength);
