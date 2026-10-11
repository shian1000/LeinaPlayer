import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:music_database_app/src/screens/queue_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Backend implements AudioBackend {
  final opened = <String>[];
  final seeks = <Duration>[];
  var pauses = 0;
  final _position = StreamController<Duration>.broadcast();
  final _state = StreamController<({bool playing, bool completed})>.broadcast();
  final skipPresses = StreamController<MediaSkip>.broadcast();

  void at(Duration position) => _position.add(position);
  void finish() => _state.add((playing: true, completed: true));

  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration?> get duration => const Stream.empty();
  @override
  Stream<({bool playing, bool completed})> get state => _state.stream;
  @override
  Stream<MediaSkip> get skips => skipPresses.stream;
  @override
  Future<void> open(NowPlaying track) async => opened.add(track.source);
  @override
  Future<void> play() async => _state.add((playing: true, completed: false));
  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> seek(Duration position) async => seeks.add(position);
  @override
  Future<void> dispose() async {}
}

SearchHit _file(String name) => SearchHit.phoneOnly(
  LocalSong(id: 1, filePath: '/music/$name.mp3', title: name, pending: true),
);

/// A MusicDatabase song marked as not on YouTube, and not on the phone: unplayable.
SearchHit _unplayable(String title) => SearchHit.main(
  CatalogSong(id: 99, title: title, artistLabel: 'X', youtubeVideoId: 'N/A'),
  const [],
);

void main() {
  late _Backend backend;
  late PlayerController player;
  late PlaybackQueue queue;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = SourceSettings();
    await settings.load();
    backend = _Backend();
    player = PlayerController(backend: () => backend);
    queue = PlaybackQueue(
      TrackPlayer(
        player: player,
        settings: settings,
        youTubeLibrary: YouTubeLibrary(
          () => Future.error(StateError('not used')),
        ),
        youTubeAudio: YouTubeAudio(newPipeAvailable: false),
        youTubeSearch: YouTubeSearch(),
      ),
    );
  });

  tearDown(() {
    queue.dispose();
    player.dispose();
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test(
    'starts at the tapped song; when a song ends the next one plays',
    () async {
      await queue.start([_file('a'), _file('b'), _file('c')], 1);
      expect(backend.opened, ['/music/b.mp3']);
      expect(queue.current?.title, 'b');
      expect((queue.hasPrevious, queue.hasNext), (true, true));

      backend.finish();
      await flush();
      expect(backend.opened.last, '/music/c.mp3');
      expect(queue.hasNext, isFalse);

      // The last song ending leaves the queue where it is.
      backend.finish();
      await flush();
      expect(backend.opened, hasLength(2));
    },
  );

  test('songs that can\'t be played are skipped when moving on', () async {
    await queue.start([_file('a'), _unplayable('b'), _file('c')], 0);
    backend.finish();
    await flush();
    await flush();
    expect(backend.opened, ['/music/a.mp3', '/music/c.mp3']);
    expect(queue.current?.title, 'c');
  });

  test(
    '"Poprzedni": the previous song within 5 s, else back to the start',
    () async {
      await queue.start([_file('a'), _file('b')], 1);

      backend.at(const Duration(seconds: 12));
      await flush();
      expect(await queue.previous(), isNull);
      expect(backend.seeks.last, Duration.zero);
      expect(backend.opened, ['/music/b.mp3']);

      backend.at(const Duration(seconds: 3));
      await flush();
      expect((await queue.previous())?.played, isTrue);
      expect(backend.opened.last, '/music/a.mp3');

      // The first song has nothing before it: always restart.
      expect(await queue.previous(), isNull);
      expect(backend.opened, hasLength(2));
    },
  );

  test('"Następny" plays the next song, and does nothing at the end', () async {
    await queue.start([_file('a'), _file('b')], 0);
    expect((await queue.next())?.played, isTrue);
    expect(backend.opened.last, '/music/b.mp3');
    expect(await queue.next(), isNull);
  });

  test('a new queue replaces the old one', () async {
    await queue.start([_file('a'), _file('b')], 0);
    await queue.start([_file('x')], 0);
    expect(queue.current?.title, 'x');
    expect(queue.upcoming, isEmpty);
    backend.finish();
    await flush();
    expect(backend.opened, ['/music/a.mp3', '/music/x.mp3']);
  });

  List<String> titles(List<QueueEntry> entries) => [
    for (final e in entries) e.hit.title,
  ];

  test(
    '"Dodaj do kolejki" plays next, before the rest of the playlist',
    () async {
      await queue.start([_file('a'), _file('b'), _file('c')], 0);
      await queue.add(_file('x'));
      await queue.add(_file('y'));
      expect(titles(queue.added), ['x', 'y']);
      expect(titles(queue.upcoming), ['x', 'y', 'b', 'c']);

      await queue.next();
      expect(queue.current?.title, 'x');
      // Back from an added song: the playlist song that played before it.
      expect((await queue.previous())?.played, isTrue);
      expect(queue.current?.title, 'a');
      expect(titles(queue.upcoming), ['y', 'b', 'c']);

      backend.finish();
      await flush();
      expect(queue.current?.title, 'y');
      backend.finish();
      await flush();
      expect(queue.current?.title, 'b');
    },
  );

  test('"Dodaj do kolejki" with nothing playing starts the song', () async {
    expect((await queue.add(_file('x')))?.played, isTrue);
    expect(backend.opened, ['/music/x.mp3']);
    expect(queue.upcoming, isEmpty);
  });

  test('jumping to and removing queued songs', () async {
    await queue.start([_file('a'), _file('b'), _file('c'), _file('d')], 0);
    await queue.add(_file('x'));
    queue.remove(queue.upcoming[2]); // c
    expect(titles(queue.upcoming), ['x', 'b', 'd']);

    await queue.jumpTo(
      queue.upcoming[2],
    ); // d: x is dropped, b counts as played
    expect(queue.current?.title, 'd');
    // Jumping within the playlist keeps the songs added with "Dodaj do kolejki".
    expect(titles(queue.upcoming), ['x']);
    expect(queue.hasPrevious, isTrue);

    queue.clearAdded();
    expect(queue.added, isEmpty);
  });

  test(
    'shuffle mixes the rest, and off goes back to the playlist order',
    () async {
      final songs = [for (var i = 0; i < 20; i++) _file('$i')];
      await queue.start(songs, 4);
      queue.setShuffle(true);
      final shuffled = titles(queue.upcoming);
      expect(shuffled.toSet(), {
        for (var i = 0; i < 20; i++)
          if (i != 4) '$i',
      });
      expect(shuffled, isNot([for (var i = 5; i < 20; i++) '$i']));

      await queue.next();
      expect(queue.current?.title, shuffled.first);
      queue.setShuffle(false);
      final at = int.parse(shuffled.first);
      expect(titles(queue.upcoming), [for (var i = at + 1; i < 20; i++) '$i']);
      expect(queue.hasPrevious, at > 0);
    },
  );

  test(
    '"Odtwarzanie losowe" starts somewhere and plays everything once',
    () async {
      final songs = [for (var i = 0; i < 6; i++) _file('$i')];
      await queue.startShuffled(songs);
      expect(queue.shuffle, isTrue);
      expect(
        {queue.current!.title, ...titles(queue.upcoming)},
        {for (var i = 0; i < 6; i++) '$i'},
      );
      expect(queue.upcoming, hasLength(5));
    },
  );

  test(
    'previous/next pressed in the media notification move the queue',
    () async {
      await queue.start([_file('a'), _file('b')], 0);
      backend.skipPresses.add(MediaSkip.next);
      await flush();
      expect(backend.opened.last, '/music/b.mp3');
      backend.skipPresses.add(MediaSkip.previous);
      await flush();
      expect(backend.opened.last, '/music/a.mp3');
    },
  );

  testWidgets(
    '"Kolejka": what plays now and next; tap to jump, remove, shuffle',
    (tester) async {
      await tester.runAsync(() async {
        await queue.start(
          [_file('a'), _file('b'), _file('c')],
          0,
          playlistName: 'Do auta',
        );
        await queue.add(_file('x'));
      });
      await tester.pumpWidget(
        PlayerScope(
          notifier: player,
          child: PlaybackQueueScope(
            notifier: queue,
            child: MaterialApp(
              theme: buildAppTheme(dummifyTheme),
              home: const QueueScreen(),
            ),
          ),
        ),
      );
      expect(find.text('Teraz odtwarzane'), findsOneWidget);
      expect(find.text('Następne w kolejce'), findsOneWidget);
      expect(find.text('Następne z: Do auta'), findsOneWidget);
      expect(find.text('x'), findsOneWidget);

      await tester.tap(find.byTooltip('Usuń z kolejki').first);
      await tester.pump();
      expect(find.text('x'), findsNothing);
      expect(find.text('Następne w kolejce'), findsNothing);

      await tester.tap(find.text('c'));
      await tester.pump();
      expect(backend.opened.last, '/music/c.mp3');
      expect(find.byTooltip('Usuń z kolejki'), findsNothing);

      await tester.tap(find.text('Losowo: wył.'));
      await tester.pump();
      expect(queue.shuffle, isTrue);
      expect(find.text('Losowo: wł.'), findsOneWidget);
    },
  );

  test('no pause between songs (the media session keeps the app awake), '
      'only at the end of the queue', () async {
    await queue.start([_file('a'), _file('b')], 0);
    backend.finish();
    await flush();
    expect(backend.opened.last, '/music/b.mp3');
    expect(backend.pauses, 0);

    backend.finish();
    await flush();
    expect(backend.pauses, 1);
    expect(backend.seeks.last, Duration.zero);
  });

  group('no connection while moving on by itself', () {
    late List<String> asked;
    late int failures;
    late PlaybackQueue offlineQueue;

    setUp(() async {
      asked = [];
      failures = 0;
      final settings = SourceSettings();
      await settings.load();
      await settings.setPlaybackMethod(YouTubePlaybackMethod.cache, false);
      offlineQueue = PlaybackQueue(
        TrackPlayer(
          player: player,
          settings: settings,
          youTubeLibrary: YouTubeLibrary(
            () => Future.error(StateError('not used')),
          ),
          youTubeAudio: YouTubeAudio(
            newPipeAvailable: true,
            newPipe: (id) async {
              asked.add(id);
              if (failures-- > 0) {
                throw PlatformException(code: 'UnknownHostException');
              }
              return [YouTubeAudioStream(url: 'https://s/$id', itag: 251)];
            },
          ),
          youTubeSearch: YouTubeSearch(),
        ),
        offlineRetries: const [Duration.zero, Duration.zero],
      );
    });

    tearDown(() => offlineQueue.dispose());

    SearchHit video(String id) =>
        SearchHit.youTubeOnly(title: id, artistLabel: 'A', videoId: id);

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await flush();
      }
    }

    test('the same song is tried again rather than skipped', () async {
      await offlineQueue.start([_file('a'), video('v1'), video('v2')], 0);
      failures = 2;
      backend.finish();
      await settle();
      expect(asked, ['v1', 'v1', 'v1']);
      expect(backend.opened.last, 'https://s/v1');
    });

    test(
      'still no connection: stops on that song; "Odtwórz" tries it again',
      () async {
        await offlineQueue.start([_file('a'), video('v1'), video('v2')], 0);
        failures = 3;
        backend.finish();
        await settle();
        expect(asked, ['v1', 'v1', 'v1']);
        expect(offlineQueue.current?.title, 'v1');
        expect((player.restored, player.current?.title), (true, 'v1'));

        await player.togglePlay();
        await settle();
        expect(backend.opened.last, 'https://s/v1');
      },
    );
  });
}
