import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/combined_search.dart';
import '../data/track_ref.dart';
import 'playback_queue.dart';
import 'player_controller.dart';

/// Remembers the queue and the song in the player across app restarts, like the reference app:
/// after a restart the mini player shows the last song paused where it was, and "Odtwórz"
/// carries on from there with the same playlist, order and added songs. The queue playing
/// something else replaced ([PlaybackQueue.replaced]) is kept too.
class QueueSession {
  QueueSession({
    required this.queue,
    required this.player,
    required this.resolve,
  });

  static const _key = 'playback.session';
  static const _replacedKey = 'playback.replaced_session';

  /// While music plays the position is saved this often, so it's roughly right even when
  /// Android kills the app in the background.
  static const saveEvery = Duration(seconds: 10);

  final PlaybackQueue queue;
  final PlayerController player;

  /// Finds a saved song again (with what the phone knows about it now).
  final SearchHit Function(TrackRef) resolve;

  Timer? _timer;
  bool _started = false;

  /// What [save] last stored under [_replacedKey].
  ReplacedQueue? _savedReplaced;

  /// Puts back the saved session (unless something is already playing), then keeps saving.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && player.current == null && queue.current == null) {
        _restore(jsonDecode(raw) as Map<String, Object?>);
      }
      final replaced = prefs.getString(_replacedKey);
      if (replaced != null && queue.replaced == null) {
        _savedReplaced = ReplacedQueue.fromJson(
          (jsonDecode(replaced) as Map).cast(),
          resolve,
        );
        queue.restoreReplaced(_savedReplaced);
      }
    } catch (e) {
      debugPrint('Restoring the play queue failed: $e');
    }
    _start();
  }

  void _restore(Map<String, Object?> json) {
    queue.restore((json['queue'] as Map).cast(), resolve);
    final durationMs = json['duration_ms'] as int?;
    player.showRestored(
      queue.currentShown!,
      position: Duration(milliseconds: json['position_ms'] as int? ?? 0),
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
      resume: _resume,
    );
  }

  /// "Odtwórz" on the restored song: play it — [PlayerController] starts it where it was.
  Future<void> _resume() => queue.playCurrent();

  void _start() {
    if (_started) return;
    _started = true;
    queue.addListener(save);
    player.addListener(_onPlayer);
  }

  void _onPlayer() {
    if (player.playing) {
      _timer ??= Timer.periodic(saveEvery, (_) => save());
    } else {
      _timer?.cancel();
      _timer = null;
    }
    save();
  }

  /// Also called when the app goes to the background.
  Future<void> save() async {
    if (!_started) return;
    final snapshot = queue.snapshot();
    try {
      final prefs = await SharedPreferences.getInstance();
      final replaced = queue.replaced;
      if (!identical(replaced, _savedReplaced)) {
        _savedReplaced = replaced;
        replaced == null
            ? await prefs.remove(_replacedKey)
            : await prefs.setString(
                _replacedKey,
                jsonEncode(replaced.toJson()),
              );
      }
      if (snapshot == null) {
        await prefs.remove(_key);
        return;
      }
      await prefs.setString(
        _key,
        jsonEncode({
          'queue': snapshot,
          'position_ms': player.currentPosition.inMilliseconds,
          'duration_ms': player.duration?.inMilliseconds,
        }),
      );
    } catch (e) {
      debugPrint('Saving the play queue failed: $e');
    }
  }

  void dispose() {
    _timer?.cancel();
    if (_started) {
      queue.removeListener(save);
      player.removeListener(_onPlayer);
    }
  }
}
