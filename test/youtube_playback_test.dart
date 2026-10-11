import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
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

    PlaybackQueue queueOf({bool onWifi = true}) => PlaybackQueue(
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

    /// Waits for background downloads to settle.
    Future<Set<String>> cached(int n) async {
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return {
        for (var i = 0; i < n; i++)
          if (library.isCached('v$i')) 'v$i',
      };
    }

    test('the next 3 songs (the default) after the tapped one', () async {
      final queue = queueOf();
      await queue.start(videos(8), 3);
      expect(await cached(8), {'v3', 'v4', 'v5', 'v6'});
      queue.dispose();
    });

    test('in shuffled order', () async {
      final queue = queueOf();
      await settings.setQueuePrefetch(2);
      await queue.start(videos(8), 3, shuffle: true);
      final next = [
        for (final e in queue.upcoming.take(2)) e.hit.youtubeVideoId,
      ];
      expect(await cached(8), {'v3', ...next});
      queue.dispose();
    });

    test('switched off, or off Wi-Fi with "tylko przez Wi-Fi"', () async {
      await settings.setQueuePrefetchEnabled(false);
      final off = queueOf();
      await off.start(videos(4), 0);
      expect(await cached(4), {'v0'});
      off.dispose();

      await settings.setQueuePrefetchEnabled(true);
      await settings.setQueuePrefetchWifiOnly(true);
      final mobile = queueOf(onWifi: false);
      await mobile.start(videos(4), 1);
      expect(await cached(4), {'v0', 'v1'});
      mobile.dispose();
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
}
