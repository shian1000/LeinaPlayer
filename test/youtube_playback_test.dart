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
import 'package:music_database_app/src/l10n.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:music_database_app/src/playback/youtube_playback.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/waiting.dart';

class _Backend implements AudioBackend {
  final opened = <String>[];
  final parked = <String>[];
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
  void showParked(NowPlaying track) => parked.add(track.title);

  @override
  Future<void> crossfadeTo(NowPlaying track, Duration fade) async {}
  @override
  Future<void> play() async => _state.add((playing: true, completed: false));
  @override
  Future<void> pause() async => _state.add((playing: false, completed: false));
  @override
  Future<void> fadeOutAndPause(Duration fade) => pause();
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
    catalog = SongCatalog(sync);
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

  NowPlaying track(String videoId, String source, {String? streamQuality}) =>
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

  test(
    'an age-restricted video opens in the YouTube app, saying why',
    () async {
      final playback = YouTubePlayback(
        audio: YouTubeAudio(
          newPipeAvailable: true,
          newPipe: (id) async =>
              throw PlatformException(code: 'AgeRestrictedContentException'),
        ),
        library: library,
        settings: settings,
        player: player,
        openExternal: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      expect(
        await playback.play('v', track),
        YouTubePlayedVia.youtubeAppAgeRestricted,
      );
      expect(opened, [Uri.parse('https://www.youtube.com/watch?v=v')]);
    },
  );

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
        // As playlists: each goes to the front, single songs would line up after x1.
        await queue.playNext([
          SearchHit.youTubeOnly(title: id, artistLabel: 'A', videoId: id),
        ], origin: QueueOrigin(playlistName: id));
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

    test('"Otwórz w YouTube" starts where the player is', () {
      final uri = Uri.parse('https://www.youtube.com/watch?v=pl&list=PL1');
      expect(
        youTubeUriAt(
          uri,
          const Duration(minutes: 1, seconds: 30, milliseconds: 700),
        ),
        Uri.parse('https://www.youtube.com/watch?v=pl&list=PL1&t=90s'),
      );
      expect(youTubeUriAt(uri, const Duration(milliseconds: 400)), uri);
    });

    test(
      'a song opened in the YouTube app is the one the players show',
      () async {
        final queue = queueOf();
        await queue.start([
          SearchHit.youTubeOnly(
            title: 'Lipe cvatu',
            artistLabel: 'A',
            videoId: 'a',
          ),
          SearchHit.youTubeOnly(
            title: 'Đurđevdan',
            artistLabel: 'B',
            videoId: 'b',
          ),
        ], 0);
        expect(player.current?.title, 'Lipe cvatu');
        newPipeFails = true;
        final outcome = await queue.next();
        expect(outcome?.external, isTrue);
        expect(opened, [Uri.parse('https://www.youtube.com/watch?v=b')]);
        expect(player.current?.title, 'Đurđevdan');
        expect(player.playing, isFalse);
        // The media notification too.
        expect(backend.parked, ['Đurđevdan']);
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

  group('an age-restricted video', () {
    const restricted = 'adult123456';
    late List<Uri> openedApp;
    late List<String> statuses;
    late List<String> streamed;
    late int searches;
    late Outbox outbox;
    var results = const <YouTubeVideo>[];

    TrackPlayer tracksWith() {
      openedApp = [];
      statuses = [];
      streamed = [];
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
            streamed.add(id);
            if (id == restricted) {
              throw PlatformException(code: 'AgeRestrictedContentException');
            }
            return [YouTubeAudioStream(url: 'http://s/$id', itag: 251)];
          },
        ),
        youTubeSearch: YouTubeSearch(
          newPipeAvailable: true,
          newPipe: (query) async {
            searches++;
            return results;
          },
        ),
        openExternal: (uri) async {
          openedApp.add(uri);
          return true;
        },
      );
    }

    final song = CatalogSong(
      id: 7,
      title: 'Tuono',
      artistLabel: 'Russell Nash',
      youtubeVideoId: restricted,
    );

    setUp(() async {
      await settings.setYouTubeSearchEnabled(true);
      results = const [
        // The age-restricted music video itself turns up too; it's skipped.
        YouTubeVideo(
          id: restricted,
          title: 'Russell Nash - Tuono (Official Video)',
          channel: 'Russell Nash',
        ),
        YouTubeVideo(
          id: 'topic123456',
          title: 'Tuono',
          channel: 'Russell Nash - Topic',
        ),
      ];
    });

    test('another upload of the song plays instead, saying so', () async {
      final tracks = tracksWith();
      final hit = SearchHit.main(song, const []);
      final outcome = await tracks.play(hit, onStatus: statuses.add);
      expect(outcome.played, isTrue);
      expect(outcome.external, isFalse);
      expect(outcome.message, contains('Tuono'));
      expect(backend.opened.last, 'http://s/topic123456');
      expect(openedApp, isEmpty);
      expect(statuses, contains(l10n.trackPlayerAgeRestrictedSearching));
      expect(library.isAgeRestricted(restricted), isTrue);
      expect(library.standInFor(restricted), 'topic123456');
      // music.db's link stays, and MusicDatabase isn't told: the video is the right one.
      expect(withPhoneYouTube(hit, library).youtubeVideoId, restricted);
      expect(await outbox.pending(), isEmpty);

      // Next time straight to the stand-in: no search, the original not tried.
      streamed.clear();
      final again = await tracks.play(hit, onStatus: statuses.add);
      expect(again.played, isTrue);
      expect(searches, 1);
      expect(streamed, ['topic123456']);
    });

    test('no other upload: the YouTube app opens it, saying why', () async {
      results = [results.first];
      final tracks = tracksWith();
      final hit = SearchHit.main(song, const []);
      final outcome = await tracks.play(hit, onStatus: statuses.add);
      expect(outcome.external, isTrue);
      expect(outcome.message, l10n.trackPlayerOpenedInYouTubeAppAgeRestricted);
      expect(openedApp, [
        Uri.parse('https://www.youtube.com/watch?v=$restricted'),
      ]);
      expect(
        statuses,
        containsAllInOrder([
          l10n.trackPlayerAgeRestrictedSearching,
          l10n.youtubePlaybackOpeningAppAgeRestricted,
        ]),
      );

      // Not searched again for a while, nor streamed: the YouTube app at once.
      streamed.clear();
      await tracks.play(hit);
      expect(searches, 1);
      expect(streamed, isEmpty);
      expect(openedApp, hasLength(2));
    });

    test(
      'the channel of the age-restricted video counts as the artist',
      () async {
        // Goran Bregović's "Đurđevdan" was uploaded by "Bijelo Dugme" (music.db song #7042).
        results = const [
          YouTubeVideo(
            id: restricted,
            title: 'Goran Bregovic - Djurdjevdan',
            channel: 'Bijelo Dugme',
          ),
          YouTubeVideo(
            id: 'tv123456789',
            title: 'Ceca & Goran Bregović - Đurđevdan / Novogodišnji program RTS 2022',
            channel: 'RTS Najlepše narodne pesme',
            viewCount: 3741756,
          ),
          YouTubeVideo(
            id: 'audio123456',
            title: 'Bijelo Dugme - Đurđevdan - (Audio 1994) HD',
            channel: 'PGP RTS',
            viewCount: 5428300,
          ),
        ];
        final tracks = tracksWith();
        final hit = SearchHit.main(
          CatalogSong(
            id: 7042,
            title: 'Đurđevdan',
            artistLabel: 'Goran Bregović',
            youtubeVideoId: restricted,
          ),
          const [],
        );
        expect((await tracks.play(hit)).played, isTrue);
        expect(library.standInFor(restricted), 'audio123456');
      },
    );

    test('switched off: the YouTube app at once, no search', () async {
      await settings.setAgeRestrictedStandIn(false);
      final tracks = tracksWith();
      final outcome = await tracks.play(
        SearchHit.main(song, const []),
        onStatus: statuses.add,
      );
      expect(outcome.external, isTrue);
      expect(searches, 0);
      expect(statuses, contains(l10n.youtubePlaybackOpeningAppAgeRestricted));
    });

    test('found out while caching ahead: the stand-in is cached', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.add(List.filled(100, 7));
        await request.response.close();
      });
      final cached = TrackPlayer(
        player: player,
        settings: settings,
        youTubeLibrary: library,
        youTubeAudio: YouTubeAudio(
          newPipeAvailable: true,
          newPipe: (id) async {
            if (id == restricted) {
              throw PlatformException(code: 'AgeRestrictedContentException');
            }
            return [
              YouTubeAudioStream(
                url: 'http://127.0.0.1:${server.port}/$id',
                itag: 251,
              ),
            ];
          },
        ),
        youTubeSearch: YouTubeSearch(
          newPipeAvailable: true,
          newPipe: (query) async => results,
        ),
        openExternal: (uri) async => true,
      );
      expect(await cached.prefetch(SearchHit.main(song, const [])), isTrue);
      expect(library.isAgeRestricted(restricted), isTrue);
      expect(library.isCached('topic123456'), isTrue);
    });
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

    test(
      'a song music.db has no link for: the video found is reported, once',
      () async {
        final tracks = tracksWith();
        final song = CatalogSong(
          id: 2,
          title: 'Total Eclipse of the Heart',
          artistLabel: 'Bonnie Tyler',
        );
        // The removed one would be picked first otherwise.
        await library.markVideoRemoved(dead);
        expect(
          (await tracks.play(SearchHit.main(song, const []))).played,
          isTrue,
        );
        expect(library.matchFor(2), 'alive123456');
        await outbox.reportFoundYouTubeLink(
          song,
          const YouTubeVideo(id: 'alive123456', title: '', channel: ''),
        );
        final found = await outbox.waitingFoundLinks();
        expect(found, hasLength(1));
        expect(found.single.songId, 2);
        expect(found.single.videoId, 'alive123456');
        expect(found.single.videoChannel, 'Bonnie Tyler');
        // Not a dead link.
        expect(await outbox.waitingReports(), isEmpty);
      },
    );

    test(
      'a video MusicDatabase turned down for the song isn\'t picked for it',
      () async {
        final tracks = tracksWith();
        CatalogSong song(int id) => CatalogSong(
          id: id,
          title: 'Total Eclipse of the Heart',
          artistLabel: 'Bonnie Tyler',
        );
        await library.useBadVideos(
          const BadVideos(
            everySong: {dead},
            forSong: {
              3: {'alive123456'},
            },
          ),
        );
        final outcome = await tracks.play(SearchHit.main(song(3), const []));
        expect(outcome.played, isFalse);
        expect(library.matchFor(3), isNull);
        expect(await outbox.pending(), isEmpty);
        // Another song may still use it.
        expect(
          (await tracks.play(SearchHit.main(song(4), const []))).played,
          isTrue,
        );
        expect(library.matchFor(4), 'alive123456');
      },
    );

    group('a song a Biblioteka playlist has its own video for', () {
      // MusicDatabase song #5965, reviewed on 2026-11-25: played from outside the playlist
      // "ダウンロード (2020.08)", the phone searched and reported a remix while that playlist
      // had the original as a track.
      final song = CatalogSong(
        id: 5965,
        title: 'Nemreš Bolivit',
        artistLabel: 'Renman',
        album: 'Space Cat, The Remixes',
      );
      const original = YouTubeVideo(
        id: '-XS-1zFEytA',
        title: 'Renman - Nemreš Bolivit',
        channel: '',
        duration: Duration(seconds: 302),
      );

      TrackPlayer tracksFor(List<YouTubeVideo> playlistVideos) {
        tracksWith();
        return TrackPlayer(
          player: player,
          settings: settings,
          youTubeLibrary: library,
          outbox: outbox,
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
                  id: 'szXthhpfkzw',
                  title: 'Nemreš Bolivit (Space Cat Remix)',
                  channel: 'Renman - Topic',
                  duration: Duration(seconds: 289),
                ),
                YouTubeVideo(
                  id: 'search12345',
                  title: 'Renman - Nemreš Bolivit',
                  channel: 'Renman',
                  duration: Duration(seconds: 300),
                ),
              ];
            },
          ),
          openExternal: (uri) async => true,
          playlistVideosOf: (id) => id == song.id ? playlistVideos : const [],
        );
      }

      test('its video is played and reported, without a search', () async {
        final tracks = tracksFor([
          // The user's other playlist with the remix: not this song.
          const YouTubeVideo(
            id: 'remix123456',
            title: 'Renman - Nemreš Bolivit (Space Cat Remix)',
            channel: '',
            duration: Duration(seconds: 289),
          ),
          original,
        ]);
        expect(
          (await tracks.play(SearchHit.main(song, const []))).played,
          isTrue,
        );
        expect(searches, 0);
        expect(backend.opened.last, 'https://s/-XS-1zFEytA');
        expect(library.matchFor(5965), '-XS-1zFEytA');
        final found = await outbox.waitingFoundLinks();
        expect(found.single.songId, 5965);
        expect(found.single.videoId, '-XS-1zFEytA');
        expect(found.single.videoTitle, 'Renman - Nemreš Bolivit');
        expect(found.single.videoChannel, isNull);
      });

      test(
        'one removed or not plausible for the song: searched instead',
        () async {
          final tracks = tracksFor([
            original,
            const YouTubeVideo(
              id: 'wrong123456',
              title: 'Renman - Inna piosenka',
              channel: '',
            ),
          ]);
          await library.markVideoRemoved(original.id);
          expect(
            (await tracks.play(SearchHit.main(song, const []))).played,
            isTrue,
          );
          expect(searches, 1);
          // Not the Topic remix the search also gave.
          expect(library.matchFor(5965), 'search12345');
          expect(
            (await outbox.waitingFoundLinks()).single.videoId,
            'search12345',
          );
        },
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
