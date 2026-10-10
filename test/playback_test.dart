import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
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
  Future<void> open(String filePath) async {
    if (failOpen) throw Exception('cannot open');
    opened.add(filePath);
    _duration.add(const Duration(minutes: 4, seconds: 26));
  }

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
  filePath: '/music/AURORA - The Seed.mp3',
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
      expect(backend.opened, [_track.filePath]);
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
    final backend = FakeBackend();
    final player = PlayerController(backend: () => backend);
    addTearDown(player.dispose);
    await tester.pumpWidget(
      PlayerScope(
        notifier: player,
        child: MaterialApp(
          theme: buildAppTheme(dummifyTheme),
          home: const Scaffold(bottomNavigationBar: MiniPlayer()),
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

    await tester.tap(find.byTooltip('Pauza').last);
    await tester.pumpAndSettle();
    expect(player.playing, isFalse);

    await tester.tap(find.byTooltip('Poprzedni'));
    expect(backend.lastSeek, Duration.zero);

    await tester.tap(find.byTooltip('Zwiń'));
    await tester.pumpAndSettle();
    expect(find.text('Odtwarzanie z wyników wyszukiwania'), findsNothing);
    expect(find.byTooltip('Odtwórz'), findsOneWidget);
  });
}
