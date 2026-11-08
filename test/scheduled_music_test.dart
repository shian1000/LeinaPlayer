import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/playback/scheduled_music.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePlatform implements ScheduledMusicPlatform {
  final scheduled = <ScheduleKind, DateTime>{};
  bool accepts = true;
  bool started = false;
  int? volume;
  bool finished = false;

  @override
  Future<bool> schedule(ScheduleKind kind, DateTime at, Set<int> days) async {
    if (accepts) scheduled[kind] = at;
    return accepts;
  }

  @override
  Future<void> cancel(ScheduleKind kind) async => scheduled.remove(kind);

  @override
  Future<bool> takeStarted() async {
    final was = started;
    started = false;
    return was;
  }

  @override
  void Function(ScheduleKind)? onFired;

  @override
  Future<bool> requestNotifications() async => true;

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
    await music.setTime(ScheduleKind.stop, 23, 0);
    await music.setDays(ScheduleKind.stop, {1, 2, 3, 4, 5, 6, 7});
    await music.fired(ScheduleKind.stop);
    final time = music.timeOf(ScheduleKind.stop);
    expect(stops, 1);
    expect(time.enabled, isTrue);
    expect(platform.scheduled[ScheduleKind.stop], time.nextAt);
    expect(time.nextAt!.isAfter(DateTime.now()), isTrue);
  });

  test('days come back after a restart', () async {
    await make().setDays(ScheduleKind.start, {1, 5});
    final second = make();
    await second.load();
    expect(second.timeOf(ScheduleKind.start).days, {1, 5});
  });

  test('start and stop are scheduled and cancelled apart', () async {
    final music = make();
    await music.setTime(ScheduleKind.start, 7, 30);
    await music.setTime(ScheduleKind.stop, 23, 5);
    expect(platform.scheduled.keys, unorderedEquals(ScheduleKind.values));
    expect(music.timeOf(ScheduleKind.start).label, '07:30');

    await music.setEnabled(ScheduleKind.start, false);
    expect(platform.scheduled.keys, [ScheduleKind.stop]);
    expect(music.timeOf(ScheduleKind.stop).enabled, isTrue);
  });

  test('stays off when Android refuses', () async {
    platform.accepts = false;
    final music = make();
    expect(await music.setEnabled(ScheduleKind.stop, true), isFalse);
    expect(music.timeOf(ScheduleKind.stop).enabled, isFalse);
  });

  test('settings come back after a restart', () async {
    final first = make();
    await first.setVolume(35);
    await first.setSource(const ScheduledPlaylist(3, 'Rano'));
    await first.setTime(ScheduleKind.start, 6, 5);

    final second = make();
    await second.load();
    expect(second.volume, 35);
    expect(second.timeOf(ScheduleKind.start).label, '06:05');
    expect(second.timeOf(ScheduleKind.start).enabled, isTrue);
    expect((second.source as ScheduledPlaylist).name, 'Rano');
  });

  test('a start plays at its volume, switches off and finishes', () async {
    final music = make();
    await music.setTime(ScheduleKind.start, 7, 0);
    platform.started = true;
    await music.fired(ScheduleKind.start);
    expect(played, isA<ScheduledLastQueue>());
    expect(platform.volume, 50);
    expect(music.timeOf(ScheduleKind.start).enabled, isFalse);
    expect(platform.finished, isTrue);
  });

  test('a start Android did not report plays nothing', () async {
    await make().fired(ScheduleKind.start);
    expect(played, isNull);
  });

  test('music that never starts still finishes', () async {
    outcome = () => Future.delayed(const Duration(days: 1), () => true);
    platform.started = true;
    await make().fired(ScheduleKind.start);
    expect(platform.finished, isTrue);
  });

  test('a stop stops the music and switches off', () async {
    final music = make();
    await music.setTime(ScheduleKind.stop, 23, 0);
    await music.fired(ScheduleKind.stop);
    expect(stops, 1);
    expect(music.timeOf(ScheduleKind.stop).enabled, isFalse);
    expect(played, isNull);
  });
}
