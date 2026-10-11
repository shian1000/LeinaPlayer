import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

/// What's loaded in the player.
class NowPlaying {
  const NowPlaying({
    required this.title,
    required this.artist,
    required this.source,
    required this.coverSeed,
    this.searchQuery,
    this.playlistName,
    this.youtubeVideoId,
  });

  final String title;
  final String artist;

  /// A file path on the phone, or an http(s) address of a stream.
  final String source;

  /// Set when [source] is this YouTube video's audio.
  final String? youtubeVideoId;

  bool get isStream => source.startsWith('http');

  /// Seed for the placeholder cover, so the player shows the same art as the result list.
  final String coverSeed;

  /// The search the song was started from ("Odtwarzanie z wyników wyszukiwania").
  final String? searchQuery;

  /// The playlist the song was started from ("Odtwarzanie z playlisty").
  final String? playlistName;
}

/// A press of "previous"/"next" outside the app: the media notification, the lock screen, a
/// headset or the car.
enum MediaSkip { previous, next }

/// The bits of an audio player the app uses; [JustAudioBackend] in the app, a fake in tests.
abstract class AudioBackend {
  Stream<Duration> get position;
  Stream<Duration?> get duration;

  /// Emits when playback starts/stops and when a track finishes.
  Stream<({bool playing, bool completed})> get state;

  /// "Previous"/"next" pressed outside the app; the queue decides what they do.
  Stream<MediaSkip> get skips;

  /// Loads [track] ([NowPlaying.source]: a file path or an http(s) URL); its title and artist
  /// also go to the media notification.
  Future<void> open(NowPlaying track);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

/// The media session: the notification with previous / play-pause / next, lock-screen and
/// headset controls, and the foreground service that keeps music playing in the background.
/// Created once in `main()` by `AudioService.init`; it owns the app's one [AudioPlayer].
class MediaSession extends BaseAudioHandler with SeekHandler {
  MediaSession() {
    player.playbackEventStream.map(_state).pipe(playbackState);
  }

  final player = AudioPlayer();
  final _skips = StreamController<MediaSkip>.broadcast();

  Stream<MediaSkip> get skips => _skips.stream;

  /// What the notification shows.
  void show(NowPlaying track, Duration? duration) => mediaItem.add(
    MediaItem(
      id: track.youtubeVideoId ?? track.source,
      title: track.title,
      artist: track.artist,
      duration: duration,
    ),
  );

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => _skips.add(MediaSkip.next);

  @override
  Future<void> skipToPrevious() async => _skips.add(MediaSkip.previous);

  PlaybackState _state(PlaybackEvent event) => PlaybackState(
    controls: [
      MediaControl.skipToPrevious,
      player.playing ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
    ],
    systemActions: const {MediaAction.seek},
    androidCompactActionIndices: const [0, 1, 2],
    processingState: const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[player.processingState]!,
    playing: player.playing,
    updatePosition: player.position,
    bufferedPosition: player.bufferedPosition,
    speed: player.speed,
  );
}

class JustAudioBackend implements AudioBackend {
  /// Without a [session] (it failed to start) music still plays, just with no notification.
  JustAudioBackend([this._session]) {
    final session = _session;
    if (session != null) {
      _durationSub = _player.durationStream.listen((d) {
        final track = _track;
        if (track != null) session.show(track, d);
      });
    }
  }

  final MediaSession? _session;
  late final AudioPlayer _player = _session?.player ?? AudioPlayer();
  StreamSubscription<Duration?>? _durationSub;
  NowPlaying? _track;

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
  Stream<MediaSkip> get skips => _session?.skips ?? const Stream.empty();

  @override
  Future<void> open(NowPlaying track) async {
    _track = track;
    _session?.show(track, null);
    await _player.setAudioSource(
      track.isStream
          ? AudioSource.uri(Uri.parse(track.source))
          : AudioSource.file(track.source),
    );
  }

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
  Future<void> dispose() async {
    await _durationSub?.cancel();
    await _player.dispose();
  }
}

/// Plays one song at a time (phone file or stream) and tells the mini player / "Teraz odtwarzane"
/// screen what's on; [PlaybackQueue] decides what comes next.
/// The audio backend is created on the first [play], so merely opening the app never touches the
/// audio plugin.
class PlayerController extends ChangeNotifier {
  PlayerController({AudioBackend Function()? backend})
    : _createBackend = backend ?? JustAudioBackend.new;

  final AudioBackend Function() _createBackend;
  AudioBackend? _backend;
  StreamSubscription<({bool playing, bool completed})>? _stateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<MediaSkip>? _skipSub;
  final _completions = StreamController<void>.broadcast();
  final _skips = StreamController<MediaSkip>.broadcast();
  bool _completed = false;
  Duration _position = Duration.zero;

  NowPlaying? _current;
  bool _playing = false;
  Future<void> Function()? _resume;
  Duration? _duration;
  String? _lastError;

  NowPlaying? get current => _current;
  bool get playing => _playing;
  Duration? get duration => _duration;

  /// Showing the song from last time ([showRestored]), not loaded yet.
  bool get restored => _resume != null;

  /// Why the last [play] failed (Polish, for display), or `null`.
  String? get lastError => _lastError;

  /// Current position; until something has been loaded, just [currentPosition] (a new stream
  /// each time, so a seek while [restored] shows).
  Stream<Duration> get position => _resume == null && _backend != null
      ? _backend!.position
      : Stream.value(_position);

  /// The last known position of the current song.
  Duration get currentPosition => _position;

  /// Fires once each time a song plays to its end; the listener (the queue) moves on, or calls
  /// [stopAtEnd] when nothing follows.
  Stream<void> get completions => _completions.stream;

  /// "Previous"/"next" pressed in the media notification, on the lock screen or a headset.
  Stream<MediaSkip> get skips => _skips.stream;

  AudioBackend _ensureBackend() {
    final existing = _backend;
    if (existing != null) return existing;
    final backend = _backend = _createBackend();
    _stateSub = backend.state.listen((s) {
      if (s.completed && !_completed) {
        _completed = true;
        // The queue starts the next song or calls [stopAtEnd]. Not pausing here matters: a
        // pause tells the media session playback stopped, which takes the app out of the
        // foreground and lets go of the wake lock — with the screen off the phone then froze
        // the app while it fetched the next song from YouTube, and the music stopped.
        if (_completions.hasListener) {
          _completions.add(null);
        } else {
          stopAtEnd();
        }
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
    _positionSub = backend.position.listen((p) => _position = p);
    _skipSub = backend.skips.listen(_skips.add);
    return backend;
  }

  /// Shows [track] — the song the app was on last time — paused at [position], without loading
  /// anything (a YouTube stream would need the network just to start the app). The first play
  /// calls [resume], which really plays it, from [currentPosition].
  void showRestored(
    NowPlaying track, {
    required Duration position,
    Duration? duration,
    required Future<void> Function() resume,
  }) {
    _current = track;
    _position = position;
    _duration = duration;
    _playing = false;
    _resume = resume;
    notifyListeners();
  }

  /// Nothing follows the song that just ended: stop at its start, ready to play again.
  Future<void> stopAtEnd() async {
    final backend = _backend;
    if (backend == null || !_completed) return;
    await backend.pause();
    await backend.seek(Duration.zero);
  }

  /// Pauses whatever is loaded and shows [track] instead, not loaded; play calls [resume] (the
  /// queue stopping on a song it couldn't reach for want of a connection).
  Future<void> park(NowPlaying track, Future<void> Function() resume) async {
    await _backend?.pause();
    showRestored(track, position: Duration.zero, resume: resume);
  }

  /// Loads and starts [track]; returns whether it could be opened.
  Future<bool> play(NowPlaying track) async {
    _resume = null;
    final backend = _ensureBackend();
    _current = track;
    _duration = null;
    _lastError = null;
    _completed = false;
    _position = Duration.zero;
    notifyListeners();
    try {
      await backend.open(track);
      await backend.play();
      return true;
    } catch (e) {
      debugPrint('Playing ${track.source} failed: $e');
      _lastError = track.isStream
          ? 'Nie udało się odtworzyć utworu „${track.title}” z YouTube'
          : 'Nie udało się odtworzyć pliku ${track.source.split('/').last}';
      _current = null;
      _playing = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> togglePlay() async {
    final resume = _resume;
    if (resume != null) {
      _resume = null;
      return resume();
    }
    final backend = _backend;
    if (backend == null || _current == null) return;
    _playing ? await backend.pause() : await backend.play();
  }

  Future<void> seek(Duration position) async {
    _position = position;
    if (_resume != null) {
      notifyListeners();
      return;
    }
    await _backend?.seek(position);
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    _skipSub?.cancel();
    _completions.close();
    _skips.close();
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
