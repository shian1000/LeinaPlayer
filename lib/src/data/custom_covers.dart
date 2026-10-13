import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// The pictures of covers picked for playlists and moods ("Dodaj okładkę"), by the SHA-256 of
/// their bytes, as MusicDatabase keeps them ([ADR 0009](../../../docs/decisions/0009-cover-sync.md)).
/// Which playlist or mood has which cover is in `local.db` (`cover_sha256`), synced with the
/// account like the rest of the playlist or mood; this only holds the files, picked here or
/// downloaded from MusicDatabase. Without a cover a playlist or mood shows a collage of its
/// songs' covers.
///
/// A hash never changes its content, so a changed cover is a new file and Flutter's image
/// cache never shows an old one.
class CustomCovers extends ChangeNotifier {
  CustomCovers({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  /// Sides of a picked cover: sharp in the playlist header (220 dp) on a 3× screen.
  static const side = 660;

  /// A file nothing refers to stays this long: it may be about to be referred to (picked, not
  /// saved yet) — and MusicDatabase keeps its own unreferenced blobs a day too.
  static const unusedKept = Duration(days: 1);

  final Future<Directory> Function() _directory;
  Map<String, File> _files = const {};

  static Future<Directory> _defaultDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/custom_covers',
  );

  static final _name = RegExp(r'^([0-9a-f]{64})\.(png|jpg)$');

  /// MusicDatabase's form of a cover's id: lowercase hex SHA-256 of the bytes.
  static String hashOf(List<int> bytes) => sha256.convert(bytes).toString();

  /// The picture of [hash], if it's on the phone.
  File? fileFor(String? hash) => hash == null ? null : _files[hash];

  Future<void> load() async {
    final dir = await _directory();
    final files = <String, File>{};
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final match = _name.firstMatch(entity.uri.pathSegments.last);
        if (match != null) files[match[1]!] = entity;
      }
    }
    _files = files;
    notifyListeners();
  }

  /// Keeps [image] (any format Flutter decodes) as a cover — its middle square, scaled down to
  /// [side], as PNG — and returns its hash. Throws when [image] isn't a picture.
  Future<String> add(List<int> image) async {
    final png = await _squarePng(image);
    final hash = hashOf(png);
    await _write(hash, png, 'png');
    return hash;
  }

  /// Keeps a cover downloaded from MusicDatabase; refused unless [bytes] are [hash]'s.
  Future<void> store(String hash, List<int> bytes, {required bool jpeg}) async {
    if (hashOf(bytes) != hash) {
      throw ArgumentError.value(hash, 'hash', 'not the hash of these bytes');
    }
    await _write(hash, bytes, jpeg ? 'jpg' : 'png');
  }

  /// [hash]'s bytes and whether they're a JPEG (else PNG), for sending them to MusicDatabase.
  Future<({List<int> bytes, bool jpeg})?> read(String hash) async {
    final file = _files[hash];
    if (file == null) return null;
    try {
      return (
        bytes: await file.readAsBytes(),
        jpeg: file.path.endsWith('.jpg'),
      );
    } on FileSystemException catch (e) {
      debugPrint('Reading cover $hash failed: $e');
      return null;
    }
  }

  Future<void> _write(String hash, List<int> bytes, String extension) async {
    final known = _files[hash];
    if (known != null) {
      // Picked again: counts as new for [prune].
      await known.setLastModified(DateTime.now());
      return;
    }
    final dir = await _directory();
    await dir.create(recursive: true);
    final file = File('${dir.path}/$hash.$extension');
    final part = File('${file.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(file.path);
    _files = {..._files, hash: file};
    notifyListeners();
  }

  /// Deletes the pictures none of [used] refers to, once they're [unusedKept] old.
  Future<void> prune(Set<String> used, {DateTime? now}) async {
    final keepAfter = (now ?? DateTime.now()).subtract(unusedKept);
    final kept = {..._files};
    for (final MapEntry(key: hash, value: file) in _files.entries) {
      if (used.contains(hash)) continue;
      try {
        if ((await file.lastModified()).isAfter(keepAfter)) continue;
        await file.delete();
        kept.remove(hash);
      } on FileSystemException catch (e) {
        debugPrint('Deleting cover $hash failed: $e');
      }
    }
    if (kept.length != _files.length) {
      _files = kept;
      notifyListeners();
    }
  }

  static Future<List<int>> _squarePng(List<int> bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      Uint8List.fromList(bytes),
    );
    // Decoded straight at about the size kept: a 12 MP photo would take a lot of memory.
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        final shorter = width < height ? width : height;
        if (shorter <= side) return ui.TargetImageSize(width: width);
        final scale = side / shorter;
        return ui.TargetImageSize(
          width: (width * scale).round(),
          height: (height * scale).round(),
        );
      },
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    final source = frame.image;
    final cut = source.width < source.height ? source.width : source.height;
    final out = cut < side ? cut : side;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      source,
      Rect.fromLTWH(
        (source.width - cut) / 2,
        (source.height - cut) / 2,
        cut.toDouble(),
        cut.toDouble(),
      ),
      Rect.fromLTWH(0, 0, out.toDouble(), out.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final square = await recorder.endRecording().toImage(out, out);
    source.dispose();
    final data = await square.toByteData(format: ui.ImageByteFormat.png);
    square.dispose();
    return data!.buffer.asUint8List();
  }
}

/// Makes the [CustomCovers] reachable from any screen.
class CustomCoversScope extends InheritedNotifier<CustomCovers> {
  const CustomCoversScope({
    super.key,
    required CustomCovers super.notifier,
    required super.child,
  });

  static CustomCovers of(BuildContext context) => maybeOf(context)!;

  /// `null` where no scope is set up (widget tests): only collages are shown.
  static CustomCovers? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CustomCoversScope>()?.notifier;
}
