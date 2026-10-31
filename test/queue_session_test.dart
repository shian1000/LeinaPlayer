import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/track_ref.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/queue_session.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Backend implements AudioBackend {
  final opened = <String>[];
  final seeks = <Duration>[];
  final calls = <String>[];

  /// Like just_audio: the playing state comes a while after play() returns.
  bool playingStateLater = false;
  final _position = StreamController<Duration>.broadcast();
  final _state = StreamController<({bool playing, bool completed})>.broadcast();

  void at(Duration position) => _position.add(position);

  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration?> get duration => const Stream.empty();
  @override
  Stream<({bool playing, bool completed})> get state => _state.stream;
  @override
  Stream<MediaSkip> get skips => const Stream.empty();
  @override
  Future<void> open(NowPlaying track) async {
    opened.add(track.source);
    calls.add('open');
  }

  @override
  Future<void> crossfadeTo(NowPlaying track, Duration fade) async {}
  @override
  Future<void> play() async {
    calls.add('play');
    void report() => _state.add((playing: true, completed: false));
    playingStateLater
        ? Timer(const Duration(milliseconds: 20), report)
        : report();
  }

  @override
  Future<void> pause() async => _state.add((playing: false, completed: false));
  @override
  Future<void> fadeOutAndPause(Duration fade) => pause();
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    calls.add('seek ${position.inSeconds}');
  }

  @override
  Future<void> dispose() async {}
}

SearchHit _file(String name) => SearchHit.phoneOnly(
  LocalSong(id: 1, filePath: '/music/$name.mp3', title: name, pending: true),
);

SearchHit _resolve(TrackRef ref) => SearchHit.phoneOnly(
  LocalSong(id: 1, filePath: ref.filePath!, title: ref.title, pending: true),
);

void main() {
  late SourceSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SourceSettings();
    await settings.load();
  });

  ({_Backend backend, PlayerController player, PlaybackQueue queue}) app() {
    final backend = _Backend();
    final player = PlayerController(backend: () => backend);
    final queue = PlaybackQueue(
      prefetchDelay: Duration.zero,
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
    return (backend: backend, player: player, queue: queue);
  }

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test(
    'after a restart: the last song paused where it was, the same queue',
    () async {
      final before = app();
      final session = QueueSession(
        queue: before.queue,
        player: before.player,
        resolve: _resolve,
      );
      await session.restore(); // nothing saved yet
      expect(before.player.current, isNull);

      await before.queue.start(
        [_file('a'), _file('b'), _file('c')],
        1,
        playlistId: 7,
        playlistName: 'Do auta',
        moodKey: 'u3',
      );
      await before.queue.add([_file('x')]);
      before.backend.at(const Duration(seconds: 42));
      await flush();
      await before.player.togglePlay(); // pause: saved
      await session.save();
      session.dispose();

      final after = app();
      await QueueSession(
        queue: after.queue,
        player: after.player,
        resolve: _resolve,
      ).restore();
      expect(after.player.current?.title, 'b');
      expect(after.player.current?.playlistName, 'Do auta');
      expect(after.player.playing, isFalse);
      expect(after.player.restored, isTrue);
      expect(after.player.currentPosition, const Duration(seconds: 42));
      expect(
        after.backend.opened,
        isEmpty,
        reason: 'nothing loaded until play',
      );
      expect([for (final e in after.queue.upcoming) e.hit.title], ['c', 'x']);
      expect(after.queue.currentEntry?.origin?.playlistId, 7);
      expect(after.queue.currentEntry?.origin?.moodKey, 'u3');
      expect(after.queue.hasPrevious, isTrue, reason: 'a played before b');

      after.backend.playingStateLater = true;
      await after.player.togglePlay();
      expect(after.backend.opened, ['/music/b.mp3']);
      expect(after.backend.calls, [
        'open',
        'seek 42',
        'play',
      ], reason: 'starts where it was, without the song\'s start heard first');
      expect(after.player.currentPosition, const Duration(seconds: 42));
      expect(after.player.restored, isFalse);
    },
  );

  test('songs that start playing are reported for the history', () async {
    final a = app();
    final plays = <QueuePlay>[];
    a.queue.played.listen(plays.add);
    await a.queue.start(
      [_file('a'), _file('b')],
      0,
      playlistId: 3,
      playlistName: 'P',
    );
    await a.queue.playNext([_file('x')]);
    await a.queue.next();
    await flush();
    expect(
      [for (final p in plays) (p.hit.title, p.playlistId)],
      [('a', 3), ('x', null)],
    );
  });

  test('the queue a new one replaced is kept across a restart, and comes back '
      'playing where it was', () async {
    final before = app();
    final session = QueueSession(
      queue: before.queue,
      player: before.player,
      resolve: _resolve,
    );
    await session.restore();
    await before.queue.start(
      [_file('a'), _file('b'), _file('c')],
      1,
      playlistName: 'Do auta',
    );
    before.backend.at(const Duration(seconds: 42));
    await flush();
    await before.queue.start([_file('z')], 0);
    expect(before.queue.replaced?.songCount, 3);
    expect(before.queue.replaced?.name, 'Do auta');
    await session.save();
    session.dispose();

    final after = app();
    await QueueSession(
      queue: after.queue,
      player: after.player,
      resolve: _resolve,
    ).restore();
    expect(after.player.current?.title, 'z');
    expect(after.queue.replaced?.current.title, 'b');

    after.backend.playingStateLater = true;
    await after.queue.playReplaced();
    expect(after.queue.current?.title, 'b');
    expect([for (final e in after.queue.upcoming) e.hit.title], ['c']);
    expect(after.queue.hasPrevious, isTrue, reason: 'a played before b');
    expect(after.backend.opened, ['/music/b.mp3']);
    expect(
      after.backend.calls,
      containsAllInOrder(['open', 'seek 42', 'play']),
    );
    // A single song isn't worth keeping: nothing to swap back to.
    expect(after.queue.replaced, isNull);
  });
}
