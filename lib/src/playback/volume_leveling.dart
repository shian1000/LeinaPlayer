import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/recordings.dart';
import 'player_controller.dart';

/// "Wyrównywanie głośności" (Ustawienia › Odtwarzanie): Android's DynamicsProcessing on both
/// players' audio sessions (`VolumeLeveling.kt`), so every source — a phone file, the server,
/// YouTube — is leveled alike, crossfades included. Android only.
///
/// A recording whose loudness is known ([loudnessOf]) gets a steady gain to
/// [Loudness.targetLufs] instead of the compressor, so it keeps its dynamics.
class VolumeLeveling {
  /// [sessions]: each player's `androidAudioSessionIdStream`.
  VolumeLeveling(List<Stream<int?>> sessions, [this._loudnessOf]) {
    for (final (player, ids) in sessions.indexed) {
      _subs.add(ids.listen((id) => _sessionChanged(player, id)));
    }
  }

  static const _channel = MethodChannel('music_database_app/volume_leveling');

  /// Whether this phone has DynamicsProcessing (Android 9+, and the maker didn't leave it out).
  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('Checking volume leveling support failed: ${e.message}');
      return false;
    }
  }

  final Future<Loudness?> Function(NowPlaying track)? _loudnessOf;
  final _subs = <StreamSubscription<int?>>[];

  /// The loudness of the recording loaded on each player, by its index.
  final _loudness = <int, Loudness>{};

  /// By the player's index.
  final _sessions = <int, int>{};
  double? _strength;

  /// 0–1 ([SourceSettings.activeLeveling]); `null` switches it off.
  set strength(double? value) {
    if (value == _strength) return;
    _strength = value;
    for (final player in _sessions.keys) {
      unawaited(_apply(player));
    }
  }

  /// Called before [track] loads on the player at index [player], so its gain is set before
  /// it's heard. The lookup is the phone's own table; a slow one is given up on.
  Future<void> trackLoading(int player, NowPlaying track) async {
    Loudness? found;
    try {
      found = await _loudnessOf
          ?.call(track)
          .timeout(const Duration(seconds: 1));
    } catch (e) {
      debugPrint('Looking up the loudness failed: $e');
    }
    if (found == null) {
      if (_loudness.remove(player) == null) return;
    } else {
      _loudness[player] = found;
    }
    if (_sessions.containsKey(player)) await _apply(player);
  }

  void _sessionChanged(int player, int? id) {
    final old = _sessions[player];
    if (old == id) return;
    if (old != null) unawaited(_call('release', {'session': old}));
    if (id == null) {
      _sessions.remove(player);
    } else {
      _sessions[player] = id;
      unawaited(_apply(player));
    }
  }

  Future<void> _apply(int player) {
    final id = _sessions[player]!;
    final strength = _strength;
    if (strength == null) return _call('release', {'session': id});
    final gain = _loudness[player]?.gainDb(strength);
    return _call('apply', {
      'session': id,
      'strength': strength,
      'gainDb': ?gain,
    });
  }

  Future<void> _call(String method, Map<String, Object> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Not Android.
    } on PlatformException catch (e) {
      debugPrint('Volume leveling ($method) failed: ${e.message}');
    }
  }

  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    for (final id in _sessions.values) {
      await _call('release', {'session': id});
    }
    _sessions.clear();
  }
}
