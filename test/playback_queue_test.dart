import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/mood_filter.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/track_ref.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:music_database_app/src/screens/now_playing.dart';
import 'package:music_database_app/src/screens/queue_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/widgets/queue_toast.dart';
import 'package:music_database_app/src/widgets/song_tile.dart';
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
  late YouTubeLibrary youTubeLibrary;
  late TrackPlayer tracks;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = SourceSettings();
    await settings.load();
    backend = _Backend();
    player = PlayerController(backend: () => backend);
    youTubeLibrary = YouTubeLibrary(() => Future.error(StateError('not used')));
    queue = PlaybackQueue(
      prefetchDelay: Duration.zero,
      tracks = TrackPlayer(
        player: player,
        settings: settings,
        youTubeLibrary: youTubeLibrary,
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

  List<String> titles(List<QueueEntry> entries) => [
    for (final e in entries) e.hit.title,
  ];

  test('"Dodaj do kolejki" plays after the songs added before, ahead of the playlist', () async {
    await queue.start([_file('a'), _file('b'), _file('c')], 0);
    await queue.add([_file('x')]);
    await queue.add([_file('y')]);
    expect(titles(queue.upcoming), ['x', 'y', 'b', 'c']);

    await queue.next();
    expect(queue.current?.title, 'x');
    // "Poprzedni" goes back in the queue, and the song left comes next again.
    expect((await queue.previous())?.played, isTrue);
    expect(queue.current?.title, 'a');
    expect(titles(queue.upcoming), ['x', 'y', 'b', 'c']);

    await queue.next();
    backend.finish();
    await flush();
    expect(queue.current?.title, 'y');
    backend.finish();
    await flush();
    expect(queue.current?.title, 'b');
  });

  test('"Odtwórz jako następny" plays right after the current song', () async {
    await queue.start([_file('a'), _file('b')], 0);
    await queue.add([_file('x')]);
    await queue.playNext([_file('n')]);
    expect(titles(queue.upcoming), ['n', 'x', 'b']);
  });

  test('adding with nothing playing starts the song', () async {
    expect((await queue.add([_file('x')]))?.played, isTrue);
    expect(backend.opened, ['/music/x.mp3']);
    expect(queue.upcoming, isEmpty);
    expect((await queue.playNext([_file('y')])), isNull);
    expect(titles(queue.upcoming), ['y']);
  });

  test(
    'a playlist added as a whole remembers it; a single song does not',
    () async {
      final plays = <QueuePlay>[];
      queue.played.listen(plays.add);
      await queue.start(
        [_file('a1'), _file('a2'), _file('a3')],
        0,
        playlistId: 1,
        playlistName: 'A',
        youTubeListId: 'PLa',
      );
      final b = QueueOrigin(
        playlistId: 2,
        playlistName: 'B',
        youTubeListId: 'PLb',
      );
      await queue.playNext([_file('b1'), _file('b2')], origin: b);
      await queue.playNext([_file('b3')]);
      expect(titles(queue.upcoming), ['b3', 'b1', 'b2', 'a2', 'a3']);

      await queue.next();
      expect(queue.currentEntry?.origin, isNull);
      await queue.next();
      expect(queue.currentEntry?.origin?.playlistName, 'B');
      expect(queue.currentEntry?.index, 0);
      expect(queue.isMain(queue.currentEntry!), isFalse);
      await queue.next();
      await queue.next();
      expect(queue.currentEntry?.origin?.playlistName, 'A');
      expect(queue.isMain(queue.currentEntry!), isTrue);
      await flush();
      expect(
        [for (final p in plays) (p.hit.title, p.playlistName)],
        [('a1', 'A'), ('b3', null), ('b1', 'B'), ('b2', 'B'), ('a2', 'A')],
      );

      // "Poprzedni" walks back through the queue, whatever each song came from.
      await queue.previous();
      expect(queue.current?.title, 'b2');
      await queue.previous();
      expect(queue.current?.title, 'b1');
    },
  );

  test('a new queue replaces everything, the added songs too', () async {
    await queue.start([_file('a'), _file('b')], 0);
    await queue.add([_file('x')]);
    await queue.start([_file('c'), _file('d')], 1);
    expect(titles(queue.upcoming), isEmpty);
    expect(queue.current?.title, 'd');
    expect(queue.hasPrevious, isTrue, reason: 'c is before d');
  });

  test('jumping to, removing, putting back and clearing', () async {
    await queue.start([_file('a'), _file('b'), _file('c'), _file('d')], 0);
    await queue.add([_file('x')]);
    final c = queue.upcoming[2];
    final at = queue.remove(c);
    expect(titles(queue.upcoming), ['x', 'b', 'd']);
    queue.reinsert(c, at);
    expect(titles(queue.upcoming), ['x', 'b', 'c', 'd']);
    queue.remove(c);

    await queue.jumpTo(
      queue.upcoming[2],
    ); // d: x is dropped, b counts as played
    expect(queue.current?.title, 'd');
    expect(queue.upcoming, isEmpty);
    expect(queue.hasPrevious, isTrue);
    await queue.previous();
    expect(queue.current?.title, 'b');

    await queue.add([_file('y')]);
    queue.clearAdded();
    expect(titles(queue.upcoming), ['d']);
  });

  test('going back to a song played before', () async {
    await queue.start([_file('a'), _file('b'), _file('c'), _file('d')], 2);
    await queue.add([_file('x')]);
    await queue.next();
    expect(titles(queue.history), ['a', 'b', 'c']);

    await queue.jumpBack(queue.history[1]);
    expect(backend.opened.last, '/music/b.mp3');
    expect(titles(queue.history), ['a']);
    expect(titles(queue.upcoming), ['c', 'x', 'd']);
  });

  test('moving songs; a moved song keeps where it came from', () async {
    await queue.start(
      [_file('a'), _file('b'), _file('c'), _file('d')],
      0,
      playlistName: 'A',
    );
    await queue.add([_file('x')]);
    queue.move(queue.upcoming[0], 2); // x between b and c
    expect(titles(queue.upcoming), ['b', 'c', 'x', 'd']);
    queue.move(queue.upcoming[3], 0); // d first
    expect(titles(queue.upcoming), ['d', 'b', 'c', 'x']);
    expect(queue.upcoming.first.origin?.playlistName, 'A');
    expect(queue.upcoming[3].origin, isNull);
    // "Dodaj do kolejki" goes before the first song of the playlist still in place.
    await queue.add([_file('y')]);
    expect(titles(queue.upcoming), ['d', 'y', 'b', 'c', 'x']);
  });

  test('shuffle mixes only the playlist songs, in their places', () async {
    final songs = [for (var i = 0; i < 20; i++) _file('$i')];
    await queue.start(songs, 0);
    await queue.add([_file('x')]);
    queue.move(queue.upcoming[6], 1); // "6" pinned second
    queue.setShuffle(true);
    expect(titles(queue.upcoming).take(2), ['x', '6']);
    queue.setShuffle(false);
    expect(titles(queue.upcoming), [
      'x',
      '6',
      for (var i = 1; i < 20; i++)
        if (i != 6) '$i',
    ]);
  });

  test('a queue saved before songs knew where they came from is read', () {
    SearchHit resolve(TrackRef ref) => _file(ref.title);
    Map<String, Object?> ref(String t) => TrackRef(title: t).toJson();
    queue.restore({
      'context': [ref('a'), ref('b'), ref('c'), ref('d')],
      'order': [0, 2, 1, 3],
      'pos': 1,
      'removed': <int>[],
      'added': [ref('x')],
      'current': ref('c'),
      'current_added': false,
      'shuffle': true,
      'playlist_id': 5,
      'youtube_list_id': null,
      'playlist_name': 'A',
      'search_query': null,
    }, resolve);
    expect(queue.current?.title, 'c');
    expect(queue.currentEntry?.origin?.playlistId, 5);
    expect(queue.currentEntry?.index, 2);
    expect(titles(queue.upcoming), ['x', 'b', 'd']);
    expect(queue.upcoming.first.origin, isNull);
    expect(queue.hasPrevious, isTrue);
    expect(queue.shuffle, isTrue);
  });

  test('saved and read back: origins, order and pinned songs', () async {
    await queue.start(
      [_file('a'), _file('b'), _file('c')],
      1,
      playlistName: 'A',
    );
    await queue.add([
      _file('p'),
      _file('q'),
    ], origin: QueueOrigin(playlistName: 'B'));
    queue.move(queue.upcoming.last, 0);
    final saved = jsonDecode(jsonEncode(queue.snapshot())) as Map;
    final other = PlaybackQueue(tracks, prefetchDelay: Duration.zero);
    addTearDown(other.dispose);
    other.restore(saved.cast(), (ref) => _file(ref.title));
    expect(titles(other.upcoming), ['c', 'p', 'q']);
    expect(other.upcoming.first.pinned, isTrue);
    expect(
      identical(other.upcoming[1].origin, other.upcoming[2].origin),
      isTrue,
    );
    expect(other.upcoming[1].origin?.playlistName, 'B');
    expect(other.isMain(other.upcoming.first), isTrue);
    expect(other.current?.title, 'b');
    expect(other.hasPrevious, isTrue);
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

  // The song playing animates for ever, so no pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> showQueue(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PlayerScope(
        notifier: player,
        child: PlaybackQueueScope(
          notifier: queue,
          child: YouTubeLibraryScope(
            notifier: youTubeLibrary,
            child: MaterialApp(
              theme: buildAppTheme(dummifyTheme),
              home: const QueueScreen(),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    '"Kolejka": a heading per place songs came from; tap to jump, shuffle',
    (tester) async {
      await tester.runAsync(() async {
        await queue.start(
          [_file('a'), _file('b'), _file('c')],
          0,
          playlistName: 'Do auta',
        );
        await queue.add([_file('x')]);
        await queue.add([
          _file('p'),
        ], origin: QueueOrigin(playlistName: 'Inna'));
      });
      await showQueue(tester);
      expect(find.text('Teraz odtwarzane'), findsOneWidget);
      expect(find.text('Następne w kolejce'), findsOneWidget);
      expect(find.text('Z playlisty: Inna'), findsOneWidget);
      expect(find.text('Następne z: Do auta'), findsOneWidget);
      expect(find.text('Wyczyść kolejkę'), findsOneWidget);

      await tester.tap(find.text('c'));
      await tester.pump();
      expect(backend.opened.last, '/music/c.mp3');
      expect(find.text('Następne w kolejce'), findsNothing);

      await tester.tap(find.text('Losowo: wył.'));
      await tester.pump();
      expect(queue.shuffle, isTrue);
      expect(find.text('Losowo: wł.'), findsOneWidget);
    },
  );

  testWidgets(
    '"Kolejka": dragging left takes a song out ("Cofnij" puts it back), '
    'right makes it play next',
    (tester) async {
      await tester.runAsync(() async {
        await queue.start([_file('a'), _file('b'), _file('c')], 0);
      });
      await showQueue(tester);

      await tester.drag(find.text('c'), const Offset(-300, 0));
      await settle(tester);
      expect(titles(queue.upcoming), ['b']);
      expect(find.text('Usunięto z kolejki: „c”'), findsOneWidget);
      await tester.tap(find.text('Cofnij'));
      await settle(tester);
      expect(titles(queue.upcoming), ['b', 'c']);

      // Not far enough: nothing happens.
      await tester.drag(find.text('c'), const Offset(40, 0));
      await settle(tester);
      expect(titles(queue.upcoming), ['b', 'c']);

      await tester.drag(find.text('c'), const Offset(300, 0));
      await settle(tester);
      expect(titles(queue.upcoming), ['c', 'b']);

      // "Usunięto z kolejki" goes by itself, even with its "Cofnij".
      await tester.drag(find.text('b'), const Offset(-300, 0));
      await settle(tester);
      expect(find.text('Cofnij'), findsOneWidget);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Cofnij'), findsNothing);
    },
  );

  testWidgets('"Kolejka": the last 5 songs before the current one, above it; '
      'tapping one goes back to it', (tester) async {
    await tester.runAsync(() async {
      await queue.start([for (var i = 0; i < 8; i++) _file('$i')], 7);
    });
    await showQueue(tester);
    // Opens at the song playing; the earlier songs are above, out of sight.
    expect(
      tester.getTopLeft(find.text('Teraz odtwarzane')).dy,
      lessThan(tester.getTopLeft(find.byType(AppBar)).dy + 150),
    );
    expect(find.text('Poprzednie').hitTestable(), findsNothing);

    await tester.drag(find.text('Teraz odtwarzane'), const Offset(0, 1500));
    await settle(tester);
    expect(find.text('Poprzednie'), findsOneWidget);
    for (final shown in ['2', '3', '4', '5', '6']) {
      expect(find.text(shown), findsOneWidget);
    }
    expect(find.text('1'), findsNothing);
    expect(
      tester.getCenter(find.text('2')).dy,
      lessThan(tester.getCenter(find.text('6')).dy),
      reason: 'oldest first',
    );

    await tester.tap(find.text('5'));
    await tester.pump();
    expect(backend.opened.last, '/music/5.mp3');
    expect(titles(queue.upcoming), ['6', '7']);
  });

  testWidgets('"Kolejka": the handle moves a song', (tester) async {
    await tester.runAsync(() async {
      await queue.start([_file('a'), _file('b'), _file('c'), _file('d')], 0);
    });
    await showQueue(tester);
    final handle = find.byIcon(Icons.drag_handle);
    final rowHeight =
        tester.getCenter(find.text('c')).dy -
        tester.getCenter(find.text('b')).dy;
    final gesture = await tester.startGesture(tester.getCenter(handle.last));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, -rowHeight * 2.2 / 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester);
    expect(titles(queue.upcoming), ['d', 'b', 'c']);
    expect(queue.upcoming.first.pinned, isTrue);
  });

  testWidgets('dragging a song row to the right adds it to the queue', (
    tester,
  ) async {
    await tester.runAsync(() => queue.start([_file('a')], 0));
    await tester.pumpWidget(
      PlayerScope(
        notifier: player,
        child: PlaybackQueueScope(
          notifier: queue,
          child: MaterialApp(
            theme: buildAppTheme(dummifyTheme),
            home: Scaffold(
              body: ListView(children: [SongTile(hit: _file('b'))]),
            ),
          ),
        ),
      ),
    );

    // Not far enough, or the other way: nothing.
    await tester.drag(find.text('b'), const Offset(40, 0));
    await tester.drag(find.text('b'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(queue.upcoming, isEmpty);

    await tester.drag(find.text('b'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(titles(queue.upcoming), ['b']);
    expect(find.text('Dodano do kolejki'), findsOneWidget);
    expect(backend.opened, ['/music/a.mp3'], reason: 'a keeps playing');
  });

  testWidgets('in the app shell, adding shows a short note with "Otwórz"', (
    tester,
  ) async {
    final toast = QueueToast();
    addTearDown(toast.dispose);
    await tester.runAsync(() => queue.start([_file('a')], 0));
    await tester.pumpWidget(
      PlayerScope(
        notifier: player,
        child: PlaybackQueueScope(
          notifier: queue,
          child: YouTubeLibraryScope(
            notifier: youTubeLibrary,
            child: MaterialApp(
              theme: buildAppTheme(dummifyTheme),
              home: QueueToastScope(
                notifier: toast,
                child: Scaffold(
                  body: Column(
                    children: [
                      Expanded(
                        child: ListView(children: [SongTile(hit: _file('b'))]),
                      ),
                      const QueueToastView(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.text('b'), const Offset(300, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Dodano do kolejki'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(QueueToast.duration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Dodano do kolejki'), findsNothing);

    // "Otwórz" opens the queue.
    await tester.drag(find.text('b'), const Offset(300, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Otwórz'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Kolejka'), findsOneWidget);
    expect(toast.shown, isNull);
  });

  testWidgets(
    'swiping the mini player: left the next song, right the previous',
    (tester) async {
      await tester.runAsync(() => queue.start([_file('a'), _file('b')], 0));
      await tester.pumpWidget(
        PlayerScope(
          notifier: player,
          child: PlaybackQueueScope(
            notifier: queue,
            child: MaterialApp(
              theme: buildAppTheme(dummifyTheme),
              home: const Scaffold(bottomNavigationBar: MiniPlayer()),
            ),
          ),
        ),
      );
      Future<void> swipe(String title, double dx) async {
        await tester.drag(find.text(title), Offset(dx, 0));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      // No song before the first one: it springs back.
      await swipe('a', 300);
      expect(queue.current?.title, 'a');

      await swipe('a', -300);
      expect(queue.current?.title, 'b');
      expect(find.text('b'), findsOneWidget);

      // Not far enough.
      await swipe('b', 30);
      expect(queue.current?.title, 'b');

      // Back to the previous song even well into this one, unlike "Poprzedni".
      backend.at(const Duration(seconds: 30));
      await tester.pump();
      await swipe('b', 300);
      expect(queue.current?.title, 'a');
      expect(backend.opened, ['/music/a.mp3', '/music/b.mp3', '/music/a.mp3']);
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
        prefetchDelay: Duration.zero,
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

  group('mood filter', () {
    late Map<int, Set<String>> moodsOf;
    late MoodFilter filter;
    late PlaybackQueue filtered;

    /// A music.db song on the phone, in [moods].
    SearchHit song(int id, String name, [Set<String> moods = const {}]) {
      moodsOf[id] = moods;
      return SearchHit.main(
        CatalogSong(id: id, title: name, artistLabel: 'X'),
        [
          LocalSong(
            id: id,
            filePath: '/music/$name.mp3',
            title: name,
            mainDbId: id,
            pending: false,
          ),
        ],
      );
    }

    setUp(() async {
      moodsOf = {};
      filter = MoodFilter(
        moodsOf: (id) => moodsOf[id] ?? const {},
        knownMoods: () => {'dance', 'gym', 'calm'},
      );
      await filter.load();
      filtered = PlaybackQueue(
        tracks,
        filter: filter,
        prefetchDelay: Duration.zero,
      );
    });

    tearDown(() {
      filtered.dispose();
      filter.dispose();
    });

    List<String> titles(List<QueueEntry> entries) => [
      for (final e in entries) e.hit.title,
    ];

    test('off: every song plays; on: songs in no ticked mood are hidden and '
        'passed over', () async {
      await filtered.start([
        song(1, 'a', {'calm'}),
        song(2, 'b', {'calm'}),
        song(3, 'c', {'dance'}),
        song(4, 'd', {'gym', 'calm'}),
        _file('e'),
      ], 0);
      expect(titles(filtered.upcoming), ['b', 'c', 'd', 'e']);

      await filter.setMood('dance', true);
      await filter.setMood('gym', true);
      expect(filter.active, isTrue);
      expect(titles(filtered.upcoming), ['c', 'd']);

      backend.finish();
      await flush();
      expect(filtered.current?.title, 'c');
      // "b" was passed over: it's behind, hidden (like "a") while the filter is on.
      expect(filtered.hasPrevious, isFalse);

      await filter.setEnabled(false);
      expect(titles(filtered.history), ['a', 'b']);
      expect(titles(filtered.upcoming), ['d', 'e']);
    });

    test('"bez nastroju" lets through songs in no mood, and those in a ticked '
        'mood', () async {
      await filtered.start([
        song(1, 'a'),
        song(2, 'b', {'calm'}),
        song(3, 'c', {'dance'}),
        song(4, 'd'),
        _file('e'),
      ], 0);
      await filter.setUntagged(true);
      expect(titles(filtered.upcoming), ['d', 'e']);
      await filter.setMood('dance', true);
      expect(titles(filtered.upcoming), ['c', 'd', 'e']);
    });

    test('a ticked mood that is gone does not count', () async {
      await filter.setMood('deleted', true);
      expect(filter.active, isFalse);
      await filtered.start([song(1, 'a'), song(2, 'b')], 0);
      expect(titles(filtered.upcoming), ['b']);
    });

    test('"Następny" and "Poprzedni" skip hidden songs', () async {
      await filtered.start([
        song(1, 'a', {'dance'}),
        song(2, 'b'),
        song(3, 'c', {'dance'}),
      ], 0);
      await filter.setMood('dance', true);
      await filtered.next();
      expect(filtered.current?.title, 'c');
      expect(filtered.hasNext, isFalse);

      await filtered.previous();
      expect(filtered.current?.title, 'a');
      await filter.setEnabled(false);
      expect(titles(filtered.upcoming), ['b', 'c']);
    });

    test('moving a song counts only the songs shown', () async {
      await filtered.start([
        song(1, 'a'),
        song(2, 'b', {'dance'}),
        song(3, 'hidden'),
        song(4, 'c', {'dance'}),
        song(5, 'd', {'dance'}),
      ], 0);
      await filter.setMood('dance', true);
      final d = filtered.upcoming.last;
      filtered.move(d, 1);
      expect(titles(filtered.upcoming), ['b', 'd', 'c']);
      await filter.setEnabled(false);
      expect(titles(filtered.upcoming), ['b', 'd', 'hidden', 'c']);
    });

    Future<void> showRow(WidgetTester tester, SearchHit hit) =>
        tester.pumpWidget(
          PlayerScope(
            notifier: player,
            child: PlaybackQueueScope(
              notifier: filtered,
              child: MoodFilterScope(
                notifier: filter,
                child: MaterialApp(
                  theme: buildAppTheme(dummifyTheme),
                  home: Scaffold(
                    body: ListView(children: [SongTile(hit: hit)]),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('a song added from outside the filter switches it off and '
        'clears it (the default)', (tester) async {
      await tester.runAsync(() async {
        await filtered.start([
          song(1, 'a', {'dance'}),
        ], 0);
        await filter.setMood('dance', true);
      });
      await showRow(tester, song(2, 'b'));
      await tester.drag(find.text('b'), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Utwór dodany do kolejki jest poza filtrami nastroju: wyłączam filtr',
        ),
        findsOneWidget,
      );
      expect(filter.enabled, isFalse);
      expect(filter.moods, isEmpty);
      expect(titles(filtered.upcoming), ['b']);
    });

    testWidgets('or, as set, it is added hidden and passed over', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await filtered.start([
          song(1, 'a', {'dance'}),
        ], 0);
        await filter.setMood('dance', true);
        await filter.setOffWhenAdded(false);
      });
      await showRow(tester, song(2, 'b'));
      await tester.drag(find.text('b'), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Utwór dodany do kolejki jest poza filtrami nastroju: '
          'będzie pominięty',
        ),
        findsOneWidget,
      );
      expect(filter.active, isTrue);
      expect(filtered.upcoming, isEmpty);
      await tester.runAsync(() => filter.setEnabled(false));
      expect(titles(filtered.upcoming), ['b']);
    });

    testWidgets('a song inside the filter is just added', (tester) async {
      await tester.runAsync(() async {
        await filtered.start([
          song(1, 'a', {'dance'}),
        ], 0);
        await filter.setMood('dance', true);
      });
      await showRow(tester, song(2, 'b', {'dance'}));
      await tester.drag(find.text('b'), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(find.text('Dodano do kolejki'), findsOneWidget);
      expect(filter.active, isTrue);
    });
  });
}
