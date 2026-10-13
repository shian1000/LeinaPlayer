import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'moods.dart';
import 'playlist_library.dart';

/// Covers the user picked for their playlists and moods ("Dodaj okładkę"), kept only on this
/// phone: MusicDatabase's playlist and mood JSON has no place for a picture (ADR 0007/0008), so
/// they aren't synced. Without one, a playlist or mood shows a collage of its songs' covers.
///
/// Each cover is one square PNG in its own folder, named `<key>.<millis>.png`: a new name for
/// every change, so a cover replaced under the same key isn't served from the image cache.
class CustomCovers extends ChangeNotifier {
  CustomCovers({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  /// Sides of the saved square: sharp in the playlist header (220 dp) on a 3× screen.
  static const side = 660;

  final Future<Directory> Function() _directory;
  Map<String, File> _files = const {};

  static Future<Directory> _defaultDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/custom_covers',
  );

  static String playlistKey(PlaylistSummary playlist) =>
      'playlist-${playlist.id}';
  static String moodKey(Mood mood) => 'mood-${mood.key}';

  /// The cover picked for [key], if any.
  File? fileFor(String key) => _files[key];

  Future<void> load() async {
    final dir = await _directory();
    final files = <String, File>{};
    final stamps = <String, int>{};
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final match = RegExp(r'^(.+)\.(\d+)\.png$')
            .firstMatch(entity.uri.pathSegments.last);
        if (match == null) continue;
        final key = match[1]!;
        final stamp = int.parse(match[2]!);
        if (stamp < (stamps[key] ?? -1)) continue;
        stamps[key] = stamp;
        files[key] = entity;
      }
    }
    _files = files;
    notifyListeners();
  }

  /// Saves [image] (any format Flutter decodes) as [key]'s cover: its middle square, scaled
  /// down to [side]. Throws when [image] isn't a picture.
  Future<void> set(String key, List<int> image) async {
    final png = await _squarePng(image);
    final dir = await _directory();
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}/$key.${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(png, flush: true);
    final old = _files[key];
    _files = {..._files, key: file};
    notifyListeners();
    if (old != null && old.path != file.path) await _deleteQuietly(old);
  }

  /// Back to the collage.
  Future<void> remove(String key) async {
    final old = _files[key];
    if (old == null) return;
    _files = {..._files}..remove(key);
    notifyListeners();
    await _deleteQuietly(old);
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } catch (e) {
      debugPrint('Deleting cover ${file.path} failed: $e');
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
