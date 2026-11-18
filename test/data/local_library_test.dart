import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';

void main() {
  sqfliteFfiInit();

  group('splitArtistTitle', () {
    test('spaced separators first, trimmed', () {
      expect(splitArtistTitle('Jieva - Negrisiu '), ('Jieva', 'Negrisiu'));
      expect(splitArtistTitle('Zdob și Zdub — La mijloc'), (
        'Zdob și Zdub',
        'La mijloc',
      ));
      expect(splitArtistTitle('A-ha - Take On Me'), ('A-ha', 'Take On Me'));
    });

    test('bare separator only as a fallback', () {
      expect(splitArtistTitle('Emade-Pierwszy stopień'), (
        'Emade',
        'Pierwszy stopień',
      ));
    });

    test('no separator: whole name is the title', () {
      expect(splitArtistTitle('Untitled'), (null, 'Untitled'));
    });
  });

  test(
    'version 24 makes keys of normalised names again: "ё" is "е" now',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('local_library_v23');
      final sync = DatabaseSync(storageRoot: () async => root);
      final catalog = SongCatalog(sync);
      final dir = await Directory('${root.path}/local').create();
      var db = await databaseFactoryFfi.openDatabase('${dir.path}/local.db');
      // Only what the upgrade touches, with keys as version 23 made them.
      await db.execute(
        'CREATE TABLE mood_tracks (mood_id INTEGER NOT NULL, '
        'track_key VARCHAR NOT NULL, title VARCHAR NOT NULL, artist VARCHAR, '
        'PRIMARY KEY (mood_id, track_key))',
      );
      await db.execute(
        'CREATE TABLE youtube_track_matches (track_key VARCHAR PRIMARY KEY, '
        'video_id VARCHAR NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE youtube_not_found (not_found_key VARCHAR PRIMARY KEY, '
        'checked_at INTEGER NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE cover_lookups (cover_key VARCHAR NOT NULL, '
        'source VARCHAR NOT NULL, PRIMARY KEY (cover_key, source))',
      );
      for (final (mood, key, title) in [
        (1, 'бумбокс|вахтёрам', 'Вахтёрам'),
        // Already there under the new key: one row stays.
        (2, 'бумбокс|вахтёрам', 'Вахтёрам'),
        (2, 'бумбокс|вахтерам', 'Вахтерам'),
        (1, 'kult|arahja', 'Arahja'),
      ]) {
        await db.insert('mood_tracks', {
          'mood_id': mood,
          'track_key': key,
          'title': title,
        });
      }
      await db.insert('youtube_track_matches', {
        'track_key': 'бумбокс\nлетний',
        'video_id': 'v',
      });
      await db.insert('youtube_not_found', {
        'not_found_key': 'track:їжак\nёлка',
        'checked_at': 1,
      });
      await db.insert('youtube_not_found', {
        'not_found_key': 'db:5',
        'checked_at': 1,
      });
      for (final key in [
        'album:бумбокс|ёлка',
        'video:бумбокс|ёлка',
        'https://example.com/ёлка.jpg',
      ]) {
        await db.insert('cover_lookups', {
          'cover_key': key,
          'source': 'itunes',
        });
      }
      await db.setVersion(23);
      await db.close();

      final upgraded = LocalLibrary(
        catalog,
        storageRoot: () async => root,
        factoryOverride: databaseFactoryFfi,
      );
      db = await upgraded.database();
      expect(
        [
          for (final r in await db.query(
            'mood_tracks',
            orderBy: 'mood_id, title',
          ))
            (r['mood_id'], r['track_key']),
        ],
        [(1, 'kult|arahja'), (1, 'бумбокс|вахтерам'), (2, 'бумбокс|вахтерам')],
      );
      expect(
        (await db.query('youtube_track_matches')).single['track_key'],
        'бумбокс\nлетнии',
      );
      expect(
        {
          for (final r in await db.query('youtube_not_found'))
            r['not_found_key'],
        },
        {'track:іжак\nелка', 'db:5'},
      );
      expect(
        {for (final r in await db.query('cover_lookups')) r['cover_key']},
        {
          'album:бумбокс|елка',
          'video:бумбокс|елка',
          'https://example.com/ёлка.jpg',
        },
      );
      upgraded.dispose();
      catalog.dispose();
      sync.dispose();
      await root.delete(recursive: true);
    },
  );

  group('LocalLibrary', () {
    late Directory root;
    late Directory music;
    late DatabaseSync sync;
    late SongCatalog catalog;
    late LocalLibrary library;

    Future<File> touch(String relative) =>
        File('${music.path}/$relative').create(recursive: true);

    LocalLibrary newLibrary(SongCatalog catalog) => LocalLibrary(
      catalog,
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('local_library_test');
      music = await Directory('${root.path}/Music').create();
      sync = DatabaseSync(storageRoot: () async => root);
      await writeMusicDb((await sync.localFile('music.db')).path);
      catalog = SongCatalog(sync);
      library = newLibrary(catalog);
      await library.load();
    });

    tearDown(() async {
      library.dispose();
      catalog.dispose();
      sync.dispose();
      await root.delete(recursive: true);
    });

    test('scan adds audio files, linking known songs and marking new ones pending', () async {
      // Empty files have no tags, so artist and title come from the file name.
      await touch('Dawid Podsiadlo - MAŁOMIASTECZKOWY.mp3');
      await touch('sub/Led Zeppelin - Going to California.flac');
      await touch('Nieznany Zespół - Nowość.mp3');
      await touch('okładka.jpg');
      await library.addFolder(music.path);

      final result = await library.scan();
      expect(result.added, 3);
      expect(result.newPending, 1);
      expect(result.mainDatabaseAvailable, isTrue);
      expect(library.songCount, 3);
      expect(library.pendingCount, 1);

      final pending = await library.pendingSongs();
      expect(pending.single.title, 'Nowość');
      expect(pending.single.artist, 'Nieznany Zespół');
      expect(pending.single.mainDbId, isNull);
    });

    test('the scan leaves out the folder "Pobierz" puts songs in', () async {
      final scanning = LocalLibrary(
        catalog,
        storageRoot: () async => root,
        factoryOverride: databaseFactoryFfi,
        downloadFolder: () => '${music.path}/Leina Player',
      );
      await scanning.load();
      await touch('Afina - Pay Your Respect.mp3');
      await touch('Leina Player/Kino - Kukushka.webm');
      await touch('Leina Player 2/Kino - Kukushka.mp3');
      await scanning.addFolder(music.path);
      expect((await scanning.scan()).added, 2);
      scanning.dispose();
    });

    test('a rescan adds only new files and drops deleted ones', () async {
      final known = await touch('Dawid Podsiadło - Małomiasteczkowy.mp3');
      await library.addFolder(music.path);
      await library.scan();

      await known.delete();
      await touch('Afina - Pay Your Respect.mp3');
      final result = await library.scan();
      expect(result.added, 1);
      expect(result.removed, 1);
      expect(library.songCount, 1);
      expect(library.pendingCount, 0);
    });

    test(
      'a file gone before a rescan is forgotten when played; a scan finds it '
      'again',
      () async {
        final gone = await touch('Dawid Podsiadło - Małomiasteczkowy.mp3');
        await library.addFolder(music.path);
        await library.scan();

        await library.forgetGone(gone.path);
        expect(library.songCount, 0);
        expect(library.fileAt(gone.path), isNull);

        expect((await library.scan()).added, 1);
        expect(library.fileAt(gone.path), isNotNull);
      },
    );

    test('pending files are re-checked once MusicDatabase has them', () async {
      await touch('Dawid Podsiadło - Nowa.mp3');
      await library.addFolder(music.path);
      await library.scan();
      expect(library.pendingCount, 1);

      final db = await databaseFactoryFfi.openDatabase(
        (await sync.localFile('music.db')).path,
      );
      await db.rawInsert(
        "INSERT INTO songs VALUES (6, 'Nowa', NULL, NULL, NULL, 1, NULL)",
      );
      await db.close();

      // A fresh catalog reads the updated music.db (in the app a download triggers this).
      library.dispose();
      final updated = SongCatalog(sync);
      addTearDown(updated.dispose);
      library = newLibrary(updated);
      await library.load();
      await library.scan();
      expect(library.pendingCount, 0);
      expect(library.songCount, 1);
    });

    test('without a downloaded database every file is pending', () async {
      await (await sync.localFile('music.db')).delete();
      library.dispose();
      final empty = SongCatalog(sync);
      addTearDown(empty.dispose);
      library = newLibrary(empty);
      await library.load();

      await touch('Dawid Podsiadło - Małomiasteczkowy.mp3');
      await library.addFolder(music.path);
      final result = await library.scan();
      expect(result.mainDatabaseAvailable, isFalse);
      expect(library.pendingCount, 1);
    });

    test('folders and counts survive a restart', () async {
      await touch('Nieznany - Coś.mp3');
      await library.addFolder('${music.path}/');
      await library.scan();

      library.dispose();
      library = newLibrary(catalog);
      await library.load();
      expect(library.folders, [music.path]);
      expect(library.songCount, 1);
      expect(library.pendingCount, 1);
      expect(library.lastScan, isNotNull);
    });

    test(
      'search covers MusicDatabase and phone-only songs, marking sources',
      () async {
        await touch('Dawid Podsiadło - Małomiasteczkowy.mp3');
        await touch('Dawid Podsiadło - Małomiasteczkowy demo.mp3');
        await library.addFolder(music.path);
        await library.scan();

        final hits = searchEverywhere('małomiasteczkowy', catalog, library);
        expect(hits.map((h) => h.title), [
          'Małomiasteczkowy',
          'Małomiasteczkowy demo',
        ]);

        final inBoth = hits[0];
        expect(inBoth.inMainDatabase, isTrue);
        expect(inBoth.onPhone, isTrue);
        expect(inBoth.pending, isFalse);

        final phoneOnly = hits[1];
        expect(phoneOnly.inMainDatabase, isFalse);
        expect(phoneOnly.pending, isTrue);
        expect(phoneOnly.artistLabel, 'Dawid Podsiadło');

        // MusicDatabase-only songs have no phone files.
        final dbOnly = searchEverywhere('california', catalog, library);
        expect(dbOnly, isNotEmpty);
        expect(dbOnly.every((h) => h.inMainDatabase && !h.onPhone), isTrue);
      },
    );

    test('phone-only songs follow the search field filters', () async {
      await touch('Nieznany Zespół - Nowość.mp3');
      await library.addFolder(music.path);
      await library.scan();
      await catalog.setSearchFields({SearchField.title});
      expect(searchEverywhere('zespol', catalog, library), isEmpty);
      await catalog.setSearchFields({SearchField.artist});
      expect(
        searchEverywhere('zespol', catalog, library).single.pending,
        isTrue,
      );
    });
  });
}
