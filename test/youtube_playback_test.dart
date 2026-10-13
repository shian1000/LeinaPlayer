import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
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
import 'package:music_database_app/src/playback/youtube_playback.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/waiting.dart';

class _Backend implements AudioBackend {
  final opened = <String>[];
  int failures = 0;
  final _state = StreamController<({bool playing, bool completed})>.broadcast();

  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration?> get duration => const Stream.empty();
  @override
  Stream<({bool playing, bool completed})> get state => _state.stream;
  @override
  Stream<MediaSkip> get skips => const Stream.empty();
  @override
  Future<void> open(NowPlaying track) async {
    opened.add(track.source);
    if (failures > 0) {
      failures--;
      throw Exception('403');
    }
  }

  @override
  Future<void> play() async => _state.add((playing: true, completed: false));
  @override
  Future<void> pause() async => _state.add((playing: false, completed: false));
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary local;
  late YouTubeLibrary library;
  late SourceSettings settings;
  late _Backend backend;
  late PlayerController player;
  late List<String> calls;
  late List<Uri> opened;
  var newPipeFails = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('youtube_playback_test');
    sync = DatabaseSync(storageRoot: () async => root);
    catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    local = LocalLibrary(
      catalog,
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
    );
    library = YouTubeLibrary(local.database, storageRoot: () async => root);
    await library.load();
    settings = SourceSettings();
    await settings.load();
    backend = _Backend();
    player = PlayerController(backend: () => backend);
    calls = [];
    opened = [];
    newPipeFails = false;
  });

  tearDown(() async {
    player.dispose();
    library.dispose();
    local.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  YouTubePlayback playback() => YouTubePlayback(
    audio: YouTubeAudio(
      newPipeAvailable: true,
      newPipe: (id) async {
        calls.add('newPipe');
        if (newPipeFails) throw Exception('403');
        return [YouTubeAudioStream(url: 'https://s/$id', itag: 251)];
      },
    ),
    library: library,
    settings: settings,
    player: player,
    openExternal: (uri) async {
      opened.add(uri);
      return true;
    },
  );

  NowPlaying track(String source) =>
      NowPlaying(title: 'T', artist: 'A', source: source, coverSeed: 's');

  Future<File> cache(String id) async {
    final file = await library.newCacheFile(id, 'webm');
    await file.writeAsBytes([1]);
    await library.cacheComplete(id, file, 25);
    return file;
  }

  test('default order: the cache before streaming', () async {
    final file = await cache('v');
    expect(await playback().play('v', track), YouTubePlayedVia.cache);
    expect(backend.opened, [file.path]);
    expect(calls, isEmpty);
  });

  test('the user\'s order: NewPipe first skips a cached copy', () async {
    await cache('v');
    await settings.setPlaybackMethodOrder([
      YouTubePlaybackMethod.newPipe,
      YouTubePlaybackMethod.cache,
      YouTubePlaybackMethod.explode,
      YouTubePlaybackMethod.ytDlpServer,
      YouTubePlaybackMethod.youtubeApp,
    ]);
    expect(await playback().play('v', track), YouTubePlayedVia.stream);
    expect(backend.opened, ['https://s/v']);
  });

  test('when streaming fails, the YouTube app is the last resort', () async {
    newPipeFails = true;
    var connecting = 0;
    expect(
      await playback().play('v', track, onConnecting: () => connecting++),
      YouTubePlayedVia.youtubeApp,
    );
    expect(calls, ['newPipe']);
    expect(opened, [Uri.parse('https://www.youtube.com/watch?v=v')]);
    expect(connecting, 1);
  });

  test('nothing switched on that works: the reasons are listed', () async {
    newPipeFails = true;
    await settings.setPlaybackMethod(YouTubePlaybackMethod.youtubeApp, false);
    await expectLater(
      playback().play('v', track),
      throwsA(
        isA<YouTubePlaybackException>().having(
          (e) => e.message,
          'message',
          contains('NewPipe'),
        ),
      ),
    );
  });

  test('a stream the player refuses is resolved once more', () async {
    backend.failures = 1;
    expect(await playback().play('v', track), YouTubePlayedVia.stream);
    expect(calls, ['newPipe', 'newPipe']);
    expect(opened, isEmpty);
  });

  group('caching the queue ahead', () {
    late HttpServer server;
    late List<String> served;

    setUp(() async {
      served = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        served.add(request.uri.path);
        request.response.add(List.filled(100, 7));
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    PlaybackQueue queueOf({
      bool onWifi = true,
      Duration prefetchDelay = Duration.zero,
    }) => PlaybackQueue(
      prefetchDelay: prefetchDelay,
      TrackPlayer(
        player: player,
        settings: settings,
        youTubeLibrary: library,
        youTubeAudio: YouTubeAudio(
          newPipeAvailable: true,
          newPipe: (id) async => [
            YouTubeAudioStream(
              url: 'http://127.0.0.1:${server.port}/$id',
              itag: 251,
            ),
          ],
        ),
        youTubeSearch: YouTubeSearch(),
        openExternal: (uri) async => true,
        onWifi: () async => onWifi,
      ),
    );

    List<SearchHit> videos(int n) => [
      for (var i = 0; i < n; i++)
        SearchHit.youTubeOnly(title: 'T$i', artistLabel: 'A', videoId: 'v$i'),
    ];

    Set<String> cachedNow(int n) => {
      for (var i = 0; i < n; i++)
        if (library.isCached('v$i')) 'v$i',
    };

    /// Exactly [expected] of the first [n] songs get cached: waits for the background downloads
    /// to produce them, then a short quiet spell lets one that shouldn't happen show up.
    Future<void> expectCached(int n, Set<String> expected) async {
      await waitUntil(() => cachedNow(n).containsAll(expected));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(cachedNow(n), expected);
    }

    test('the next 3 songs (the default) after the tapped one', () async {
      final queue = queueOf();
      await queue.start(videos(8), 3);
      await expectCached(8, {'v3', 'v4', 'v5', 'v6'});
      queue.dispose();
    });

    test('in shuffled order', () async {
      final queue = queueOf();
      await settings.setQueuePrefetch(2);
      await queue.start(videos(8), 3, shuffle: true);
      final next = [
        for (final e in queue.upcoming.take(2)) e.hit.youtubeVideoId!,
      ];
      await expectCached(8, {'v3', ...next});
      queue.dispose();
    });

    test('switched off, or off Wi-Fi with "tylko przez Wi-Fi"', () async {
      await settings.setQueuePrefetchEnabled(false);
      final off = queueOf();
      await off.start(videos(4), 0);
      await expectCached(4, {'v0'});
      off.dispose();

      await settings.setQueuePrefetchEnabled(true);
      await settings.setQueuePrefetchWifiOnly(true);
      final mobile = queueOf(onWifi: false);
      await mobile.start(videos(4), 1);
      await expectCached(4, {'v0', 'v1'});
      mobile.dispose();
    });

    test('songs added quickly: only the ones then next are cached', () async {
      final queue = queueOf(prefetchDelay: const Duration(milliseconds: 300));
      await settings.setQueuePrefetch(1);
      await queue.start(videos(2), 0);
      for (final id in ['x1', 'x2', 'x3']) {
        await queue.playNext([
          SearchHit.youTubeOnly(title: id, artistLabel: 'A', videoId: id),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await waitUntil(() => library.isCached('x3'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect([
        for (final id in ['v1', 'x1', 'x2'])
          if (library.isCached(id)) id,
      ], isEmpty);
      queue.dispose();
    });

    test('the cache keeps room for the songs cached ahead', () async {
      await settings.setCacheLimit(1);
      expect(settings.cacheKeep, 5);
      await settings.setQueuePrefetchEnabled(false);
      expect(settings.cacheKeep, 1);
    });
  });

  group('the song in the YouTube app, inside its playlist', () {
    PlaybackQueue queueOf() => PlaybackQueue(
      prefetchDelay: Duration.zero,
      TrackPlayer(
        player: player,
        settings: settings,
        youTubeLibrary: library,
        youTubeAudio: YouTubeAudio(
          newPipeAvailable: true,
          newPipe: (id) async {
            if (newPipeFails) throw Exception('403');
            return [YouTubeAudioStream(url: 'https://s/$id', itag: 251)];
          },
        ),
        youTubeSearch: YouTubeSearch(),
        openExternal: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );

    // The playlist's video of the song differs from the one MusicDatabase links.
    final fromPlaylist = SearchHit.youTubeOnly(
      title: 'T',
      artistLabel: 'A',
      videoId: 'db',
      playlistVideoId: 'pl',
    );

    test(
      '"Otwórz w YouTube": the playlist\'s video with list=, else the video',
      () async {
        final queue = queueOf();
        await queue.start([fromPlaylist], 0, youTubeListId: 'PL1');
        expect(
          queue.currentYouTubeUri,
          Uri.parse('https://www.youtube.com/watch?v=pl&list=PL1'),
        );

        await queue.start([fromPlaylist], 0); // e.g. from search: no playlist
        expect(
          queue.currentYouTubeUri,
          Uri.parse('https://www.youtube.com/watch?v=db'),
        );
        queue.dispose();
      },
    );

    test('the last-resort fallback opens it the same way', () async {
      newPipeFails = true;
      final queue = queueOf();
      await queue.start([fromPlaylist], 0, youTubeListId: 'PL1');
      expect(opened, [
        Uri.parse('https://www.youtube.com/watch?v=pl&list=PL1'),
      ]);
      queue.dispose();
    });
  });

  test('a video found for a track known only by name is remembered', () async {
    await settings.setYouTubeSearchEnabled(true);
    var searches = 0;
    final tracks = TrackPlayer(
      player: player,
      settings: settings,
      youTubeLibrary: library,
      youTubeAudio: YouTubeAudio(
        newPipeAvailable: true,
        newPipe: (id) async => [
          YouTubeAudioStream(url: 'https://s/$id', itag: 251),
        ],
      ),
      youTubeSearch: YouTubeSearch(
        newPipeAvailable: true,
        newPipe: (query) async {
          searches++;
          return const [
            YouTubeVideo(
              id: 'tote1234567',
              title: 'Bonnie Tyler - Total Eclipse of the Heart',
              channel: 'Bonnie Tyler',
            ),
          ];
        },
      ),
      openExternal: (uri) async => true,
    );
    // A Spotify playlist's track that isn't a MusicDatabase song.
    SearchHit spotifyTrack() => SearchHit.youTubeOnly(
      title: 'Total Eclipse of the Heart',
      artistLabel: 'Bonnie Tyler',
      videoId: null,
    );

    expect((await tracks.play(spotifyTrack())).played, isTrue);
    expect(searches, 1);
    expect(
      library.matchForTrack('bonnie tyler', 'Total Eclipse of the Heart'),
      'tote1234567',
    );
    expect((await tracks.play(spotifyTrack())).played, isTrue);
    expect(searches, 1);
    expect(backend.opened.last, 'https://s/tote1234567');
  });

  test('finding nothing on YouTube is remembered: the queue skips, a tap searches again', () async {
    await settings.setYouTubeSearchEnabled(true);
    var searches = 0;
    final tracks = TrackPlayer(
      player: player,
      settings: settings,
      youTubeLibrary: library,
      youTubeAudio: YouTubeAudio(newPipeAvailable: true),
      youTubeSearch: YouTubeSearch(
        newPipeAvailable: true,
        newPipe: (query) async {
          searches++;
          return const [
            YouTubeVideo(id: 'other123456', title: 'Coś innego', channel: 'X'),
          ];
        },
      ),
      openExternal: (uri) async => true,
    );
    final hit = SearchHit.youTubeOnly(
      title: 'Rzadki utwór',
      artistLabel: 'Nieznany zespół',
      videoId: null,
    );

    expect((await tracks.play(hit)).played, isFalse);
    expect(searches, 1);
    expect(library.notFoundTrack('Nieznany zespół', 'Rzadki utwór'), isTrue);

    // When a song ends and this one is next, or caching ahead: no new search.
    expect((await tracks.play(hit, allowExternal: false)).played, isFalse);
    expect(await tracks.prefetch(hit), isFalse);
    expect(searches, 1);

    // Tapped: searched again.
    await tracks.play(hit);
    expect(searches, 2);
  });

  group('a video YouTube removed', () {
    const dead = 'dead1234567';
    late List<Uri> openedApp;
    late int searches;
    late Outbox outbox;

    TrackPlayer tracksWith() {
      openedApp = [];
      searches = 0;
      outbox = Outbox(
        storageRoot: () async => root,
        factoryOverride: databaseFactoryFfi,
      );
      return TrackPlayer(
        player: player,
        settings: settings,
        youTubeLibrary: library,
        outbox: outbox,
        youTubeAudio: YouTubeAudio(
          newPipeAvailable: true,
          newPipe: (id) async {
            if (id == dead) {
              throw PlatformException(code: 'ContentNotAvailableException');
            }
            return [YouTubeAudioStream(url: 'https://s/$id', itag: 251)];
          },
        ),
        youTubeSearch: YouTubeSearch(
          newPipeAvailable: true,
          newPipe: (query) async {
            searches++;
            return const [
              // The removed one may still turn up in results; it's skipped.
              YouTubeVideo(
                id: dead,
                title: 'Bonnie Tyler - Total Eclipse of the Heart',
                channel: 'Bonnie Tyler',
              ),
              YouTubeVideo(
                id: 'alive123456',
                title: 'Bonnie Tyler - Total Eclipse of the Heart',
                channel: 'Bonnie Tyler',
              ),
            ];
          },
        ),
        openExternal: (uri) async {
          openedApp.add(uri);
          return true;
        },
      );
    }

    setUp(() => settings.setYouTubeSearchEnabled(true));

    test(
      'a playlist\'s video: marked, and another one is found and played',
      () async {
        final tracks = tracksWith();
        final fromPlaylist = SearchHit.youTubeOnly(
          title: 'Total Eclipse of the Heart',
          artistLabel: 'Bonnie Tyler',
          videoId: dead,
          playlistVideoId: dead,
        );
        final outcome = await tracks.play(fromPlaylist);
        expect(outcome.played, isTrue);
        expect(searches, 1);
        expect(backend.opened.last, 'https://s/alive123456');
        expect(openedApp, isEmpty); // not handed to the YouTube app
        expect(library.isVideoRemoved(dead), isTrue);
        // Shown from now on with the new video.
        expect(
          withPhoneYouTube(fromPlaylist, library).youtubeVideoId,
          'alive123456',
        );
      },
    );

    test('"Otwórz w YouTube" opens the video found instead, also played from its playlist', () async {
      final queue = PlaybackQueue(tracksWith(), prefetchDelay: Duration.zero);
      final fromPlaylist = SearchHit.youTubeOnly(
        title: 'Total Eclipse of the Heart',
        artistLabel: 'Bonnie Tyler',
        videoId: dead,
        playlistVideoId: dead,
      );
      await queue.start([fromPlaylist], 0, youTubeListId: 'PL1');
      expect(
        queue.currentYouTubeUri,
        Uri.parse('https://www.youtube.com/watch?v=alive123456'),
      );
      queue.dispose();
    });

    test('MusicDatabase\'s own link: marked, replaced on the phone until music.db changes it', () async {
      final tracks = tracksWith();
      CatalogSong song(String videoId) => CatalogSong(
        id: 1,
        title: 'Total Eclipse of the Heart',
        artistLabel: 'Bonnie Tyler',
        youtubeVideoId: videoId,
      );
      final hit = SearchHit.main(song(dead), const []);
      final outcome = await tracks.play(hit);
      expect(outcome.played, isTrue);
      expect(searches, 1);
      expect(backend.opened.last, 'https://s/alive123456');
      expect(openedApp, isEmpty);
      expect(library.isVideoRemoved(dead), isTrue);
      expect(library.matchFor(1), 'alive123456');
      expect(withPhoneYouTube(hit, library).youtubeVideoId, 'alive123456');
      expect(
        tracks.youTubeUri(hit),
        Uri.parse('https://www.youtube.com/watch?v=alive123456'),
      );
      // MusicDatabase is told, with the video found instead.
      final request = (await outbox.pending()).single;
      final db = await databaseFactoryFfi.openDatabase(request.path);
      final reported = await db.query('dead_youtube_links');
      await db.close();
      expect(reported, hasLength(1));
      expect(reported.single, containsPair('song_id', 1));
      expect(reported.single, containsPair('dead_video_id', dead));
      expect(
        reported.single,
        containsPair('replacement_video_id', 'alive123456'),
      );
      // A new link in music.db wins over the phone's replacement.
      expect(
        withPhoneYouTube(
          SearchHit.main(song('fixed123456'), const []),
          library,
        ).youtubeVideoId,
        'fixed123456',
      );
    });

    test('found out while caching ahead: marked, nothing played', () async {
      final tracks = tracksWith();
      final hit = SearchHit.youTubeOnly(
        title: 'T',
        artistLabel: 'A',
        videoId: dead,
      );
      expect(await tracks.prefetch(hit), isFalse);
      expect(library.isVideoRemoved(dead), isTrue);
      // Not a music.db link: nothing for MusicDatabase.
      expect(await outbox.pending(), isEmpty);
    });
  });
}
