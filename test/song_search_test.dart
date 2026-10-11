import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/screens/song_search_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/fixtures.dart';

/// Audio backend that only records what was opened.
class _FakeBackend implements AudioBackend {
  final opened = <String>[];

  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration?> get duration => const Stream.empty();
  @override
  Stream<({bool playing, bool completed})> get state => const Stream.empty();
  @override
  Future<void> open(NowPlaying track) async => opened.add(track.source);

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  sqfliteFfiInit();

  late Directory storage;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary library;
  late SourceSettings settings;
  late YouTubeLibrary youTubeLibrary;
  late PlayerController player;
  late List<String> searches;
  late _FakeBackend backend;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    searches = [];
  });

  tearDown(() async {
    player.dispose();
    youTubeLibrary.dispose();
    library.dispose();
    catalog.dispose();
    sync.dispose();
    settings.dispose();
    await storage.delete(recursive: true);
  });

  Future<void> pumpSearch(WidgetTester tester, {bool youTube = true}) async {
    await tester.runAsync(() async {
      storage = await Directory.systemTemp.createTemp('song_search_test');
      sync = DatabaseSync(storageRoot: () async => storage);
      catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      library = LocalLibrary(
        catalog,
        storageRoot: () async => storage,
        factoryOverride: databaseFactoryFfi,
      );
      settings = SourceSettings();
      youTubeLibrary = YouTubeLibrary(
        library.database,
        storageRoot: () async => storage,
      );
      backend = _FakeBackend();
      player = PlayerController(backend: () => backend);
      await writeMusicDb((await sync.localFile('music.db')).path);
      await catalog.ensureLoaded();
      await library.load();
      await youTubeLibrary.load();
      await settings.load();
      await settings.setYouTubeSearchEnabled(youTube);
    });
    final search = YouTubeSearch(
      explode: (q) async {
        searches.add(q);
        return [
          YouTubeVideo(
            id: 'vid1',
            title: '$q (Official Video)',
            channel: 'Kanał',
            duration: const Duration(minutes: 3, seconds: 5),
          ),
        ];
      },
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
                child: SourceSettingsScope(
                  notifier: settings,
                  child: YouTubeScope(
                    search: search,
                    playlists: YouTubePlaylists(),
                    audio: YouTubeAudio(
                      newPipeAvailable: true,
                      newPipe: (id) async => [
                        YouTubeAudioStream(
                          url: 'https://stream.test/$id/140',
                          itag: 140,
                          bitrate: 128,
                        ),
                        YouTubeAudioStream(
                          url: 'https://stream.test/$id/251',
                          itag: 251,
                          bitrate: 160,
                        ),
                      ],
                    ),
                    child: MaterialApp(
                      theme: buildAppTheme(dummifyTheme),
                      home: const SongSearchScreen(),
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
  }

  /// Lets real file/SQLite work started by a tap (the YouTube cache) finish, then settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
  }

  /// The result row titled [title] (the search field holds the same text).
  Finder row(String title) =>
      find.descendant(of: find.byType(ListTile), matching: find.text(title));

  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'YouTube icon: full with a stored link, dimmed without, none for N/A',
    (tester) async {
      await pumpSearch(tester);

      await type(tester, 'Małomiasteczkowy');
      expect(find.byTooltip('Na YouTube'), findsOneWidget);

      await type(tester, 'California');
      expect(find.byTooltip('Do wyszukania na YouTube'), findsNWidgets(2));

      await type(tester, 'Pay Your Respect');
      expect(find.byTooltip('Na YouTube'), findsNothing);
      expect(find.byTooltip('Do wyszukania na YouTube'), findsNothing);
    },
  );

  testWidgets('YouTube is searched only after tapping the button', (
    tester,
  ) async {
    await pumpSearch(tester);

    await type(tester, 'California');
    expect(find.text('Wyszukaj na YouTubie'), findsOneWidget);
    expect(searches, isEmpty);

    await tester.tap(find.text('Wyszukaj na YouTubie'));
    await tester.pumpAndSettle();
    expect(searches, ['California']);
    expect(find.text('YouTube: 1'), findsOneWidget);
    expect(find.text('California (Official Video)'), findsOneWidget);
    expect(find.text('Kanał • 3:05'), findsOneWidget);

    await tester.tap(find.text('California (Official Video)'));
    await settle(tester);
    expect(backend.opened, ['https://stream.test/vid1/251']);

    // A changed query drops the results that belonged to the old one.
    await type(tester, 'Californi');
    expect(find.text('Wyszukaj na YouTubie'), findsOneWidget);
    expect(find.text('California (Official Video)'), findsNothing);
  });

  testWidgets('no YouTube button while YouTube search is off', (tester) async {
    await pumpSearch(tester, youTube: false);
    await type(tester, 'California');
    expect(find.text('Wyszukaj na YouTubie'), findsNothing);
  });

  testWidgets(
    'tapping a song: plays a stored link, searches YouTube, or is unavailable',
    (tester) async {
      await pumpSearch(tester);

      await type(tester, 'Małomiasteczkowy');
      await tester.showKeyboard(find.byType(TextField));
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(row('Małomiasteczkowy'));
      await settle(tester);
      // Choosing a song hides the keyboard.
      expect(tester.testTextInput.isVisible, isFalse);
      // Stored link: plays the video's Opus stream (itag 251) found through NewPipe.
      expect(backend.opened, ['https://stream.test/X2XWBcd5jn0/251']);
      expect(player.current?.youtubeVideoId, 'X2XWBcd5jn0');
      expect(player.current?.title, 'Małomiasteczkowy');

      await type(tester, 'Going to California');
      await tester.tap(row('Going to California'));
      await settle(tester);
      // No stored link: searched by main artist + title, the best-scoring result is played.
      expect(searches, ['Led Zeppelin Going to California']);
      expect(backend.opened.last, 'https://stream.test/vid1/251');
      expect(find.textContaining('Z YouTube:'), findsOneWidget);

      await type(tester, 'Pay Your Respect');
      await tester.tap(row('Pay Your Respect'));
      await tester.pumpAndSettle();
      expect(find.textContaining('niedostępny'), findsOneWidget);
    },
  );

  testWidgets(
    'a song the phone matched gets a full icon, and plays from the cache next time',
    (tester) async {
      await pumpSearch(tester);

      await type(tester, 'Going to California');
      expect(find.byTooltip('Do wyszukania na YouTube'), findsOneWidget);
      await tester.tap(row('Going to California'));
      await settle(tester);
      expect(searches, hasLength(1));
      expect(youTubeLibrary.matchFor(2), 'vid1');
      expect(
        find.byTooltip('Na YouTube (znalezione przez telefon)'),
        findsOneWidget,
      );
      expect(backend.opened.last, 'https://stream.test/vid1/251');

      // The real download can't reach the fake stream address here; stand in for it.
      late String saved;
      await tester.runAsync(() async {
        final file = await youTubeLibrary.newCacheFile('vid1', 'webm');
        await file.writeAsBytes([1, 2, 3]);
        await youTubeLibrary.cacheComplete('vid1', file, 25);
        saved = file.path;
      });
      expect(youTubeLibrary.cachedCount, 1);

      // Second tap: no new search, played from the file.
      await tester.tap(row('Going to California'));
      await settle(tester);
      expect(searches, hasLength(1));
      expect(backend.opened.last, saved);
    },
  );
}
