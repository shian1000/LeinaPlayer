import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

/// Android's side (`ScheduledMusic.kt`); a fake in tests.
///
/// Each time is known there by its [ScheduledTime.key]: [ScheduledMusic.stopKey] or a start's.
abstract class ScheduledMusicPlatform {
  /// Whether Android accepted it.
  ///
  /// [days]: the weekdays it comes back on ([DateTime.weekday]); Android moves it on by itself,
  /// as the app may not be running then. Empty: once.
  Future<bool> schedule(String key, DateTime at, Set<int> days);
  Future<void> cancel(String key);

  /// Cancels every time Android keeps but [keys] (left by a restored backup).
  Future<void> cancelAllBut(Set<String> keys);

  /// The key of a scheduled start that went off, recently, since this was last asked.
  Future<String?> takeStarted();
  set onFired(void Function(String key)? callback);

  /// Whether the user allowed the notification that brings the app up.
  Future<bool> requestNotifications();

  /// Whether that notification may open the app by itself (Android 14+ asks for it apart).
  Future<bool> canStartApp();

  /// Opens Android's screen for allowing it; false when there is none.
  Future<bool> openStartAppSettings();
  Future<void> setVolume(int percent);

  /// Takes the app off the lock screen and removes the notification.
  Future<void> finishStarting();
}

class ChannelScheduledMusicPlatform implements ScheduledMusicPlatform {
  static const _channel = MethodChannel('music_database_app/scheduled_music');

  @override
  Future<bool> schedule(String key, DateTime at, Set<int> days) async =>
      await _channel.invokeMethod<bool>('schedule', {
        'key': key,
        'at': at.millisecondsSinceEpoch,
        'days': days.toList(),
      }) ??
      false;

  @override
  Future<void> cancel(String key) => _channel.invokeMethod('cancel', key);

  @override
  Future<void> cancelAllBut(Set<String> keys) =>
      _channel.invokeMethod('cancelAllBut', keys.toList());

  @override
  Future<String?> takeStarted() => _channel.invokeMethod<String>('takeStarted');

  @override
  set onFired(void Function(String key)? callback) =>
      _channel.setMethodCallHandler(
        callback == null
            ? null
            : (call) async => callback(call.arguments as String),
      );

  @override
  Future<bool> requestNotifications() async =>
      (await Permission.notification.request()).isGranted;

  @override
  Future<bool> canStartApp() async =>
      await _channel.invokeMethod<bool>('canStartApp') ?? true;

  @override
  Future<bool> openStartAppSettings() async =>
      await _channel.invokeMethod<bool>('openStartAppSettings') ?? false;

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
  ScheduledTime(this.key, this.hour, this.minute);

  /// What Android knows it by.
  final String key;
  bool enabled = false;
  int hour;
  int minute;
  DateTime? nextAt;

  /// The weekdays it repeats on ([DateTime.weekday]); empty: once, then off.
  Set<int> days = {};

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  bool get isOn => enabled && nextAt != null;

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

/// One of the scheduled starts, like one of the phone's alarms: its time, how loud and what plays.
class ScheduledStart extends ScheduledTime {
  // The first start keeps the key the single start of older versions had, so Android's alarm
  // set by them is this one, not a second.
  ScheduledStart(this.id, int hour, int minute)
    : super(id == 0 ? 'start' : 'start_$id', hour, minute);

  final int id;

  /// Percent of the phone's music volume.
  int volume = 50;
  ScheduledSource source = const ScheduledLastQueue();

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'id': id,
    'volume': volume,
    'source': source.toJson(),
  };

  @override
  void read(Map<String, Object?> json) {
    super.read(json);
    volume = json['volume'] as int? ?? volume;
    source = ScheduledSource.fromJson(
      (json['source'] as Map? ?? const {}).cast<String, Object?>(),
    );
  }
}

/// Ja › Zaplanowana muzyka › Zaplanowane uruchomienie (several, like the phone's alarms) /
/// Zaplanowane wyłączenie: each at the set time, once or on the chosen weekdays. Android starts
/// the app if it isn't running ([ScheduledMusicPlatform]) and the music plays with the phone's
/// music volume set as asked; nothing has to be confirmed.
class ScheduledMusic extends ChangeNotifier {
  ScheduledMusic({
    required this.platform,
    required this.play,
    required this.stop,
    this.startTimeout = const Duration(seconds: 30),
  });

  static const _key = 'scheduled_music';
  static const stopKey = 'stop';
  static const minVolume = 5;

  final ScheduledMusicPlatform platform;
  final Future<bool> Function(ScheduledSource) play;
  final Future<void> Function() stop;

  /// How long the app stays over the lock screen at most, while the music starts.
  final Duration startTimeout;

  final _starts = <ScheduledStart>[];
  final stopTime = ScheduledTime(stopKey, 23, 0);
  bool _started = false;

  /// By the time of day, as the phone's alarms are listed.
  List<ScheduledStart> get starts => [..._starts]
    ..sort((a, b) {
      final byTime = (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

  Iterable<ScheduledTime> get _times => [..._starts, stopTime];

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    final json = (jsonDecode(raw) as Map).cast<String, Object?>();
    stopTime.read((json[stopKey] as Map? ?? const {}).cast());
    _starts.clear();
    final starts = json['starts'] as List?;
    if (starts != null) {
      for (final raw in starts) {
        final start = (raw as Map).cast<String, Object?>();
        _starts.add(ScheduledStart(start['id'] as int, 7, 0)..read(start));
      }
    } else if (json['start'] is Map) {
      // Older versions had one start, with its volume and source beside it.
      _starts.add(
        ScheduledStart(0, 7, 0)..read({
          ...(json['start'] as Map).cast<String, Object?>(),
          'volume': json['volume'],
          'source': json['source'],
        }),
      );
    }
    notifyListeners();
  }

  /// Once the queue is restored, as "Ostatnia kolejka" needs it: plays if that's why the app
  /// started, drops what was missed with the phone off, and tells Android again what a restored
  /// backup set.
  Future<void> start() async {
    if (_started || kIsWeb || !Platform.isAndroid) return;
    _started = true;
    platform.onFired = (key) => unawaited(
      fired(key)
          .catchError((Object e) => debugPrint('Scheduled $key failed: $e')),
    );
    await _startFired();
    await platform.cancelAllBut({for (final time in _times) time.key});
    var changed = false;
    for (final time in _times) {
      final at = time.nextAt;
      if (!time.enabled || at == null) continue;
      if (at.isAfter(DateTime.now())) {
        await platform.schedule(time.key, at, time.days);
      } else {
        await _afterItsTime(time);
        changed = true;
      }
    }
    if (changed) {
      await _save();
      notifyListeners();
    }
  }

  /// [time]'s time has passed: on to its next day, or off.
  Future<void> _afterItsTime(ScheduledTime time) async {
    if (time.days.isNotEmpty) {
      await _arm(time);
    } else {
      time
        ..enabled = false
        ..nextAt = null;
    }
  }

  /// [fired] and any other time that passed meanwhile (two starts at the same minute report one).
  Future<void> _moveOn(ScheduledTime? fired) async {
    final now = DateTime.now();
    for (final time in _times) {
      final at = time.nextAt;
      if (!time.enabled) continue;
      if (time == fired || (at != null && !at.isAfter(now))) {
        await _afterItsTime(time).catchError(
          (Object e) => debugPrint('Scheduling the next time failed: $e'),
        );
      }
    }
    notifyListeners();
    await _save().catchError(
      (Object e) => debugPrint('Saving the scheduled music failed: $e'),
    );
  }

  Future<bool> _arm(ScheduledTime time) async {
    final at = nextScheduledTime(
      DateTime.now(),
      time.hour,
      time.minute,
      time.days,
    );
    final done = await platform.schedule(time.key, at, time.days);
    time
      ..enabled = done
      ..nextAt = done ? at : null;
    return done;
  }

  /// Android says the time with [key] has come.
  @visibleForTesting
  Future<void> fired(String key) async {
    if (key != stopKey) return _startFired();
    await _moveOn(stopTime);
    await stop();
  }

  /// Plays what the start Android reports asks for, if it went off.
  Future<void> _startFired() async {
    final key = await platform.takeStarted();
    if (key == null) return;
    final start = _starts.where((start) => start.key == key).firstOrNull;
    await _moveOn(start);
    if (start != null) await _play(start);
    await platform.finishStarting().catchError((Object e) {
      debugPrint('Finishing the scheduled start failed: $e');
    });
  }

  Future<void> _play(ScheduledStart start) async {
    await platform.setVolume(start.volume).catchError((Object e) {
      debugPrint('Setting the scheduled volume failed: $e');
    });
    try {
      if (!await play(start.source).timeout(startTimeout)) {
        debugPrint('The scheduled music could not be played');
      }
    } on TimeoutException {
      debugPrint('The scheduled music did not start in time');
    } catch (e) {
      debugPrint('Playing the scheduled music failed: $e');
    }
  }

  /// A new start at [hour]:[minute], switched on; [ok] says whether Android accepted it.
  Future<({ScheduledStart start, bool ok})> addStart(
    int hour,
    int minute,
  ) async {
    final id = _starts.fold(-1, (top, start) => max(top, start.id)) + 1;
    final start = ScheduledStart(id, hour, minute);
    _starts.add(start);
    return (start: start, ok: await setTime(start, hour, minute));
  }

  Future<void> removeStart(ScheduledStart start) async {
    _starts.remove(start);
    await platform.cancel(start.key);
    notifyListeners();
    await _save();
  }

  /// Brings back a start just removed ("Cofnij"), switched on again if it was.
  Future<void> restoreStart(ScheduledStart start) async {
    if (_starts.any((other) => other.id == start.id)) return;
    _starts.add(start);
    if (start.enabled) await _arm(start);
    notifyListeners();
    await _save();
  }

  /// Sets the time and switches it on; returns [setEnabled]'s answer.
  Future<bool> setTime(ScheduledTime time, int hour, int minute) {
    time
      ..hour = hour
      ..minute = minute;
    return setEnabled(time, true);
  }

  /// Returns whether it's as asked: Android can refuse.
  Future<bool> setEnabled(ScheduledTime time, bool on) async {
    var done = true;
    if (on) {
      done = await _arm(time);
    } else {
      time.enabled = false;
      time.nextAt = null;
      await platform.cancel(time.key);
    }
    notifyListeners();
    await _save();
    return done;
  }

  /// Which weekdays [time] repeats on; moves a time that's switched on to the first of them.
  Future<void> setDays(ScheduledTime time, Set<int> days) async {
    time.days = days;
    if (time.enabled) await _arm(time);
    notifyListeners();
    await _save();
  }

  Future<void> setVolume(ScheduledStart start, int percent) async {
    start.volume = percent;
    notifyListeners();
    await _save();
  }

  Future<void> setSource(ScheduledStart start, ScheduledSource source) async {
    start.source = source;
    notifyListeners();
    await _save();
  }

  Future<bool> requestNotifications() => platform.requestNotifications();

  Future<bool> canStartApp() => platform.canStartApp();

  Future<bool> openStartAppSettings() => platform.openStartAppSettings();

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'starts': [for (final start in _starts) start.toJson()],
        stopKey: stopTime.toJson(),
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
