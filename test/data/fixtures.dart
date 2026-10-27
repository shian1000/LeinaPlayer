import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Writes a minimal `music.db` with the same tables the app reads from MusicDatabase.
Future<void> writeMusicDb(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute(
    'CREATE TABLE artists (id INTEGER PRIMARY KEY, name VARCHAR NOT NULL, '
    'origin VARCHAR, synonyms VARCHAR)',
  );
  await db.execute(
    'CREATE TABLE songs (id INTEGER PRIMARY KEY, title VARCHAR NOT NULL, '
    'album VARCHAR, year INTEGER, language VARCHAR, artist_id INTEGER NOT NULL, '
    'youtube_video_id VARCHAR)',
  );
  await db.execute(
    'CREATE TABLE additional_song_artists (song_id INTEGER NOT NULL, '
    'artist_id INTEGER NOT NULL, role VARCHAR NOT NULL)',
  );
  await db.rawInsert(
    "INSERT INTO artists VALUES "
    "(1, 'Dawid Podsiadło', 'Poland - Silesia - Dąbrowa Górnicza', NULL), "
    "(2, 'Led Zeppelin', 'England - London', 'ledzeppelinofficial'), "
    "(3, 'Afina', NULL, NULL), (4, 'CJ Pitts', 'USA - Ohio', NULL), "
    "(5, 'Artur Rojek', 'Poland - Silesia - Katowice', NULL), "
    "(6, 'CatchUp', NULL, NULL)",
  );
  await db.rawInsert(
    "INSERT INTO songs VALUES "
    "(1, 'Małomiasteczkowy', 'Małomiasteczkowy', 2018, 'Polish', 1, 'X2XWBcd5jn0'), "
    "(2, 'Going to California', 'Led Zeppelin IV', 1971, 'English', 2, NULL), "
    "(3, 'Pay Your Respect', 'Singles', NULL, 'Unknown', 3, 'N/A'), "
    "(4, 'Pusty', NULL, 2014, 'Polish', 5, ''), "
    "(5, 'California Dreaming', 'Covers', 2001, 'English', 2, NULL)",
  );
  await db.rawInsert(
    "INSERT INTO additional_song_artists VALUES (3, 4, 'feat'), (4, 6, 'main')",
  );
  await db.close();
}

/// A `files.db` like MusicDatabase's music library index (`files_index.py`): each of [files]
/// is (id, path, size, song id); [durations] gives some of them `duration_s` (by file id).
Future<void> writeFilesDb(
  String path,
  List<(int, String, int, int?)> files, {
  Map<int, int> durations = const {},
}) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute(
    'CREATE TABLE files (id INTEGER PRIMARY KEY AUTOINCREMENT, path VARCHAR NOT NULL UNIQUE, '
    'size INTEGER NOT NULL, mtime INTEGER NOT NULL, song_id INTEGER, '
    "match_source VARCHAR NOT NULL DEFAULT 'auto', artist VARCHAR, title VARCHAR, "
    'duration_s INTEGER, indexed_at VARCHAR NOT NULL)',
  );
  for (final (id, file, size, songId) in files) {
    await db.insert('files', {
      'id': id,
      'path': file,
      'size': size,
      'mtime': 0,
      'song_id': songId,
      'duration_s': durations[id],
      'indexed_at': '2026-10-14T12:00:00+00:00',
    });
  }
  await db.close();
}

/// Adds music.db's `youtube_video_durations` (MusicDatabase's migration 0017) with [seconds]
/// per video id.
Future<void> addVideoDurations(String path, Map<String, int> seconds) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute(
    'CREATE TABLE youtube_video_durations (video_id TEXT PRIMARY KEY NOT NULL, '
    'duration_s INTEGER NOT NULL, fetched_at TEXT NOT NULL)',
  );
  for (final MapEntry(:key, :value) in seconds.entries) {
    await db.insert('youtube_video_durations', {
      'video_id': key,
      'duration_s': value,
      'fetched_at': '2026-10-27 12:00:00',
    });
  }
  await db.close();
}

/// A tag.db like MusicDatabase's since moods (`tags.kind`), or — [withKind] false — an older one.
Future<void> writeTagDb(
  String path, {
  Map<int, (String, String, List<int>)> tags = const {},
  bool withKind = true,
}) async {
  await File(path).parent.create(recursive: true);
  if (await File(path).exists()) await File(path).delete();
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute(
    'CREATE TABLE tags (id INTEGER PRIMARY KEY, name VARCHAR NOT NULL UNIQUE'
    '${withKind ? ", kind VARCHAR NOT NULL DEFAULT 'marker'" : ''})',
  );
  await db.execute(
    'CREATE TABLE song_tags (id INTEGER PRIMARY KEY, song_id INTEGER NOT NULL, '
    'tag_id INTEGER NOT NULL)',
  );
  for (final MapEntry(key: id, value: (name, kind, songs)) in tags.entries) {
    await db.insert('tags', {
      'id': id,
      'name': name,
      'kind': ?(withKind ? kind : null),
    });
    for (final song in songs) {
      await db.insert('song_tags', {'song_id': song, 'tag_id': id});
    }
  }
  await db.close();
}
