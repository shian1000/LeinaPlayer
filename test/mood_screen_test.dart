import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/moods.dart';
import 'package:music_database_app/src/data/playlist_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:music_database_app/src/screens/mood_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/widgets/mood_sheet.dart';
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
  late PlaylistLibrary playlists;
  late MoodLibrary moods;
  late SourceSettings settings;
  late PlayerController player;
  late PlaybackQueue queue;

  final video = SearchHit.youTubeOnly(
    title: 'Spoza bazy',
    artistLabel: 'Ktoś',
    videoId: 'outsideVid1',
    playlistVideoId: 'outsideVid1',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() async {
    queue.dispose();
    player.dispose();
    moods.dispose();
    playlists.dispose();
    youTubeLibrary.dispose();
    library.dispose();
    catalog.dispose();
    sync.dispose();
    settings.dispose();
    await storage.delete(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    await tester.runAsync(() async {
      storage = await Directory.systemTemp.createTemp('mood_screen_test');
      sync = DatabaseSync(storageRoot: () async => storage);
      await writeMusicDb((await sync.localFile('music.db')).path);
      await writeTagDb(
        (await sync.localFile('tag.db')).path,
        tags: {
          1: ('Globalny', 'mood', [1]),
        },
      );
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
      moods = MoodLibrary(
        library.database,
        sync,
        factoryOverride: databaseFactoryFfi,
        userName: () => 'tester',
        authToken: () => 'tok',
        canEditGlobal: () => true,
        catalog: catalog,
      );
      settings = SourceSettings();
      player = PlayerController();
      await catalog.ensureLoaded();
      await library.load();
      await youTubeLibrary.load();
      await playlists.load();
      await moods.load();
      await settings.load();
      await moods.create('Chill', songIds: [1], hits: [video]);
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
                child: MoodLibraryScope(
                  notifier: moods,
                  child: PlayerScope(
                    notifier: player,
                    child: PlaybackQueueScope(
                      notifier: queue,
                      child: SourceSettingsScope(
                        notifier: settings,
                        child: YouTubeScope(
                          search: YouTubeSearch(),
                          audio: YouTubeAudio(newPipeAvailable: false),
                          playlists: YouTubePlaylists(newPipeAvailable: false),
                          child: MaterialApp(
                            theme: buildAppTheme(dummifyTheme),
                            home: home,
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
      ),
    );
    await tester.pump();
  }

  testWidgets('the mood picker takes a song outside music.db, own moods only', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMoodPicker(context, video),
            child: const Text('otwórz'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('otwórz'));
    await tester.pumpAndSettle();

    expect(find.text('Chill'), findsOneWidget);
    expect(find.text('Globalny'), findsNothing);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );

    await tester.tap(find.text('Chill'));
    await pumpUntil(tester, () => moods.userMoods.single.tracks.isEmpty);
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
  });

  testWidgets('the mood picker searches the moods by name', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMoodPicker(context, video),
            child: const Text('otwórz'),
          ),
        ),
      ),
    );
    await tester.runAsync(() => moods.create('Siłownia'));
    await tester.tap(find.text('otwórz'));
    await tester.pumpAndSettle();
    expect(find.text('Chill'), findsOneWidget);
    expect(find.text('Siłownia'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'siło');
    await tester.pump();
    expect(find.text('Chill'), findsNothing);
    expect(find.text('Siłownia'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bieganie');
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      find.text('Żaden nastrój nie pasuje do „bieganie”.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Nowy nastrój'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('bieganie'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the mood screen lists such a song and takes it out', (
    tester,
  ) async {
    late Mood mood;
    await pumpApp(
      tester,
      Builder(
        builder: (context) {
          mood = MoodLibraryScope.of(context).userMoods.single;
          return MoodScreen(mood: mood);
        },
      ),
    );
    await pumpUntil(
      tester,
      () => find.text('Spoza bazy').evaluate().isNotEmpty,
    );
    expect(find.text('Małomiasteczkowy'), findsWidgets);

    await tester.tap(find.byTooltip('Menu utworu (⋮)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń z tego nastroju'));
    await pumpUntil(tester, () => moods.userMoods.single.tracks.isEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Spoza bazy'), findsNothing);
    expect(moods.userMoods.single.songIds, {1});
  });
}
