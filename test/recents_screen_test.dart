import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/play_history.dart';
import 'package:music_database_app/src/data/playlist_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/track_ref.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:music_database_app/src/screens/recents_screen.dart';
import 'package:music_database_app/src/screens/song_search_screen.dart';
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
  late PlaylistLibrary playlists;
  late SourceSettings settings;
  late PlayerController player;
  late PlaybackQueue queue;
  late PlayHistory history;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await Directory.systemTemp.createTemp('recents_screen_test');
  });

  tearDown(() async {
    history.dispose();
    queue.dispose();
    player.dispose();
    playlists.dispose();
    youTubeLibrary.dispose();
    library.dispose();
    catalog.dispose();
    sync.dispose();
    settings.dispose();
    await storage.delete(recursive: true);
  });

  /// Two songs played today, and [yesterday] played the day before.
  Future<void> pumpRecents(WidgetTester tester, String yesterday) async {
    await tester.runAsync(() async {
      sync = DatabaseSync(storageRoot: () async => storage);
      catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      library = LocalLibrary(
        catalog,
        storageRoot: () async => storage,
        factoryOverride: databaseFactoryFfi,
      );
      youTubeLibrary = YouTubeLibrary(
        library.database,
        storageRoot: () async => storage,
      );
      playlists = PlaylistLibrary(library.database, catalog, youTubeLibrary);
      settings = SourceSettings();
      player = PlayerController();
      await catalog.ensureLoaded();
      await library.load();
      await youTubeLibrary.load();
      await playlists.load();
      await settings.load();
      final now = DateTime.now();
      var clock = now.subtract(const Duration(days: 1));
      history = PlayHistory(library.database, now: () => clock);
      await history.load();
      await history.record(TrackRef(title: yesterday, artist: 'Kino'));
      clock = now;
      await history.record(
        const TrackRef(title: 'Małomiasteczkowy', artist: 'Dawid Podsiadło'),
      );
      await history.record(
        const TrackRef(title: 'Gruppa krovi', artist: 'Kino'),
      );
    });
    queue = PlaybackQueue(
      prefetchDelay: Duration.zero,
      TrackPlayer(
        player: player,
        settings: settings,
        youTubeLibrary: youTubeLibrary,
        youTubeAudio: YouTubeAudio(newPipeAvailable: false),
        youTubeSearch: YouTubeSearch(),
      ),
    );
    await tester.pumpWidget(
      DatabaseSyncScope(
        notifier: sync,
        child: SongCatalogScope(
          notifier: catalog,
          child: LocalLibraryScope(
            notifier: library,
            child: YouTubeLibraryScope(
              notifier: youTubeLibrary,
              child: PlaylistLibraryScope(
                notifier: playlists,
                child: PlayerScope(
                  notifier: player,
                  child: PlaybackQueueScope(
                    notifier: queue,
                    child: SourceSettingsScope(
                      notifier: settings,
                      child: PlayHistoryScope(
                        notifier: history,
                        child: MaterialApp(
                          theme: buildAppTheme(dummifyTheme),
                          home: const Scaffold(body: Text('Ja')),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const RecentsScreen()),
    );
    await pumpUntil(tester, () => find.text('Dzisiaj').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'searching keeps matching songs under their days; Back closes it',
    (tester) async {
      await pumpRecents(tester, 'Kukushka');
      expect(find.text('Wczoraj'), findsOneWidget);

      await tester.tap(find.byTooltip('Szukaj w ostatnich'));
      await tester.pumpAndSettle();

      // Accents ignored; a day with nothing left goes.
      await tester.enterText(find.byType(TextField), 'malomiast');
      await tester.pumpAndSettle();
      expect(find.text('Małomiasteczkowy'), findsOneWidget);
      expect(find.text('Gruppa krovi'), findsNothing);
      expect(find.text('Dzisiaj'), findsOneWidget);
      expect(find.text('Wczoraj'), findsNothing);

      // By artist, across days.
      await tester.enterText(find.byType(TextField), 'kino');
      await tester.pumpAndSettle();
      expect(find.text('Gruppa krovi'), findsOneWidget);
      expect(find.text('Kukushka'), findsOneWidget);
      expect(find.text('Małomiasteczkowy'), findsNothing);
      expect(find.text('Wczoraj'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'xyz');
      await tester.pumpAndSettle();
      expect(find.text('Brak wyników dla „xyz”'), findsOneWidget);

      // The query carries over to song search over the whole database.
      await tester.tap(find.byTooltip('Szukaj w całej bazie'));
      await tester.pumpAndSettle();
      expect(find.byType(SongSearchScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(SongSearchScreen))).pop();
      await tester.pumpAndSettle();

      Navigator.of(tester.element(find.byType(RecentsScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(RecentsScreen), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Małomiasteczkowy'), findsOneWidget);
      expect(find.text('Wczoraj'), findsOneWidget);
    },
  );
}
