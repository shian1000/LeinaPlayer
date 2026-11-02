import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/recordings.dart';

/// A recording the phone has whole, which may be measured.
typedef MeasurableFile = ({RecordingKey key, String path});

/// The measurement of one file: its loudness (`null` for silence) and length.
typedef Measurement = ({Loudness? loudness, Duration duration});

/// Measures the loudness of every recording the phone has whole ([candidates]: the YouTube
/// cache — newest first, so the queue's next songs are ready before they play —, downloads,
/// phone files) one at a time in the background, for "Wyrównywanie głośności". Only while
/// that is on: it costs the phone a few seconds of decoding per song, once.
class LoudnessMeasurer {
  LoudnessMeasurer(
    this._recordings,
    this._candidates, {
    Future<Measurement> Function(String path)? measure,
    this.delay = const Duration(seconds: 2),
  }) : _measure = measure ?? _measureNatively;

  final Recordings _recordings;
  final Future<List<MeasurableFile>> Function() _candidates;
  final Future<Measurement> Function(String path) _measure;

  /// How long [schedule] waits for more changes.
  final Duration delay;

  static const _channel = MethodChannel('music_database_app/volume_leveling');

  static Future<Measurement> _measureNatively(String path) async {
    final r = (await _channel.invokeMapMethod<String, Object?>('measure', {
      'path': path,
    }))!;
    final lufs = (r['lufs'] as num?)?.toDouble();
    return (
      loudness: lufs == null
          ? null
          : Loudness(lufs: lufs, peakDb: (r['peakDb'] as num?)?.toDouble()),
      duration: Duration(milliseconds: (r['durationMs']! as num).toInt()),
    );
  }

  bool _enabled = false;
  bool _disposed = false;
  Timer? _timer;
  Future<void>? _running;
  bool _again = false;

  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (value) schedule();
  }

  /// Something new may be there to measure (a file cached, downloaded or scanned); looked at
  /// after [delay], so a burst of changes is one look.
  void schedule() {
    if (!_enabled || _disposed) return;
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (_running != null) {
        _again = true;
        return;
      }
      _running = _run().whenComplete(() {
        _running = null;
        if (_again) {
          _again = false;
          schedule();
        }
      });
    });
  }

  /// Waits for the measuring under way, for tests.
  @visibleForTesting
  Future<void> get idle async {
    while (_timer?.isActive == true || _running != null) {
      await (_running ?? Future<void>.delayed(delay));
    }
  }

  Future<void> _run() async {
    try {
      final settled = await _recordings.settled();
      for (final file in await _candidates()) {
        if (!_enabled || _disposed) return;
        if (settled.contains(file.key)) continue;
        await _measureOne(file);
      }
    } catch (e) {
      debugPrint('Measuring loudness failed: $e');
    }
  }

  Future<void> _measureOne(MeasurableFile file) async {
    try {
      final m = await _measure(file.path);
      await _recordings.saveLoudness(
        file.key,
        m.loudness,
        LoudnessMethod.analysis,
        duration: m.duration,
      );
    } on MissingPluginException {
      _enabled = false;
    } catch (e) {
      // By the file's name only: a path names the user's folders.
      debugPrint(
        'Measuring the loudness of ${file.path.split('/').last} failed: $e',
      );
      await _recordings.saveLoudness(file.key, null, LoudnessMethod.failed);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
