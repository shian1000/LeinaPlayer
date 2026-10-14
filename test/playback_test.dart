import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_database_app/src/screens/now_playing.dart';
import 'package:music_database_app/src/theme.dart';

/// In-memory stand-in for the audio plugin.
class FakeBackend implements AudioBackend {
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _state = StreamController<({bool playing, bool completed})>.broadcast();
  final opened = <String>[];
  Duration? lastSeek;
  bool failOpen = false;

  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration?> get duration => _duration.stream;
  @override
  Stream<({bool playing, bool completed})> get state => _state.stream;
  @override
  Stream<MediaSkip> get skips => const Stream.empty();

  @override
  Future<void> open(NowPlaying track) async {
    if (failOpen) throw Exception('cannot open');
    opened.add(track.source);
    _duration.add(const Duration(minutes: 4, seconds: 26));
  }

  @override
  Future<void> crossfadeTo(NowPlaying track, Duration fade) async {}
  @override
  Future<void> play() async => _state.add((playing: true, completed: false));
  @override
  Future<void> pause() async => _state.add((playing: false, completed: false));
  @override
  Future<void> seek(Duration position) async => lastSeek = position;
  void finish() => _state.add((playing: true, completed: true));
  @override
  Future<void> dispose() async {}
}

const _track = NowPlaying(
  title: 'The Seed',
  artist: 'AURORA',
  source: '/music/AURORA - The Seed.mp3',
  coverSeed: 'seed',
  searchQuery: 'aurora',
);

void main() {
  group('PlayerController', () {
    late FakeBackend backend;
    late PlayerController player;

    setUp(() {
      backend = FakeBackend();
      player = PlayerController(backend: () => backend);
    });

    tearDown(() => player.dispose());

    test('plays, pauses and resumes', () async {
      expect(await player.play(_track), isTrue);
      await pumpEventQueue();
      expect(backend.opened, [_track.source]);
      expect(player.current, same(_track));
      expect(player.playing, isTrue);
      expect(player.duration, const Duration(minutes: 4, seconds: 26));

      await player.togglePlay();
      await pumpEventQueue();
      expect(player.playing, isFalse);
      await player.togglePlay();
      await pumpEventQueue();
      expect(player.playing, isTrue);
    });

    test('a finished song stops at its start', () async {
      await player.play(_track);
      backend.finish();
      await pumpEventQueue();
      expect(player.playing, isFalse);
      expect(backend.lastSeek, Duration.zero);
      expect(player.current, same(_track));
    });

    test(
      'a file that cannot be opened is reported, nothing stays loaded',
      () async {
        backend.failOpen = true;
        expect(await player.play(_track), isFalse);
        expect(player.current, isNull);
        expect(player.lastError, contains('AURORA - The Seed.mp3'));
      },
    );
  });

  testWidgets('mini player opens the full player, which controls playback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final backend = FakeBackend();
    final player = PlayerController(backend: () => backend);
    addTearDown(player.dispose);
    final queue = PlaybackQueue(
      prefetchDelay: Duration.zero,
      TrackPlayer(
        player: player,
        settings: SourceSettings(),
        youTubeLibrary: YouTubeLibrary(
          () => Future.error(StateError('unused')),
        ),
        youTubeAudio: YouTubeAudio(newPipeAvailable: false),
        youTubeSearch: YouTubeSearch(),
      ),
    );
    addTearDown(queue.dispose);
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
    expect(find.text('The Seed'), findsNothing);

    await player.play(_track);
    await tester.pumpAndSettle();
    expect(find.text('The Seed'), findsOneWidget);
    expect(find.byTooltip('Pauza'), findsOneWidget);

    await tester.tap(find.text('The Seed'));
    await tester.pumpAndSettle();
    expect(find.text('Odtwarzanie z wyników wyszukiwania'), findsOneWidget);
    expect(find.text('„aurora” w wyszukiwarce'), findsOneWidget);
    expect(find.text('4:26'), findsOneWidget);

    await tester.tap(find.text('4:26'));
    await tester.pump();
    expect(find.text('-4:26'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'player.show_remaining_time',
      ),
      isTrue,
    );
    await tester.tap(find.text('-4:26'));
    await tester.pump();
    expect(find.text('4:26'), findsOneWidget);

    await tester.tap(find.byTooltip('Pauza').last);
    await tester.pumpAndSettle();
    expect(player.playing, isFalse);

    // Nothing queued before this song: "Poprzedni" restarts it.
    await tester.tap(find.byTooltip('Poprzedni'));
    await tester.pump();
    expect(backend.lastSeek, Duration.zero);

    await tester.tap(find.byTooltip('Zwiń'));
    await tester.pumpAndSettle();
    expect(find.text('Odtwarzanie z wyników wyszukiwania'), findsNothing);
    expect(find.byTooltip('Odtwórz'), findsOneWidget);
  });
}
