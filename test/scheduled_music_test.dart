import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/playback/scheduled_music.dart';
import 'package:music_database_app/src/screens/scheduled_music_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePlatform implements ScheduledMusicPlatform {
  final scheduled = <String, DateTime>{};
  bool accepts = true;
  String? started;
  int? volume;
  bool finished = false;

  @override
  Future<bool> schedule(String key, DateTime at, Set<int> days) async {
    if (accepts) scheduled[key] = at;
    return accepts;
  }

  @override
  Future<void> cancel(String key) async => scheduled.remove(key);

  @override
  Future<void> cancelAllBut(Set<String> keys) async =>
      scheduled.removeWhere((key, _) => !keys.contains(key));

  @override
  Future<String?> takeStarted() async {
    final was = started;
    started = null;
    return was;
  }

  @override
  void Function(String)? onFired;

  @override
  Future<bool> requestNotifications() async => true;

  @override
  Future<bool> canStartApp() async => true;

  @override
  Future<bool> openStartAppSettings() async => true;

  @override
  Future<void> setVolume(int percent) async => volume = percent;

  @override
  Future<void> finishStarting() async => finished = true;
}

void main() {
  late _FakePlatform platform;
  ScheduledSource? played;
  late Future<bool> Function() outcome;
  var stops = 0;

  ScheduledMusic make() => ScheduledMusic(
    platform: platform,
    play: (source) {
      played = source;
      return outcome();
    },
    stop: () async => stops++,
    startTimeout: const Duration(milliseconds: 20),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    platform = _FakePlatform();
    played = null;
    stops = 0;
    outcome = () async => true;
  });

  test('a time still to come is today, one gone or now is tomorrow', () {
    expect(
      nextScheduledTime(DateTime(2026, 11, 8, 6, 30), 7, 0),
      DateTime(2026, 11, 8, 7),
    );
    expect(
      nextScheduledTime(DateTime(2026, 11, 30, 7), 7, 0),
      DateTime(2026, 12, 1, 7),
    );
  });

  test('with days, the next ticked weekday at that time', () {
    // 2026-11-08 is a Sunday.
    final sunday = DateTime(2026, 11, 8, 12);
    expect(
      nextScheduledTime(sunday, 7, 0, {DateTime.wednesday}),
      DateTime(2026, 11, 11, 7),
    );
    expect(
      nextScheduledTime(sunday, 13, 0, {DateTime.sunday}),
      DateTime(2026, 11, 8, 13),
    );
    expect(
      nextScheduledTime(sunday, 7, 0, {DateTime.sunday}),
      DateTime(2026, 11, 15, 7),
    );
  });

  test('a repeating time stays on and moves to its next day', () async {
    final music = make();
    final stop = music.stopTime;
    await music.setTime(stop, 23, 0);
    await music.setDays(stop, {1, 2, 3, 4, 5, 6, 7});
    await music.fired(ScheduledMusic.stopKey);
    expect(stops, 1);
    expect(stop.enabled, isTrue);
    expect(platform.scheduled['stop'], stop.nextAt);
    expect(stop.nextAt!.isAfter(DateTime.now()), isTrue);
  });

  test('days come back after a restart', () async {
    final first = make();
    final (:start, ok: _) = await first.addStart(7, 0);
    await first.setDays(start, {1, 5});
    final second = make();
    await second.load();
    expect(second.starts.single.days, {1, 5});
  });

  test('starts and the stop are scheduled and cancelled apart', () async {
    final music = make();
    final (start: early, ok: _) = await music.addStart(7, 30);
    final (start: late, ok: _) = await music.addStart(9, 0);
    await music.setTime(music.stopTime, 23, 5);
    expect(early.key, isNot(late.key));
    expect(
      platform.scheduled.keys,
      unorderedEquals([early.key, late.key, 'stop']),
    );
    expect(early.label, '07:30');

    await music.setEnabled(early, false);
    expect(platform.scheduled.keys, unorderedEquals([late.key, 'stop']));
    expect(late.enabled, isTrue);

    await music.removeStart(late);
    expect(music.starts, [early]);
    expect(platform.scheduled.keys, ['stop']);
  });

  test('starts are listed by the time of day', () async {
    final music = make();
    await music.addStart(9, 0);
    await music.addStart(6, 45);
    await music.addStart(7, 0);
    expect(music.starts.map((s) => s.label), ['06:45', '07:00', '09:00']);
  });

  test('a start brought back is scheduled again', () async {
    final music = make();
    final (:start, ok: _) = await music.addStart(7, 0);
    await music.removeStart(start);
    expect(platform.scheduled, isEmpty);
    await music.restoreStart(start);
    expect(music.starts, [start]);
    expect(platform.scheduled[start.key], start.nextAt);
  });

  test('stays off when Android refuses', () async {
    platform.accepts = false;
    final music = make();
    expect(await music.setEnabled(music.stopTime, true), isFalse);
    expect(music.stopTime.enabled, isFalse);
  });

  test('Ja\'s summary names what is switched on', () async {
    final music = make();
    expect(scheduledSummary(music), 'Wyłączone');
    await music.setTime(music.stopTime, 23, 0);
    expect(scheduledSummary(music), 'Wyłączenie o 23:00');
    await music.addStart(7, 5);
    expect(
      scheduledSummary(music),
      'Uruchomienie o 07:05 • wyłączenie o 23:00',
    );
    final (:start, ok: _) = await music.addStart(6, 0);
    expect(
      scheduledSummary(music),
      'Uruchomienia o 06:00, 07:05 • wyłączenie o 23:00',
    );
    await music.setEnabled(start, false);
    expect(
      scheduledSummary(music),
      'Uruchomienie o 07:05 • wyłączenie o 23:00',
    );
  });

  test('each start keeps its own settings after a restart', () async {
    final first = make();
    final (start: morning, ok: _) = await first.addStart(6, 5);
    final (start: noon, ok: _) = await first.addStart(12, 0);
    await first.setVolume(morning, 35);
    await first.setSource(morning, const ScheduledPlaylist(3, 'Rano'));
    await first.setEnabled(noon, false);

    final second = make();
    await second.load();
    final [a, b] = second.starts;
    expect(a.label, '06:05');
    expect(a.enabled, isTrue);
    expect(a.volume, 35);
    expect((a.source as ScheduledPlaylist).name, 'Rano');
    expect(b.label, '12:00');
    expect(b.enabled, isFalse);
    expect(b.volume, 50);
    expect(b.source, isA<ScheduledLastQueue>());
    expect(b.key, noon.key);
  });

  test('the single start of older versions becomes the first one', () async {
    final at = DateTime.now().add(const Duration(hours: 1));
    SharedPreferences.setMockInitialValues({
      'scheduled_music': jsonEncode({
        'start': {
          'enabled': true,
          'hour': at.hour,
          'minute': at.minute,
          'next_at': at.millisecondsSinceEpoch,
          'days': [1],
        },
        'stop': {'enabled': false, 'hour': 22, 'minute': 0},
        'volume': 40,
        'source': {'kind': 'playlist', 'playlist_id': 2, 'playlist_name': 'X'},
      }),
    });
    final music = make();
    await music.load();
    final start = music.starts.single;
    expect(start.key, 'start');
    expect(start.enabled, isTrue);
    expect(start.days, {1});
    expect(start.volume, 40);
    expect((start.source as ScheduledPlaylist).name, 'X');
    expect(music.stopTime.label, '22:00');
    final (start: added, ok: _) = await music.addStart(8, 0);
    expect(added.key, 'start_1');
  });

  test(
    'the start Android reports plays at its volume and switches off',
    () async {
      final music = make();
      final (start: other, ok: _) = await music.addStart(6, 0);
      final (:start, ok: _) = await music.addStart(7, 0);
      await music.setVolume(start, 70);
      await music.setSource(start, const ScheduledPlaylist(1, 'Pobudka'));
      platform.started = start.key;
      await music.fired(start.key);
      expect((played as ScheduledPlaylist).name, 'Pobudka');
      expect(platform.volume, 70);
      expect(start.enabled, isFalse);
      expect(other.enabled, isTrue);
      expect(platform.finished, isTrue);
    },
  );

  test('a start Android did not report plays nothing', () async {
    final music = make();
    final (:start, ok: _) = await music.addStart(7, 0);
    await music.fired(start.key);
    expect(played, isNull);
  });

  test(
    'a start removed before it went off plays nothing but finishes',
    () async {
      final music = make();
      final (:start, ok: _) = await music.addStart(7, 0);
      await music.removeStart(start);
      platform.started = start.key;
      await music.fired(start.key);
      expect(played, isNull);
      expect(platform.finished, isTrue);
    },
  );

  test('music that never starts still finishes', () async {
    outcome = () => Future.delayed(const Duration(days: 1), () => true);
    final music = make();
    final (:start, ok: _) = await music.addStart(7, 0);
    platform.started = start.key;
    await music.fired(start.key);
    expect(platform.finished, isTrue);
  });

  test('a stop stops the music and switches off', () async {
    final music = make();
    await music.setTime(music.stopTime, 23, 0);
    await music.fired(ScheduledMusic.stopKey);
    expect(stops, 1);
    expect(music.stopTime.enabled, isFalse);
    expect(played, isNull);
  });

  testWidgets('the starts are listed and dragged left to delete', (
    tester,
  ) async {
    final music = make();
    await music.addStart(9, 15);
    await music.addStart(6, 30);
    await tester.pumpWidget(
      ScheduledMusicScope(
        notifier: music,
        child: MaterialApp(
          theme: buildAppTheme(dummifyTheme),
          home: const ScheduledStartsScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('06:30'), findsOneWidget);
    expect(find.text('09:15'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('06:30')).dy,
      lessThan(tester.getTopLeft(find.text('09:15')).dy),
    );

    await tester.drag(find.text('06:30'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('06:30'), findsNothing);
    expect(music.starts.single.label, '09:15');
    expect(find.text('Usunięto uruchomienie o 06:30'), findsOneWidget);

    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(find.text('06:30'), findsOneWidget);
    expect(music.starts, hasLength(2));
  });

  testWidgets('with no starts the list says how to add one', (tester) async {
    await tester.pumpWidget(
      ScheduledMusicScope(
        notifier: make(),
        child: MaterialApp(
          theme: buildAppTheme(dummifyTheme),
          home: const ScheduledStartsScreen(),
        ),
      ),
    );
    expect(
      find.textContaining('Nie masz jeszcze zaplanowanych uruchomień'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
