import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'database_sync.dart';

typedef DbRow = Map<String, Object?>;

/// Everything the downloaded `music.db` and `tag.db` say about one song, for "Informacje o
/// utworze" in the full player. Rows are kept whole (`SELECT *`), so columns MusicDatabase adds
/// later show up without changing the phone.
class SongDetails {
  const SongDetails({
    required this.song,
    this.artists = const [],
    this.album,
    this.albumArtist,
    this.albumCovers = const [],
    this.tags = const [],
    this.formerIds = const [],
  });

  /// The `songs` row.
  final DbRow song;

  /// `artists` rows: the song's own artist (role `main`) first, then `additional_song_artists`.
  final List<({String role, DbRow artist})> artists;

  /// The `albums` row of `songs.album_id`.
  final DbRow? album;

  /// `artists.name` of the album's `artist_id`.
  final String? albumArtist;

  /// The album's `album_covers` rows (one per source).
  final List<DbRow> albumCovers;

  /// tag.db's tags of the song (moods among them, `kind = 'mood'`).
  final List<({String name, String kind})> tags;

  /// Ids the song had before MusicDatabase merged or renumbered it (`song_id_changes`).
  final List<({int id, String? changedAt})> formerIds;
}

/// Reads [SongDetails] of `songs.id` [songId] from the files [sync] downloaded, or `null` when
/// music.db is missing or has no such song. Tables an older database lacks are skipped.
Future<SongDetails?> readSongDetails(
  DatabaseSync sync,
  int songId, {
  DatabaseFactory? factory,
}) async {
  final musicFile = await sync.localFile('music.db');
  if (!await musicFile.exists()) return null;
  final options = OpenDatabaseOptions(readOnly: true, singleInstance: false);
  final tags = await _readTags(
    sync,
    songId,
    factory ?? databaseFactory,
    options,
  );
  final db = await (factory ?? databaseFactory).openDatabase(
    musicFile.path,
    options: options,
  );
  try {
    final tables = {
      for (final row in await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ))
        row['name'],
    };
    final song = (await db.rawQuery('SELECT * FROM songs WHERE id = ?', [
      songId,
    ])).firstOrNull;
    if (song == null) return null;

    final artists = <({String role, DbRow artist})>[
      for (final row in await db.rawQuery(
        'SELECT * FROM artists WHERE id = ?',
        [song['artist_id']],
      ))
        (role: 'main', artist: row),
      if (tables.contains('additional_song_artists'))
        for (final row in await db.rawQuery(
          'SELECT x.role AS song_role, a.* FROM additional_song_artists x '
          'JOIN artists a ON a.id = x.artist_id WHERE x.song_id = ? '
          "ORDER BY x.role = 'feat', a.name",
          [songId],
        ))
          (
            role: row['song_role']! as String,
            artist: Map.of(row)..remove('song_role'),
          ),
    ];

    DbRow? album;
    String? albumArtist;
    var covers = const <DbRow>[];
    final albumId = song['album_id'];
    if (albumId != null && tables.contains('albums')) {
      album = (await db.rawQuery('SELECT * FROM albums WHERE id = ?', [
        albumId,
      ])).firstOrNull;
      if (album?['artist_id'] != null) {
        albumArtist =
            (await db.rawQuery('SELECT name FROM artists WHERE id = ?', [
                  album!['artist_id'],
                ])).firstOrNull?['name']
                as String?;
      }
      if (tables.contains('album_covers')) {
        covers = await db.rawQuery(
          'SELECT * FROM album_covers WHERE album_id = ? ORDER BY source',
          [albumId],
        );
      }
    }

    final formerIds = !tables.contains('song_id_changes')
        ? const <({int id, String? changedAt})>[]
        : [
            for (final row in await db.rawQuery(
              'SELECT old_song_id, changed_at FROM song_id_changes '
              'WHERE new_song_id = ? ORDER BY changed_at',
              [songId],
            ))
              (
                id: row['old_song_id']! as int,
                changedAt: row['changed_at'] as String?,
              ),
          ];

    return SongDetails(
      song: song,
      artists: artists,
      album: album,
      albumArtist: albumArtist,
      albumCovers: covers,
      tags: tags,
      formerIds: formerIds,
    );
  } finally {
    await db.close();
  }
}

Future<List<({String name, String kind})>> _readTags(
  DatabaseSync sync,
  int songId,
  DatabaseFactory factory,
  OpenDatabaseOptions options,
) async {
  final file = await sync.localFile('tag.db');
  if (!await file.exists()) return const [];
  try {
    final db = await factory.openDatabase(file.path, options: options);
    try {
      final columns = {
        for (final c in await db.rawQuery('PRAGMA table_info(tags)')) c['name'],
      };
      // Older tag.dbs have no kinds (all markers) and no deleted moods.
      final kind = columns.contains('kind') ? 't.kind' : "'marker'";
      final live = columns.contains('deleted_at')
          ? 'AND t.deleted_at IS NULL'
          : '';
      return [
        for (final row in await db.rawQuery(
          'SELECT t.name, $kind AS kind FROM song_tags s '
          'JOIN tags t ON t.id = s.tag_id WHERE s.song_id = ? $live '
          'ORDER BY kind, t.name',
          [songId],
        ))
          (name: row['name']! as String, kind: row['kind']! as String),
      ];
    } finally {
      await db.close();
    }
  } catch (e) {
    debugPrint('Reading tags from tag.db failed: $e');
    return const [];
  }
}
