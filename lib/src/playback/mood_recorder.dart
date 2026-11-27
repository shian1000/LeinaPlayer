import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/combined_search.dart';
import 'listening_tracker.dart';
import 'playback_queue.dart';

/// Kolejka's "Nagraj nastrój": while it's on, every song heard for [heardEnough] (or almost
/// whole, when shorter) goes into one mood of the user's own, made when the recording starts
/// and kept in Biblioteka like any other. On across restarts, until switched off or the mood
/// is gone.
class MoodRecorder extends ChangeNotifier {
  MoodRecorder({
    required Stream<QueuePlay> played,
    required Stream<Duration> positions,
    required this.playing,
    required this.duration,
    required this.createMood,
    required this.addSong,
  }) {
    _playedSub = played.listen(_started);
    _positionSub = positions.listen(_moved);
  }

  static const heardEnough = Duration(minutes: 1);
  static const _uidKey = 'mood_recorder.uid';

  final bool Function() playing;
  final Duration? Function() duration;

  /// Makes a mood named [name] (or like it, if the name is taken); returns its `moods.uid`.
  final Future<String> Function(String name) createMood;

  /// Puts [hit] into the mood [uid]; `false` when there is no such mood any more.
  final Future<bool> Function(String uid, SearchHit hit) addSong;

  late final StreamSubscription<QueuePlay> _playedSub;
  late final StreamSubscription<Duration> _positionSub;

  String? _uid;

  /// The `moods.uid` of the mood being recorded, `null` while not recording.
  String? get moodUid => _uid;
  bool get recording => _uid != null;

  SearchHit? _hit;
  Duration _heard = Duration.zero;
  Duration? _last;
  bool _added = false;

  Future<void> load() async {
    _uid = (await SharedPreferences.getInstance()).getString(_uidKey);
    notifyListeners();
  }

  /// Starts recording into a new mood named [name]. The song playing counts from where it is.
  Future<void> start(String name) async {
    if (recording) return;
    final uid = await createMood(name);
    _uid = uid;
    _added = false;
    _heard = _hit == null ? Duration.zero : _last ?? Duration.zero;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_uidKey, uid);
    await _addIfHeard();
  }

  Future<void> stop() async {
    if (!recording) return;
    _uid = null;
    notifyListeners();
    await (await SharedPreferences.getInstance()).remove(_uidKey);
  }

  void _started(QueuePlay play) {
    _last = null;
    _heard = Duration.zero;
    _added = false;
    // In the YouTube app nothing tells how long it was heard.
    _hit = play.external ? null : play.hit;
  }

  void _moved(Duration position) {
    final last = _last;
    _last = position;
    if (last == null || !playing() || _hit == null) return;
    final step = position - last;
    if (step <= Duration.zero || step > ListeningTracker.maxStep) return;
    _heard += step;
    _addIfHeard();
  }

  Future<void> _addIfHeard() async {
    final uid = _uid;
    final hit = _hit;
    if (uid == null || hit == null || _added) return;
    final length = duration();
    final enough = length != null && length < heardEnough
        ? length * 0.9
        : heardEnough;
    if (_heard < enough) return;
    _added = true;
    try {
      if (!await addSong(uid, hit) && _uid == uid) await stop();
    } catch (e) {
      debugPrint('Adding a song to the recorded mood failed: $e');
    }
  }

  @override
  void dispose() {
    _playedSub.cancel();
    _positionSub.cancel();
    super.dispose();
  }
}

class MoodRecorderScope extends InheritedNotifier<MoodRecorder> {
  const MoodRecorderScope({
    super.key,
    required MoodRecorder super.notifier,
    required super.child,
  });

  static MoodRecorder? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MoodRecorderScope>()?.notifier;
}
