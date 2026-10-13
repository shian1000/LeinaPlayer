import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/song_details.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('song_details_test');
    sync = DatabaseSync(storageRoot: () async => root);
  });

  tearDown(() async {
    sync.dispose();
    await root.delete(recursive: true);
  });

  Future<SongDetails?> read(int id) =>
      readSongDetails(sync, id, factory: databaseFactoryFfi);

  test('no music.db, or no such song: nothing', () async {
    expect(await read(1), isNull);
    await writeMusicDb((await sync.localFile('music.db')).path);
    expect(await read(99), isNull);
  });

  test('an older music.db: the song row and its artists, no album', () async {
    await writeMusicDb((await sync.localFile('music.db')).path);
    final details = (await read(3))!;
    expect(details.song['title'], 'Pay Your Respect');
    expect(details.song['youtube_video_id'], 'N/A');
    expect(
      [for (final a in details.artists) (a.role, a.artist['name'])],
      [('main', 'Afina'), ('feat', 'CJ Pitts')],
    );
    expect(details.album, isNull);
    expect(details.tags, isEmpty);
  });

  test('album, its covers, former ids and tag.db tags', () async {
    final path = (await sync.localFile('music.db')).path;
    await writeMusicDb(path);
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('ALTER TABLE songs ADD COLUMN album_id INTEGER');
    await db.execute(
      'CREATE TABLE albums (id INTEGER PRIMARY KEY, title VARCHAR, '
      'artist_id INTEGER, year INTEGER, type VARCHAR, deezer_album_id INTEGER)',
    );
    await db.execute(
      'CREATE TABLE album_covers (album_id INTEGER, source VARCHAR, url VARCHAR, '
      'status VARCHAR)',
    );
    await db.execute(
      'CREATE TABLE song_id_changes (id INTEGER PRIMARY KEY, old_song_id INTEGER, '
      'new_song_id INTEGER, changed_at TEXT)',
    );
    await db.rawInsert(
      "INSERT INTO albums VALUES (7, 'Led Zeppelin IV', 2, 1971, 'album', 123)",
    );
    await db.rawInsert(
      "INSERT INTO album_covers VALUES (7, 'deezer', 'https://x/y.jpg', 'found')",
    );
    await db.rawInsert(
      "INSERT INTO song_id_changes VALUES (1, 40, 2, '2026-01-02')",
    );
    await db.rawUpdate('UPDATE songs SET album_id = 7 WHERE id = 2');
    await db.close();
    await writeTagDb(
      (await sync.localFile('tag.db')).path,
      tags: {
        1: ('Siłownia', 'mood', [2]),
        2: ('spellchecked', 'marker', [2, 3]),
        3: ('album_checked', 'marker', [1]),
      },
    );

    final details = (await read(2))!;
    expect(details.album?['title'], 'Led Zeppelin IV');
    expect(details.albumArtist, 'Led Zeppelin');
    expect(details.albumCovers.single['source'], 'deezer');
    expect(details.formerIds.single.id, 40);
    expect(details.tags, [
      (name: 'spellchecked', kind: 'marker'),
      (name: 'Siłownia', kind: 'mood'),
    ]);
  });
}
