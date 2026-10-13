import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/outbox.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:music_database_app/src/screens/database_source_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/fixtures.dart';
import 'support/waiting.dart';

void main() {
  sqfliteFfiInit();

  late Directory storage;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary library;
  late YouTubeLibrary youTubeLibrary;
  late SourceSettings settings;
  late PlayerController player;
  late PlaybackQueue queue;
  late Outbox outbox;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() async {
    queue.dispose();
    player.dispose();
    outbox.dispose();
    youTubeLibrary.dispose();
    library.dispose();
    catalog.dispose();
    sync.dispose();
    settings.dispose();
    await storage.delete(recursive: true);
  });

  testWidgets(
    '"Czeka na wysłanie" opens the reported songs with their replacements',
    (tester) async {
      await tester.runAsync(() async {
        storage = await Directory.systemTemp.createTemp('outbox_screen_test');
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
        outbox = Outbox(
          storageRoot: () async => storage,
          factoryOverride: databaseFactoryFfi,
        );
        settings = SourceSettings();
        player = PlayerController();
        await writeMusicDb((await sync.localFile('music.db')).path);
        await catalog.ensureLoaded();
        await library.load();
        await youTubeLibrary.load();
        await settings.load();
        await outbox.load();
        final song = catalog.byId(1)!;
        await outbox.reportDeadYouTubeLink(song, 'X2XWBcd5jn0');
        await outbox.reportReplacement(
          song,
          'X2XWBcd5jn0',
          const YouTubeVideo(
            id: 'newVideo123',
            title: 'Małomiasteczkowy (Official Video)',
            channel: 'Dawid Podsiadło',
          ),
        );
        // A song music.db no longer has: shown as the phone reported it.
        await outbox.reportDeadYouTubeLink(
          CatalogSong(id: 999, title: 'Usunięty', artistLabel: 'Ktoś'),
          'goneVideo12',
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
                child: OutboxScope(
                  notifier: outbox,
                  child: PlayerScope(
                    notifier: player,
                    child: PlaybackQueueScope(
                      notifier: queue,
                      child: SourceSettingsScope(
                        notifier: settings,
                        child: MaterialApp(
                          theme: buildAppTheme(dummifyTheme),
                          home: const DatabaseSourceScreen(),
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
      await tester.pumpAndSettle();

      final waiting = find.text('Czeka na wysłanie');
      await tester.dragUntilVisible(
        waiting,
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 zgłoszenie'), findsOneWidget);
      await tester.tap(waiting);
      await pumpUntil(
        tester,
        () => find.text('Usunięty').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(find.text('Małomiasteczkowy'), findsOneWidget);
      expect(
        find.text(
          'Dawid Podsiadło · Zamiennik: Małomiasteczkowy (Official Video) '
          '(Dawid Podsiadło)',
        ),
        findsOneWidget,
      );
      expect(find.text('Ktoś · Bez zamiennika'), findsOneWidget);
    },
  );
}
