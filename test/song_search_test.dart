import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/playlist_library.dart';
import 'package:music_database_app/src/data/playlist_search.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/spotify_playlist.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:music_database_app/src/widgets/song_tile.dart';
import 'package:music_database_app/src/screens/song_search_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/fixtures.dart';
import 'support/spotify_fakes.dart';
import 'support/waiting.dart';

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
  Stream<MediaSkip> get skips => const Stream.empty();
  @override
  Future<void> open(NowPlaying track) async => opened.add(track.source);

  @override
  Future<void> crossfadeTo(NowPlaying track, Duration fade) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> fadeOutAndPause(Duration fade) => pause();
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
  late PlaylistLibrary playlists;
  late FakeSpotify spotify;
  late PlayerController player;
  late List<String> searches;
  late _FakeBackend backend;
  late PlaybackQueue queue;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    searches = [];
  });

  tearDown(() async {
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

  Future<void> pumpSearch(
    WidgetTester tester, {
    bool youTube = true,
    bool spotifyPlaylists = false,
  }) async {
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
      playlists = PlaylistLibrary(library.database, catalog, youTubeLibrary);
      spotify = FakeSpotify();
      backend = _FakeBackend();
      player = PlayerController(backend: () => backend);
      await writeMusicDb((await sync.localFile('music.db')).path);
      await catalog.ensureLoaded();
      await library.load();
      await youTubeLibrary.load();
      await playlists.load();
      await settings.load();
      await settings.setYouTubeSearchEnabled(youTube);
      await settings.setSpotifyPlaylistSearch(spotifyPlaylists);
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
      explodePlaylists: (q) async {
        searches.add('playlists: $q');
        return [
          FoundPlaylist(
            source: PlaylistSource.youtube,
            id: 'PLrock',
            name: '$q — składanka',
            owner: 'Kanał',
            trackCount: 12,
          ),
        ];
      },
    );
    final audio = YouTubeAudio(
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
    );
    queue = PlaybackQueue(
      prefetchDelay: Duration.zero,
      TrackPlayer(
        player: player,
        settings: settings,
        youTubeLibrary: youTubeLibrary,
        youTubeAudio: audio,
        youTubeSearch: search,
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
                      child: YouTubeScope(
                        search: search,
                        playlists: YouTubePlaylists(),
                        spotify: SpotifyPlaylists(
                          get: spotify.get,
                          call: spotify.call,
                        ),
                        audio: audio,
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
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lets real file/SQLite work started by a tap (searching, the YouTube cache) run until
  /// [until] holds, then settles.
  Future<void> settle(
    WidgetTester tester, {
    required bool Function() until,
  }) async {
    await pumpUntil(tester, until);
    await tester.pumpAndSettle();
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
    expect(searches, ['California', 'playlists: California']);
    expect(find.text('YouTube: 1'), findsOneWidget);
    expect(find.text('Playlisty na YouTube: 1'), findsOneWidget);
    expect(find.text('California — składanka'), findsOneWidget);
    // The video's title without its junk bracket; the channel as the artist.
    expect(find.text('California (Official Video)'), findsNothing);
    expect(find.text('Kanał • 3:05'), findsOneWidget);

    await tester.tap(find.text('Kanał • 3:05'));
    await settle(tester, until: () => backend.opened.isNotEmpty);
    expect(backend.opened, ['https://stream.test/vid1/251']);

    // A changed query drops the results that belonged to the old one.
    await type(tester, 'Californi');
    expect(find.text('Wyszukaj na YouTubie'), findsOneWidget);
    expect(find.text('Kanał • 3:05'), findsNothing);
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
      await settle(tester, until: () => backend.opened.isNotEmpty);
      // Choosing a song hides the keyboard.
      expect(tester.testTextInput.isVisible, isFalse);
      // Stored link: plays the video's Opus stream (itag 251) found through NewPipe.
      expect(backend.opened, ['https://stream.test/X2XWBcd5jn0/251']);
      expect(player.current?.youtubeVideoId, 'X2XWBcd5jn0');
      expect(player.current?.title, 'Małomiasteczkowy');

      await type(tester, 'Going to California');
      await tester.tap(row('Going to California'));
      await settle(
        tester,
        until: () => find.textContaining('Z YouTube:').evaluate().isNotEmpty,
      );
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

  testWidgets('the queue button queues every found song in the list\'s order', (
    tester,
  ) async {
    await pumpSearch(tester);
    expect(find.byTooltip('Utwórz kolejkę z wyników'), findsNothing);

    await type(tester, 'California');
    final shown = [
      for (final tile in tester.widgetList<SongTile>(find.byType(SongTile)))
        tile.hit.title,
    ];
    expect(shown, hasLength(2));
    await tester.tap(find.byTooltip('Utwórz kolejkę z wyników'));
    await settle(tester, until: () => backend.opened.isNotEmpty);
    expect(searches, isNot(contains('California')));
    expect([
      queue.current?.title,
      for (final entry in queue.upcoming) entry.hit.title,
    ], shown);
  });

  testWidgets(
    'a song the phone matched gets a full icon, and plays from the cache next time',
    (tester) async {
      await pumpSearch(tester);

      await type(tester, 'Going to California');
      expect(find.byTooltip('Do wyszukania na YouTube'), findsOneWidget);
      await tester.tap(row('Going to California'));
      await settle(
        tester,
        until: () =>
            youTubeLibrary.matchFor(2) != null && backend.opened.isNotEmpty,
      );
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
      final playedBefore = backend.opened.length;
      await tester.tap(row('Going to California'));
      await settle(tester, until: () => backend.opened.length > playedBefore);
      expect(searches, hasLength(1));
      expect(backend.opened.last, saved);
    },
  );

  testWidgets(
    'albums show while typing and open their songs; Singles is no album',
    (tester) async {
      await pumpSearch(tester);

      await type(tester, 'zeppelin iv');
      expect(find.text('Albumy: 1'), findsOneWidget);
      expect(find.text('Led Zeppelin IV'), findsOneWidget);
      expect(find.text('1 utw.'), findsOneWidget);

      await tester.tap(find.text('Led Zeppelin IV'));
      await tester.pumpAndSettle();
      expect(find.text('Going to California'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await type(tester, 'singles');
      expect(find.textContaining('Albumy'), findsNothing);

      await type(tester, 'zeppelin iv');
      await tester.runAsync(() => settings.setAlbumSearch(false));
      await tester.pumpAndSettle();
      expect(find.textContaining('Albumy'), findsNothing);
    },
  );

  testWidgets(
    'Biblioteka playlists show while typing, unless switched off in filters',
    (tester) async {
      await pumpSearch(tester);
      await tester.runAsync(
        () => playlists.importSpotify(
          const SpotifyPlaylistData(
            id: 'sp1',
            name: 'Rockowe hity',
            owner: 'Ja',
            tracks: [
              SpotifyTrack(
                id: 't1',
                title: 'Kashmir',
                artists: ['Led Zeppelin'],
              ),
            ],
          ),
        ),
      );

      await type(tester, 'rockowe');
      expect(find.text('Playlisty w Bibliotece: 1'), findsOneWidget);
      expect(find.text('Rockowe hity'), findsOneWidget);

      await tester.runAsync(() => settings.setPlaylistSearch(false));
      await tester.pumpAndSettle();
      expect(find.text('Rockowe hity'), findsNothing);
      // Nor does the button look for playlists any more.
      await tester.tap(find.text('Wyszukaj na YouTubie'));
      await tester.pumpAndSettle();
      expect(searches, ['rockowe']);
      expect(find.textContaining('Playlisty na'), findsNothing);
    },
  );

  testWidgets(
    'the button also finds Spotify playlists; one opens as a preview and can be saved',
    (tester) async {
      await pumpSearch(tester, spotifyPlaylists: true);
      spotify.playlists['a' * 22] = embedPage(owner: 'Spotify', [
        track('t1', 'Going to California', 'Led Zeppelin'),
        track('t2', 'Nieznany utwór', 'Ktoś'),
      ]);

      await type(tester, 'rock');
      await tester.tap(find.text('Wyszukaj na YouTubie i Spotify'));
      await settle(
        tester,
        until: () => find.text('Playlisty na Spotify: 2').evaluate().isNotEmpty,
      );
      expect(find.text('Rock Classics'), findsOneWidget);
      expect(find.text('Playlisty na YouTube: 1'), findsOneWidget);

      await tester.tap(find.text('Rock Classics'));
      await settle(
        tester,
        until: () => find.text('Nieznany utwór').evaluate().isNotEmpty,
      );
      // The embed page's name, not the search's.
      expect(find.text('All Out 80s'), findsOneWidget);
      expect(find.text('Going to California'), findsOneWidget);
      expect(playlists.playlists, isEmpty);

      await tester.tap(find.text('Zapisz w Bibliotece'));
      // The screen, not the notifier: it sets `playlists` before it notifies (AGENTS.md).
      await settle(
        tester,
        until: () => find.text('Sortuj').evaluate().isNotEmpty,
      );
      expect(playlists.playlists.single.sourceId, 'a' * 22);
      expect(playlists.playlists.single.trackCount, 2);
      expect(find.text('Zapisz w Bibliotece'), findsNothing);
      // The saved playlist's chips; an imported one is sorted, not edited.
      expect(find.text('Sortuj'), findsOneWidget);
    },
  );
}
