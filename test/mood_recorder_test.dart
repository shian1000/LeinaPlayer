import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/playback/mood_recorder.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late StreamController<QueuePlay> played;
  late StreamController<Duration> positions;
  late List<(String, String)> added;
  late Set<String> moods;
  late bool playing;
  Duration? duration;
  late MoodRecorder recorder;

  MoodRecorder make() => MoodRecorder(
    played: played.stream,
    positions: positions.stream,
    playing: () => playing,
    duration: () => duration,
    createMood: (name) async {
      moods.add('uid-$name');
      return 'uid-$name';
    },
    addSong: (uid, hit) async {
      if (!moods.contains(uid)) return false;
      added.add((uid, hit.title));
      return true;
    },
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    played = StreamController.broadcast(sync: true);
    positions = StreamController.broadcast(sync: true);
    added = [];
    moods = {};
    playing = true;
    duration = const Duration(minutes: 4);
    recorder = make();
  });

  tearDown(() => recorder.dispose());

  void play(String title, {bool external = false}) => played.add((
    hit: SearchHit.youTubeOnly(title: title, artistLabel: 'A', videoId: title),
    playlistId: null,
    index: null,
    playlistName: null,
    moodKey: null,
    external: external,
  ));

  /// Plays on from [from] for [seconds], a position each second.
  Future<void> listen(int seconds, {int from = 0}) async {
    for (var s = from; s <= from + seconds; s++) {
      positions.add(Duration(seconds: s));
    }
    await Future<void>.delayed(Duration.zero);
  }

  test('adds a song once it has been heard for a minute', () async {
    await recorder.start('Wieczór');
    play('Krótko');
    await listen(59);
    play('Długo');
    await listen(61);
    await listen(30, from: 61);
    expect(added, [('uid-Wieczór', 'Długo')]);
  });

  test('seeks and paused time do not count', () async {
    await recorder.start('Wieczór');
    play('Przewinięty');
    await listen(20);
    positions.add(const Duration(minutes: 3));
    playing = false;
    await listen(50, from: 180);
    expect(added, isEmpty);
  });

  test('a song shorter than a minute counts when heard almost whole', () async {
    await recorder.start('Wieczór');
    duration = const Duration(seconds: 40);
    play('Miniatura');
    await listen(37);
    expect(added, [('uid-Wieczór', 'Miniatura')]);
  });

  test('records nothing when off, nor what the YouTube app plays', () async {
    play('Bez nagrywania');
    await listen(70);
    play('Chwilę przed');
    await listen(10);
    await recorder.start('Wieczór');
    play('W aplikacji YouTube', external: true);
    await listen(70);
    await recorder.stop();
    play('Po zatrzymaniu');
    await listen(70);
    expect(added, isEmpty);
  });

  test('the song playing when it starts counts from where it is', () async {
    play('W trakcie');
    await listen(50);
    await recorder.start('Wieczór');
    await listen(15, from: 50);
    expect(added, [('uid-Wieczór', 'W trakcie')]);
  });

  test('stays on across restarts and stops when the mood is gone', () async {
    await recorder.start('Wieczór');
    recorder.dispose();
    recorder = make();
    await recorder.load();
    expect(recorder.moodUid, 'uid-Wieczór');
    moods.clear();
    play('Po usunięciu');
    await listen(61);
    await Future<void>.delayed(Duration.zero);
    expect(recorder.recording, isFalse);
  });
}
