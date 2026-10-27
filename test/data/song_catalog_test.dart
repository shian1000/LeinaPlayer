import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/text_normalizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';
import '../support/waiting.dart';

void main() {
  sqfliteFfiInit();

  group('normalizeForSearch', () {
    test('strips Polish and other diacritics and lowercases', () {
      expect(normalizeForSearch('Zażółć GĘŚLĄ jaźń'), 'zazolc gesla jazn');
      expect(normalizeForSearch('Beyoncé • Motörhead'), 'beyonce motorhead');
    });

    test('drops apostrophes, turns other punctuation into spaces', () {
      expect(normalizeForSearch("Don't Stop (Remix)!"), 'dont stop remix');
      expect(normalizeForSearch('  AC/DC  -  T.N.T. '), 'ac dc t n t');
    });

    test('spells out letters that do not decompose', () {
      expect(
        normalizeForSearch('Straße Œuvre Øresund'),
        'strasse oeuvre oresund',
      );
    });
  });

  group('SongCatalog', () {
    late Directory storage;
    late DatabaseSync sync;
    late SongCatalog catalog;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = await Directory.systemTemp.createTemp('song_catalog_test');
      sync = DatabaseSync(storageRoot: () async => storage);
      catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    });

    tearDown(() async {
      catalog.dispose();
      sync.dispose();
      await storage.delete(recursive: true);
    });

    Future<void> loadSample() async {
      await writeMusicDb((await sync.localFile('music.db')).path);
      await catalog.ensureLoaded();
    }

    test('reports a missing database instead of failing', () async {
      await catalog.ensureLoaded();
      expect(catalog.status, CatalogStatus.noDatabase);
      expect(catalog.search('anything'), isEmpty);
    });

    test(
      'reads the videos MusicDatabase found bad; none without the table',
      () async {
        final path = (await sync.localFile('music.db')).path;
        await writeMusicDb(path);
        final before = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
        await before.ensureLoaded();
        expect(before.status, CatalogStatus.ready);
        expect(before.badVideos.everySong, isEmpty);
        expect(before.badVideos.forSong, isEmpty);
        before.dispose();

        final db = await databaseFactoryFfi.openDatabase(path);
        await db.execute('''
        CREATE TABLE bad_youtube_videos (
          id INTEGER PRIMARY KEY, video_id TEXT NOT NULL, song_id INTEGER,
          reason TEXT NOT NULL, marked_at TEXT NOT NULL)''');
        for (final (video, song, reason) in [
          ('gone1234567', null, 'removed'),
          ('wrong123456', 1, 'wrong_for_song'),
          ('wrong654321', 1, 'wrong_for_song'),
        ]) {
          await db.insert('bad_youtube_videos', {
            'video_id': video,
            'song_id': song,
            'reason': reason,
            'marked_at': '2026-10-14T12:00:00+02:00',
          });
        }
        await db.close();
        await catalog.ensureLoaded();

        expect(catalog.badVideos.everySong, {'gone1234567'});
        expect(catalog.badVideos.isWrongFor(1, 'wrong123456'), isTrue);
        expect(catalog.badVideos.isWrongFor(1, 'gone1234567'), isFalse);
        expect(catalog.badVideos.isWrongFor(2, 'wrong123456'), isFalse);
      },
    );

    test('files on the server come from files.db, the largest one per song; '
        'none without it', () async {
      await loadSample();
      expect(catalog.byId(1)!.serverFile, isNull);

      await writeFilesDb((await sync.localFile('files.db')).path, [
        (10, 'Dawid Podsiadło/Małomiasteczkowy.mp3', 5000, 1),
        (11, 'Dawid Podsiadło/Małomiasteczkowy (128k).mp3', 3000, 1),
        (12, 'Unknown/track.mp3', 4000, null),
        (13, 'Led Zeppelin/Going to California.mp3', 6000, 2),
      ]);
      final again = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      addTearDown(again.dispose);
      await again.ensureLoaded();
      expect(again.byId(1)!.serverFile!.id, 10);
      expect(again.byId(1)!.serverFile!.fileName, 'Małomiasteczkowy.mp3');
      expect(
        again.byId(2)!.serverFile!.path,
        'Led Zeppelin/Going to California.mp3',
      );
      expect(again.byId(3)!.serverFile, isNull);
    });

    test('video lengths come from youtube_video_durations, file lengths from '
        'files.db; unknown without them', () async {
      await loadSample();
      expect(catalog.videoDuration('X2XWBcd5jn0'), isNull);

      final path = (await sync.localFile('music.db')).path;
      await addVideoDurations(path, {'X2XWBcd5jn0': 245});
      await writeFilesDb(
        (await sync.localFile('files.db')).path,
        [
          (10, 'Led Zeppelin/Going to California.mp3', 6000, 2),
          (11, 'Afina/Pay Your Respect.mp3', 6000, 3),
        ],
        durations: {10: 211},
      );
      final again = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      addTearDown(again.dispose);
      await again.ensureLoaded();
      expect(again.videoDuration('X2XWBcd5jn0'), const Duration(seconds: 245));
      expect(again.videoDuration('other123456'), isNull);
      expect(again.videoDuration(null), isNull);
      expect(again.byId(2)!.serverFile!.duration, const Duration(seconds: 211));
      expect(again.byId(3)!.serverFile!.duration, isNull);
    });

    test('Latin forms of names in another alphabet: music.db\'s, else an '
        'artist\'s Latin synonym; found by search', () async {
      final path = (await sync.localFile('music.db')).path;
      await writeMusicDb(path);
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute('ALTER TABLE artists ADD COLUMN name_latin VARCHAR');
      await db.execute('ALTER TABLE songs ADD COLUMN title_latin VARCHAR');
      await db.execute('ALTER TABLE songs ADD COLUMN album_id INTEGER');
      await db.execute(
        'CREATE TABLE albums (id INTEGER PRIMARY KEY, title VARCHAR NOT NULL, '
        'title_latin VARCHAR)',
      );
      await db.rawInsert(
        "INSERT INTO albums VALUES (1, 'Группа крови', 'Gruppa krovi')",
      );
      await db.rawInsert(
        "INSERT INTO artists (id, name, synonyms, name_latin) VALUES "
        "(7, 'Кино', NULL, 'Kino'), "
        "(8, 'Бумбокс', 'Бумбокс UA, familyboombox, Bumboks', NULL), "
        "(9, 'Земфира', NULL, NULL)",
      );
      await db.rawInsert(
        'INSERT INTO songs (id, title, album, language, artist_id, '
        'title_latin, album_id) VALUES '
        "(6, 'Группа крови', 'Группа крови', 'Russian', 7, 'Gruppa krovi', 1), "
        "(7, 'Вахтёрам', NULL, 'Ukrainian', 8, NULL, NULL), "
        "(8, 'Хочешь?', NULL, 'Russian', 9, 'Khochesh?', NULL)",
      );
      await db.rawInsert(
        "INSERT INTO additional_song_artists VALUES (7, 2, 'feat')",
      );
      await db.execute("UPDATE songs SET title_latin = 'Maly' WHERE id = 1");
      await db.close();
      await catalog.ensureLoaded();

      final kino = catalog.byId(6)!;
      expect(kino.titleLatin, 'Gruppa krovi');
      expect(kino.artistLatin, 'Kino');
      expect(kino.albumLatin, 'Gruppa krovi');
      final boombox = catalog.byId(7)!;
      expect(boombox.titleLatin, isNull);
      expect(boombox.artistLatin, 'familyboombox feat. Led Zeppelin');
      // Nothing to go by: no Latin form rather than a half-Latin one.
      expect(catalog.byId(8)!.artistLatin, isNull);
      // Already in Latin letters: nothing more to show.
      expect(catalog.byId(1)!.titleLatin, isNull);
      expect(catalog.byId(1)!.artistLatin, isNull);

      expect(catalog.search('gruppa kino').single.id, 6);
      expect(catalog.search('khochesh').single.id, 8);
      expect(catalog.findExact(title: 'Группа крови', artist: 'Kino')?.id, 6);

      // An artist by any of its names: a channel name, a Latin form.
      expect(catalog.artistNamed('FamilyBoomBox'), 'Бумбокс');
      expect(catalog.artistNamed('Kino'), 'Кино');
      expect(catalog.artistNamed('Бумбокс'), 'Бумбокс');
      expect(catalog.artistNamed('led zeppelin'), 'Led Zeppelin');
      expect(catalog.artistNamed('Nobody'), isNull);
    });

    test('no Latin forms in a music.db from before them', () async {
      await loadSample();
      expect(catalog.byId(1)!.titleLatin, isNull);
      expect(catalog.byId(1)!.albumLatin, isNull);
    });

    test('loads every song with its artists', () async {
      await loadSample();
      expect(catalog.status, CatalogStatus.ready);
      expect(catalog.songCount, 5);
      expect(
        catalog.search('respect').single.artistLabel,
        'Afina feat. CJ Pitts',
      );
      expect(
        catalog.search('pusty').single.artistLabel,
        'Artur Rojek, CatchUp',
      );
    });

    test(
      'matches title and artist words regardless of accents and case',
      () async {
        await loadSample();
        expect(catalog.search('malomiasteczkowy podsiadlo').single.id, 1);
        expect(catalog.search('MAŁOMIASTECZKOWY').single.id, 1);
        expect(catalog.search('catchup').single.id, 4);
        expect(catalog.search('zeppelin nothing'), isEmpty);
        expect(catalog.search('   '), isEmpty);
      },
    );

    test('reads a Spotify track link, not an album one', () async {
      final path = (await sync.localFile('music.db')).path;
      await writeMusicDb(path);
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute('ALTER TABLE songs ADD COLUMN spotify_url VARCHAR');
      await db.rawUpdate(
        "UPDATE songs SET spotify_url = "
        "'https://open.spotify.com/track/7lQ8MOhq6IN2w8EYcFNSUk' WHERE id = 2",
      );
      await db.rawUpdate(
        "UPDATE songs SET spotify_url = "
        "'https://open.spotify.com/album/1Ugdi2OTxKopVVqsprp5pb' WHERE id = 5",
      );
      await db.close();
      await catalog.ensureLoaded();
      expect(catalog.byId(2)!.spotifyTrackId, '7lQ8MOhq6IN2w8EYcFNSUk');
      expect(catalog.byId(5)!.spotifyTrackId, isNull);
      expect(catalog.byId(1)!.spotifyTrackId, isNull);
    });

    test('songs.kind: full albums marked, an unknown value is a song, no '
        'column at all is songs only', () async {
      await loadSample();
      expect(catalog.songs.any((s) => s.isFullAlbum), isFalse);

      final path = (await sync.localFile('music.db')).path;
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute('ALTER TABLE songs ADD COLUMN kind TEXT');
      await db.rawUpdate("UPDATE songs SET kind = 'full_album' WHERE id = 2");
      await db.rawUpdate("UPDATE songs SET kind = 'dj_mix' WHERE id = 3");
      await db.close();
      final again = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      addTearDown(again.dispose);
      await again.ensureLoaded();
      expect(again.byId(2)!.kind, SongKind.fullAlbum);
      expect(again.byId(2)!.youTubeTarget.fullAlbum, isTrue);
      expect(again.byId(3)!.kind, SongKind.song);
      expect(again.byId(1)!.kind, SongKind.song);
      expect(again.byId(1)!.youTubeTarget.fullAlbum, isFalse);
    });

    test('puts titles starting with the query first', () async {
      await loadSample();
      expect(catalog.search('california').map((s) => s.id).toList(), [5, 2]);
    });

    test('reloads after a new download', () async {
      await loadSample();
      final db = await databaseFactoryFfi.openDatabase(
        (await sync.localFile('music.db')).path,
      );
      await db.rawInsert(
        "INSERT INTO songs VALUES (6, 'Nowa', NULL, NULL, NULL, 1, NULL)",
      );
      await db.close();
      expect(catalog.search('nowa'), isEmpty);

      // Simulates DatabaseSync announcing a new lastSync, as after a successful download.
      SharedPreferences.setMockInitialValues({
        'database_sync.url': 'http://127.0.0.1:1/',
        'database_sync.last_sync_ms': DateTime(
          2026,
          10,
          10,
        ).millisecondsSinceEpoch,
      });
      await sync.load();
      // The reload runs in the background and touches the real file system.
      await waitUntil(() => catalog.search('nowa').isNotEmpty);
      expect(catalog.search('nowa').single.id, 6);
    });

    test('search fields: defaults are title, artist and album', () async {
      await loadSample();
      expect(catalog.searchFields, SearchField.defaults);
      expect(catalog.search('led zeppelin iv').single.id, 2); // album
      expect(catalog.search('cj pitts').single.id, 3); // featured artist
      expect(catalog.search('2018'), isEmpty);
      expect(catalog.search('polish'), isEmpty);
      expect(catalog.search('silesia'), isEmpty);
    });

    test('search fields: year, language, origin, artist synonyms', () async {
      await loadSample();
      await catalog.setSearchFields({SearchField.year});
      expect(catalog.search('2018').single.id, 1);

      await catalog.setSearchFields({SearchField.language});
      expect(
        catalog.search('polish').map((s) => s.id),
        unorderedEquals([1, 4]),
      );
      expect(catalog.search('unknown'), isEmpty);

      await catalog.setSearchFields({SearchField.origin});
      // Origin of an additional artist counts too (CJ Pitts on song 3).
      expect(catalog.search('ohio').single.id, 3);
      expect(
        catalog.search('silesia').map((s) => s.id),
        unorderedEquals([1, 4]),
      );

      // Other artist names (synonyms) come with the artist field, not on their own.
      await catalog.setSearchFields({SearchField.artist});
      expect(
        catalog.search('ledzeppelinofficial').map((s) => s.id),
        unorderedEquals([2, 5]),
      );
      await catalog.setSearchFields({SearchField.title});
      expect(catalog.search('ledzeppelinofficial'), isEmpty);
    });

    test(
      'search fields: combined words may come from different fields',
      () async {
        await loadSample();
        await catalog.setSearchFields({SearchField.title, SearchField.year});
        expect(catalog.search('california 1971').single.id, 2);
      },
    );

    test('search fields: never empty, and remembered', () async {
      await loadSample();
      await catalog.setSearchFields({});
      expect(catalog.searchFields, SearchField.defaults);

      await catalog.setSearchFields({SearchField.year, SearchField.title});
      final again = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      addTearDown(again.dispose);
      await waitUntil(() => again.searchFields.length == 2);
      expect(again.searchFields, {SearchField.year, SearchField.title});
    });

    test('YouTube link: id, "N/A" annotation, or nothing stored', () async {
      await loadSample();
      CatalogSong song(String title) => catalog.search(title).first;

      expect(song('Małomiasteczkowy').youTube, YouTubeLink.linked);
      expect(song('Małomiasteczkowy').youtubeVideoId, 'X2XWBcd5jn0');
      expect(song('Pay Your Respect').youTube, YouTubeLink.notOnYouTube);
      expect(song('Pay Your Respect').youtubeVideoId, isNull);
      expect(song('Pusty').youTube, YouTubeLink.unknown);
      expect(song('Going to California').youTube, YouTubeLink.unknown);
    });
  });
}
