import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

/// What's loaded in the player.
class NowPlaying {
  const NowPlaying({
    required this.title,
    required this.artist,
    required this.filePath,
    required this.coverSeed,
    this.searchQuery,
  });

  final String title;
  final String artist;
  final String filePath;

  /// Seed for the placeholder cover, so the player shows the same art as the result list.
  final String coverSeed;

  /// The search the song was started from ("Odtwarzanie z wyników wyszukiwania").
  final String? searchQuery;
}

/// The bits of an audio player the app uses; [JustAudioBackend] in the app, a fake in tests.
abstract class AudioBackend {
  Stream<Duration> get position;
  Stream<Duration?> get duration;

  /// Emits when playback starts/stops and when a track finishes.
  Stream<({bool playing, bool completed})> get state;

  Future<void> open(String filePath);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

class JustAudioBackend implements AudioBackend {
  final _player = AudioPlayer();

  @override
  Stream<Duration> get position => _player.positionStream;

  @override
  Stream<Duration?> get duration => _player.durationStream;

  @override
  Stream<({bool playing, bool completed})> get state =>
      _player.playerStateStream.map(
        (s) => (
          playing: s.playing,
          completed: s.processingState == ProcessingState.completed,
        ),
      );

  @override
  Future<void> open(String filePath) => _player.setFilePath(filePath);

  @override
  Future<void> play() async {
    // just_audio's play() completes only when playback stops, so don't wait for it.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() => _player.dispose();
}

/// Plays songs from the phone and tells the mini player / "Teraz odtwarzane" screen what's on.
/// The audio backend is created on the first [play], so merely opening the app never touches the
/// audio plugin.
class PlayerController extends ChangeNotifier {
  PlayerController({AudioBackend Function()? backend})
    : _createBackend = backend ?? JustAudioBackend.new;

  final AudioBackend Function() _createBackend;
  AudioBackend? _backend;
  StreamSubscription<({bool playing, bool completed})>? _stateSub;
  StreamSubscription<Duration?>? _durationSub;

  NowPlaying? _current;
  bool _playing = false;
  Duration? _duration;
  String? _lastError;

  NowPlaying? get current => _current;
  bool get playing => _playing;
  Duration? get duration => _duration;

  /// Why the last [play] failed (Polish, for display), or `null`.
  String? get lastError => _lastError;

  /// Current position; empty until something has been played.
  Stream<Duration> get position => _backend?.position ?? const Stream.empty();

  AudioBackend _ensureBackend() {
    final existing = _backend;
    if (existing != null) return existing;
    final backend = _backend = _createBackend();
    _stateSub = backend.state.listen((s) {
      if (s.completed) {
        // Finished: stop at the start, ready to play again (there's no queue yet).
        backend.pause();
        backend.seek(Duration.zero);
      }
      final playing = s.playing && !s.completed;
      if (playing != _playing) {
        _playing = playing;
        notifyListeners();
      }
    });
    _durationSub = backend.duration.listen((d) {
      _duration = d;
      notifyListeners();
    });
    return backend;
  }

  /// Loads and starts [track]; returns whether it could be opened.
  Future<bool> play(NowPlaying track) async {
    final backend = _ensureBackend();
    _current = track;
    _duration = null;
    _lastError = null;
    notifyListeners();
    try {
      await backend.open(track.filePath);
      await backend.play();
      return true;
    } catch (e) {
      debugPrint('Playing ${track.filePath} failed: $e');
      _lastError =
          'Nie udało się odtworzyć pliku ${track.filePath.split('/').last}';
      _current = null;
      _playing = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> togglePlay() async {
    final backend = _backend;
    if (backend == null || _current == null) return;
    _playing ? await backend.pause() : await backend.play();
  }

  Future<void> seek(Duration position) async => _backend?.seek(position);

  @override
  void dispose() {
    _stateSub?.cancel();
    _durationSub?.cancel();
    _backend?.dispose();
    super.dispose();
  }
}

/// Makes the [PlayerController] reachable from any screen.
class PlayerScope extends InheritedNotifier<PlayerController> {
  const PlayerScope({
    super.key,
    required PlayerController super.notifier,
    required super.child,
  });

  static PlayerController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerScope>()!.notifier!;
}
