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
