import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/listening_log.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:music_database_app/src/screens/listening_stats_screen.dart';
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
  late ListeningLog log;

  tearDown(() async {
    queue.dispose();
    player.dispose();
    log.dispose();
    youTubeLibrary.dispose();
    library.dispose();
    catalog.dispose();
    sync.dispose();
    settings.dispose();
    await storage.delete(recursive: true);
  });

  testWidgets('sums up the plays of the period picked', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var clock = DateTime.now();
    await tester.runAsync(() async {
      storage = await Directory.systemTemp.createTemp('stats_screen_test');
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
      settings = SourceSettings();
      player = PlayerController();
      log = ListeningLog(library.database, now: () => clock);
      await writeMusicDb((await sync.localFile('music.db')).path);
      await catalog.ensureLoaded();
      await library.load();
      await youTubeLibrary.load();

      Future<void> play(int songId, String title, int seconds) async {
        await log.start(
          title: title,
          artist: 'x',
          songId: songId,
          source: ListenSource.phone,
        );
        await log.listened(Duration(seconds: seconds));
        await log.finish();
      }

      // Two months ago: only in the longer periods.
      clock = DateTime.now().subtract(const Duration(days: 60));
      await play(2, 'Going to California', 240);
      clock = DateTime.now().subtract(const Duration(days: 1));
      await play(1, 'Małomiasteczkowy', 180);
      await play(1, 'Małomiasteczkowy', 120);
      await play(1, 'Małomiasteczkowy', 60);
      await play(2, 'Going to California', 10);
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
              child: PlayerScope(
                notifier: player,
                child: PlaybackQueueScope(
                  notifier: queue,
                  child: SourceSettingsScope(
                    notifier: settings,
                    child: ListeningLogScope(
                      notifier: log,
                      child: MaterialApp(
                        theme: buildAppTheme(dummifyTheme),
                        home: const ListeningStatsScreen(),
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

    await pumpUntil(tester, () => find.text('6 minut').evaluate().isNotEmpty);
    expect(find.text('6 minut'), findsOneWidget);
    expect(find.text('3 odtworzenia • 1 utwór • 1 wykonawca'), findsOneWidget);
    // Three plays in the week: the song of the week, on top.
    expect(find.text('Utwór tygodnia'), findsOneWidget);
    expect(
      find.text('„Małomiasteczkowy” • Dawid Podsiadło • 3 odtw.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Going to California'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Małomiasteczkowy'), findsOneWidget);
    expect(find.text('Going to California'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pump();
    await tester.tap(find.text('Od początku'));
    await pumpUntil(tester, () => find.text('10 minut').evaluate().isNotEmpty);
    expect(
      find.text('4 odtworzenia • 2 utwory • 2 wykonawców'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Lata 70.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Lata 70.'), findsOneWidget);
    expect(find.text('2010–2019'), findsOneWidget);

    // This year's summary, card by card to the one to share.
    final year = DateTime.now().subtract(const Duration(days: 1)).year;
    await tester.scrollUntilVisible(
      find.text('Rok $year'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    // scrollUntilVisible ends with an ensureVisible jump but no frame: without this pump the
    // tap hits where the last drag left the card. That place depends on the hour (the drags
    // start over the hour chart, and over a bar with plays they lose the touch slop to its
    // Tooltip) – at 12:xx it was under the app bar.
    await tester.pump();
    await tester.tap(find.text('Rok $year'));
    await tester.pumpAndSettle();
    expect(find.text('Twój rok $year'), findsOneWidget);
    expect(find.text('Udostępnij'), findsNothing);
    for (var i = 0; i < 12 && find.text('Udostępnij').evaluate().isEmpty; i++) {
      await tester.tapAt(const Offset(700, 300));
      await tester.pumpAndSettle();
    }
    expect(find.text('Udostępnij'), findsOneWidget);
    expect(find.text('1. Małomiasteczkowy'), findsOneWidget);
  });
}
