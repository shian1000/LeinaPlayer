import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// "Artist - Title" for a song downloaded into the user's own folder, without the characters
/// shared storage refuses (an SD card's FAT among them) and short enough for its 255 bytes.
String downloadBaseName(String artist, String title) {
  final name = [artist, title]
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join(' - ')
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
  final short = name.length > 120 ? name.substring(0, 120).trim() : name;
  return short.isEmpty ? 'Utwór' : short;
}

/// `.flac` of `1234.flac`, '' for a name without one.
String fileExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 || name.lastIndexOf('/') > dot ? '' : name.substring(dot);
}

/// [base] + [extension] in [dir], with " (2)", " (3)"… when a file of that name is there.
Future<File> freeFileIn(Directory dir, String base, String extension) async {
  await dir.create(recursive: true);
  var file = File('${dir.path}/$base$extension');
  for (var n = 2; await file.exists(); n++) {
    file = File('${dir.path}/$base ($n)$extension');
  }
  return file;
}

/// Moves [from] to [to] — copied and deleted when they're on different storage (the app's
/// own folder and the user's), where a rename fails.
Future<File> moveFile(File from, File to) async {
  try {
    return await from.rename(to.path);
  } on FileSystemException {
    final copy = File('${to.path}.part');
    try {
      await from.copy(copy.path);
      await copy.rename(to.path);
    } catch (_) {
      if (await copy.exists()) await copy.delete();
      rethrow;
    }
    await from.delete();
    return to;
  }
}

/// Whether [dir] is inside [folder] (or is it).
bool isInFolder(String dir, String folder) =>
    dir == folder || dir.startsWith(folder.endsWith('/') ? folder : '$folder/');

const _links = MethodChannel('music_database_app/links');

/// Tells Android's media store about [paths] (new or deleted), so other music apps see the songs
/// in the user's folder at once. Not on other platforms, and a failure only delays that.
Future<void> announceMediaFiles(List<String> paths) async {
  if (!Platform.isAndroid || paths.isEmpty) return;
  try {
    await _links.invokeMethod<void>('scanMedia', paths);
  } on MissingPluginException {
    // Tests.
  } catch (e) {
    debugPrint('Announcing ${paths.length} downloaded files failed: $e');
  }
}
