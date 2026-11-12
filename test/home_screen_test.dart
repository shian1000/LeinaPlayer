import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/album_covers.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/home_layout.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/play_history.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/startup_covers.dart';
import 'package:music_database_app/src/data/track_ref.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/screens/home_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/waiting.dart';

void main() {
  sqfliteFfiInit();

  late Directory storage;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary library;
  late YouTubeLibrary youTubeLibrary;
  late PlayHistory history;
  late HomeLayout layout;
  late SourceSettings settings;
  late StartupCovers startup;
  late AlbumCovers covers;

  tearDown(() async {
    covers.dispose();
    settings.dispose();
    layout.dispose();
    history.dispose();
    youTubeLibrary.dispose();
    library.dispose();
    catalog.dispose();
    sync.dispose();
    await storage.delete(recursive: true);
  });

  /// Home with one song played before, its play history not read yet; [lastShown] as
  /// [HomeLayout.lastShown] saved by the last start.
  Future<void> pumpHome(
    WidgetTester tester, {
    Map<String, String>? lastShown,
    Future<void> Function()? prepare,
    bool catalogLoaded = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'home_layout.last_shown': ?(lastShown == null
          ? null
          : jsonEncode(lastShown)),
    });
    await tester.runAsync(() async {
      storage = await Directory.systemTemp.createTemp('home_screen_test');
      sync = DatabaseSync(storageRoot: () async => storage);
      catalog = SongCatalog(sync);
      library = LocalLibrary(
        catalog,
        storageRoot: () async => storage,
        factoryOverride: databaseFactoryFfi,
      );
      youTubeLibrary = YouTubeLibrary(
        library.database,
        storageRoot: () async => storage,
      );
      if (catalogLoaded) await catalog.ensureLoaded();
      await library.load();
      await youTubeLibrary.load();
      final before = PlayHistory(library.database);
      await before.record(
        const TrackRef(title: 'Gruppa krovi', artist: 'Kino'),
      );
      before.dispose();
      layout = HomeLayout(defaults: HomeScreen.defaultSections);
      await layout.load();
      settings = SourceSettings();
      await settings.load();
      startup = StartupCovers(storageRoot: () async => storage);
      covers = AlbumCovers(
        library.database,
        settings,
        storageRoot: () async => storage,
        startup: startup,
        getJson: (_) async => throw const SocketException('offline'),
        getBytes: (_) async => throw const SocketException('offline'),
      );
      await prepare?.call();
    });
    history = PlayHistory(library.database);
    await tester.pumpWidget(
      SongCatalogScope(
        notifier: catalog,
        child: LocalLibraryScope(
          notifier: library,
          child: YouTubeLibraryScope(
            notifier: youTubeLibrary,
            child: PlayHistoryScope(
              notifier: history,
              child: HomeLayoutScope(
                notifier: layout,
                child: AlbumCoversScope(
                  notifier: covers,
                  child: MaterialApp(
                    theme: buildAppTheme(dummifyTheme),
                    home: const Scaffold(body: HomeScreen()),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> loadHistory(WidgetTester tester) async {
    await tester.runAsync(history.load);
    await pumpUntil(
      tester,
      () => find.text('Gruppa krovi').evaluate().isNotEmpty,
    );
  }

  testWidgets('a row shown last time keeps its place while its songs are read, '
      'and is remembered once everything is read', (tester) async {
    await pumpHome(tester, lastShown: {'lib:recent': 'Ostatnio odtwarzane'});
    expect(find.text('Ostatnio odtwarzane'), findsOneWidget);
    expect(find.text('Gruppa krovi'), findsNothing);
    expect(layout.lastShown, {'lib:recent': 'Ostatnio odtwarzane'});

    await loadHistory(tester);
    expect(find.text('Ostatnio odtwarzane'), findsOneWidget);
    expect(layout.lastShown, {'lib:recent': 'Ostatnio odtwarzane'});
  });

  testWidgets(
    'a row not shown last time waits to be read, then is remembered',
    (tester) async {
      await pumpHome(tester);
      expect(find.text('Ostatnio odtwarzane'), findsNothing);

      await loadHistory(tester);
      expect(find.text('Ostatnio odtwarzane'), findsOneWidget);
      await tester.pump();
      expect(layout.lastShown, {'lib:recent': 'Ostatnio odtwarzane'});
    },
  );

  testWidgets(
    'a row shown last time that has nothing now is forgotten once all is read',
    (tester) async {
      await pumpHome(
        tester,
        lastShown: {
          'lib:recent': 'Ostatnio odtwarzane',
          'lib:liked': 'Polubione utwory',
        },
      );
      expect(
        find.text('Polubione utwory'),
        findsNothing,
        reason: 'no liked songs here to read: nothing waits for them',
      );
      await loadHistory(tester);
      await tester.pump();
      expect(layout.lastShown, {'lib:recent': 'Ostatnio odtwarzane'});
    },
  );

  testWidgets('a row still being read shows the cards it showed last time', (
    tester,
  ) async {
    await pumpHome(
      tester,
      lastShown: {'lib:recent': 'Ostatnio odtwarzane'},
      prepare: () async {
        final file = File('${storage.path}/cover.img')..writeAsBytesSync([1]);
        startup.rememberTexts('home:lib:recent#0', 'x', 'Kukushka', 'Kino');
        await startup.remember('home:lib:recent#0', 'x', FileImage(file), 's');
      },
    );
    expect(find.text('Kukushka'), findsOneWidget);
    expect(find.text('Gruppa krovi'), findsNothing);

    await loadHistory(tester);
    expect(find.text('Kukushka'), findsNothing);
    await tester.runAsync(startup.flush);
  });

  testWidgets('before music.db is read, a card of the same song as last time '
      'is named as it was then', (tester) async {
    await pumpHome(
      tester,
      catalogLoaded: false,
      lastShown: {'lib:recent': 'Ostatnio odtwarzane'},
      prepare: () async {
        final file = File('${storage.path}/cover.img')..writeAsBytesSync([1]);
        // What the history keeps, the same before music.db and after.
        final check = const TrackRef(title: 'Gruppa krovi', artist: 'Kino').key;
        startup.rememberTexts(
          'home:lib:recent#0',
          check,
          'Gruppa krovi (Группа крови)',
          'Kino (Кино)',
        );
        await startup.remember(
          'home:lib:recent#0',
          check,
          FileImage(file),
          's',
        );
      },
    );
    await tester.runAsync(history.load);
    await tester.pump();
    expect(history.loaded, isTrue, reason: 'the real card, not the stand-in');
    expect(find.text('Kino (Кино)'), findsOneWidget);
    expect(find.text('Gruppa krovi (Группа крови)'), findsOneWidget);
    expect(find.text('Gruppa krovi'), findsNothing);
    await tester.runAsync(startup.flush);
  });
}
