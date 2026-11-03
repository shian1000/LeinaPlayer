import 'dart:io';

import 'package:flutter/services.dart';

import 'download_files.dart';

/// What a converted file's ID3 tag says — music.db's values, so other music apps list the song
/// as MusicDatabase knows it.
class Mp3Tags {
  const Mp3Tags({
    this.title,
    this.artist,
    this.album,
    this.year,
    this.genre,
    this.cover,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? year;
  final String? genre;

  /// The album cover's image file (JPEG or PNG), as the app shows it, without cover filters.
  final Uint8List? cover;
}

/// Encodes [from] as MP3 into [to]; throws when it can't.
typedef Mp3Converter = Future<void> Function(File from, File to, Mp3Tags tags);

/// "Pobieraj jako MP3"'s bitrate (user's choice): a lossy source re-encoded loses next to
/// nothing audible at it.
const mp3Kbps = 256;

const _channel = MethodChannel('music_database_app/downloads');

/// The phone's own encoder (`Mp3Encoder.kt`); `null` where there's none (not Android).
Mp3Converter? platformMp3Converter() => Platform.isAndroid
    ? (from, to, tags) => _channel.invokeMethod<void>('toMp3', {
        'from': from.path,
        'to': to.path,
        'kbps': mp3Kbps,
        'title': tags.title,
        'artist': tags.artist,
        'album': tags.album,
        'year': tags.year?.toString(),
        'genre': tags.genre,
        'cover': tags.cover,
      })
    : null;

bool isMp3(String path) => fileExtension(path).toLowerCase() == '.mp3';

/// [source] re-encoded as `<same name>.mp3` in its folder (" (2)"… when that's taken), written in
/// [workDir] first so the folder never shows a half-done file; [source] is deleted then. Returns
/// the new file — it throws, leaving [source] as it was, when the conversion fails.
Future<File> convertBeside(
  File source,
  Directory workDir,
  Mp3Tags tags,
  Mp3Converter convert,
) async {
  final name = source.uri.pathSegments.last;
  final base = name.substring(0, name.length - fileExtension(name).length);
  final part = File('${workDir.path}/$base.mp3.part');
  try {
    await convert(source, part, tags);
    final target = await moveFile(
      part,
      await freeFileIn(source.parent, base, '.mp3'),
    );
    await source.delete();
    return target;
  } catch (_) {
    if (await part.exists()) await part.delete();
    rethrow;
  }
}
