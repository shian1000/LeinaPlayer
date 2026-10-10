import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/text_normalizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';

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
        "INSERT INTO songs VALUES (6, 'Nowa', NULL, NULL, NULL, 1)",
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
      for (var i = 0; i < 100 && catalog.search('nowa').isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
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
      for (var i = 0; i < 50 && again.searchFields.length != 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(again.searchFields, {SearchField.year, SearchField.title});
    });
  });
}
