import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/track_ref.dart';

/// What a scheduled start plays.
sealed class ScheduledSource {
  const ScheduledSource();

  Map<String, Object?> toJson();

  static ScheduledSource fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'song' => ScheduledSong(
          TrackRef.fromJson((json['song'] as Map).cast<String, Object?>()),
        ),
        'playlist' => ScheduledPlaylist(
          json['playlist_id'] as int,
          json['playlist_name'] as String,
        ),
        _ => const ScheduledLastQueue(),
      };
}

class ScheduledSong extends ScheduledSource {
  const ScheduledSong(this.song);

  final TrackRef song;

  @override
  Map<String, Object?> toJson() => {'kind': 'song', 'song': song.toJson()};
}

class ScheduledPlaylist extends ScheduledSource {
  const ScheduledPlaylist(this.id, this.name);

  final int id;
  final String name;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'playlist',
    'playlist_id': id,
    'playlist_name': name,
  };
}

class ScheduledLastQueue extends ScheduledSource {
  const ScheduledLastQueue();

  @override
  Map<String, Object?> toJson() => {'kind': 'last_queue'};
}

enum ScheduleKind { start, stop }

/// Android's side (`ScheduledMusic.kt`); a fake in tests.
abstract class ScheduledMusicPlatform {
  /// Whether Android accepted it.
  ///
  /// [days]: the weekdays it comes back on ([DateTime.weekday]); Android moves it on by itself,
  /// as the app may not be running then. Empty: once.
  Future<bool> schedule(ScheduleKind kind, DateTime at, Set<int> days);
  Future<void> cancel(ScheduleKind kind);

  /// Whether a scheduled start went off, recently, since this was last asked.
  Future<bool> takeStarted();
  set onFired(void Function(ScheduleKind)? callback);

  /// Whether the user allowed the notification that brings the app up.
  Future<bool> requestNotifications();
  Future<void> setVolume(int percent);

  /// Takes the app off the lock screen and removes the notification.
  Future<void> finishStarting();
}

class ChannelScheduledMusicPlatform implements ScheduledMusicPlatform {
  static const _channel = MethodChannel('music_database_app/scheduled_music');

  @override
  Future<bool> schedule(ScheduleKind kind, DateTime at, Set<int> days) async =>
      await _channel.invokeMethod<bool>('schedule', {
        'kind': kind.name,
        'at': at.millisecondsSinceEpoch,
        'days': days.toList(),
      }) ??
      false;

  @override
  Future<void> cancel(ScheduleKind kind) =>
      _channel.invokeMethod('cancel', kind.name);

  @override
  Future<bool> takeStarted() async =>
      await _channel.invokeMethod<bool>('takeStarted') ?? false;

  @override
  set onFired(void Function(ScheduleKind)? callback) =>
      _channel.setMethodCallHandler(
        callback == null
            ? null
            : (call) async => callback(
                ScheduleKind.values.byName(call.arguments as String),
              ),
      );

  @override
  Future<bool> requestNotifications() async =>
      (await Permission.notification.request()).isGranted;

  @override
  Future<void> setVolume(int percent) =>
      _channel.invokeMethod('setVolume', percent);

  @override
  Future<void> finishStarting() => _channel.invokeMethod('finishStarting');
}

/// The next moment after [now] the clock shows [hour]:[minute], on one of [days]
/// ([DateTime.weekday]) when there are any.
DateTime nextScheduledTime(
  DateTime now,
  int hour,
  int minute, [
  Set<int> days = const {},
]) {
  for (var i = 0; ; i++) {
    // By the calendar, not 24 hours: a day with a clock change is longer or shorter.
    final at = DateTime(now.year, now.month, now.day + i, hour, minute);
    if (at.isAfter(now) && (days.isEmpty || days.contains(at.weekday))) {
      return at;
    }
  }
}

/// A scheduled start's or stop's time.
class ScheduledTime {
  ScheduledTime(this.hour, this.minute);

  bool enabled = false;
  int hour;
  int minute;
  DateTime? nextAt;

  /// The weekdays it repeats on ([DateTime.weekday]); empty: once, then off.
  Set<int> days = {};

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'next_at': nextAt?.millisecondsSinceEpoch,
    'days': (days.toList()..sort()),
  };

  void read(Map<String, Object?> json) {
    enabled = json['enabled'] as bool? ?? false;
    hour = json['hour'] as int? ?? hour;
    minute = json['minute'] as int? ?? minute;
    final at = json['next_at'] as int?;
    nextAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    days = {...(json['days'] as List? ?? const []).cast<int>()};
  }
}

/// Ja › Zaplanowane uruchomienie muzyki / Zaplanowane wyłączenie: each at the set time, once or on
/// the chosen weekdays. Android starts the app if it isn't running ([ScheduledMusicPlatform]) and the music plays
/// with the phone's music volume set as asked; nothing has to be confirmed.
class ScheduledMusic extends ChangeNotifier {
  ScheduledMusic({
    required this.platform,
    required this.play,
    required this.stop,
    this.startTimeout = const Duration(seconds: 30),
  });

  static const _key = 'scheduled_music';
  static const minVolume = 5;

  final ScheduledMusicPlatform platform;
  final Future<bool> Function(ScheduledSource) play;
  final Future<void> Function() stop;

  /// How long the app stays over the lock screen at most, while the music starts.
  final Duration startTimeout;

  final _times = {
    ScheduleKind.start: ScheduledTime(7, 0),
    ScheduleKind.stop: ScheduledTime(23, 0),
  };
  int _volume = 50;
  ScheduledSource _source = const ScheduledLastQueue();
  bool _started = false;

  ScheduledTime timeOf(ScheduleKind kind) => _times[kind]!;

  /// Percent of the phone's music volume.
  int get volume => _volume;
  ScheduledSource get source => _source;

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    final json = (jsonDecode(raw) as Map).cast<String, Object?>();
    for (final kind in ScheduleKind.values) {
      _times[kind]!.read((json[kind.name] as Map? ?? const {}).cast());
    }
    _volume = json['volume'] as int? ?? _volume;
    _source = ScheduledSource.fromJson(
      (json['source'] as Map? ?? const {}).cast<String, Object?>(),
    );
    notifyListeners();
  }

  /// Once the queue is restored, as "Ostatnia kolejka" needs it: plays if that's why the app
  /// started, drops what was missed with the phone off, and tells Android again what a restored
  /// backup set.
  Future<void> start() async {
    if (_started || kIsWeb || !Platform.isAndroid) return;
    _started = true;
    platform.onFired = (kind) => unawaited(
      fired(kind).catchError(
        (Object e) => debugPrint('Scheduled ${kind.name} failed: $e'),
      ),
    );
    await fired(ScheduleKind.start);
    var changed = false;
    for (final kind in ScheduleKind.values) {
      final time = timeOf(kind);
      final at = time.nextAt;
      if (!time.enabled || at == null) continue;
      if (at.isAfter(DateTime.now())) {
        await platform.schedule(kind, at, time.days);
      } else {
        await _afterItsTime(kind);
        changed = true;
      }
    }
    if (changed) {
      await _save();
      notifyListeners();
    }
  }

  /// [kind]'s time has passed: on to its next day, or off.
  Future<void> _afterItsTime(ScheduleKind kind) async {
    final time = timeOf(kind);
    if (time.days.isNotEmpty) {
      await _arm(kind);
    } else {
      time
        ..enabled = false
        ..nextAt = null;
    }
  }

  Future<bool> _arm(ScheduleKind kind) async {
    final time = timeOf(kind);
    final at = nextScheduledTime(
      DateTime.now(),
      time.hour,
      time.minute,
      time.days,
    );
    final done = await platform.schedule(kind, at, time.days);
    time
      ..enabled = done
      ..nextAt = done ? at : null;
    return done;
  }

  /// Android says [kind]'s time has come.
  @visibleForTesting
  Future<void> fired(ScheduleKind kind) async {
    if (kind == ScheduleKind.start && !await platform.takeStarted()) return;
    await _afterItsTime(kind).catchError(
      (Object e) => debugPrint('Scheduling the next time failed: $e'),
    );
    notifyListeners();
    await _save().catchError(
      (Object e) => debugPrint('Saving the scheduled music failed: $e'),
    );
    if (kind == ScheduleKind.stop) return stop();
    await platform.setVolume(_volume).catchError((Object e) {
      debugPrint('Setting the scheduled volume failed: $e');
    });
    try {
      if (!await play(_source).timeout(startTimeout)) {
        debugPrint('The scheduled music could not be played');
      }
    } on TimeoutException {
      debugPrint('The scheduled music did not start in time');
    } catch (e) {
      debugPrint('Playing the scheduled music failed: $e');
    }
    await platform.finishStarting().catchError((Object e) {
      debugPrint('Finishing the scheduled start failed: $e');
    });
  }

  /// Sets the time and switches it on; returns [setEnabled]'s answer.
  Future<bool> setTime(ScheduleKind kind, int hour, int minute) {
    timeOf(kind)
      ..hour = hour
      ..minute = minute;
    return setEnabled(kind, true);
  }

  /// Returns whether it's as asked: Android can refuse.
  Future<bool> setEnabled(ScheduleKind kind, bool on) async {
    final time = timeOf(kind);
    var done = true;
    if (on) {
      done = await _arm(kind);
    } else {
      time.enabled = false;
      time.nextAt = null;
      await platform.cancel(kind);
    }
    notifyListeners();
    await _save();
    return done;
  }

  /// Which weekdays [kind] repeats on; moves a time that's switched on to the first of them.
  Future<void> setDays(ScheduleKind kind, Set<int> days) async {
    final time = timeOf(kind)..days = days;
    if (time.enabled) await _arm(kind);
    notifyListeners();
    await _save();
  }

  Future<void> setVolume(int percent) async {
    _volume = percent;
    notifyListeners();
    await _save();
  }

  Future<void> setSource(ScheduledSource source) async {
    _source = source;
    notifyListeners();
    await _save();
  }

  Future<bool> requestNotifications() => platform.requestNotifications();

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        for (final kind in ScheduleKind.values)
          kind.name: timeOf(kind).toJson(),
        'volume': _volume,
        'source': _source.toJson(),
      }),
    );
  }

  @override
  void dispose() {
    if (_started) platform.onFired = null;
    super.dispose();
  }
}

class ScheduledMusicScope extends InheritedNotifier<ScheduledMusic> {
  const ScheduledMusicScope({
    super.key,
    required ScheduledMusic super.notifier,
    required super.child,
  });

  static ScheduledMusic? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ScheduledMusicScope>()
      ?.notifier;

  static ScheduledMusic of(BuildContext context) => maybeOf(context)!;
}
