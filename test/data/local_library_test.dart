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
      catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
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
      final updated = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
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
      final empty = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
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
