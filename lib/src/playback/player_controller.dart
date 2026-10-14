import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../data/album_covers.dart';
import '../data/latin_names.dart';

/// What's loaded in the player.
class NowPlaying {
  const NowPlaying({
    required this.title,
    required this.artist,
    required this.source,
    required this.coverSeed,
    CoverRequest? cover,
    this.searchQuery,
    this.playlistName,
    this.youtubeVideoId,
    this.titleLatin,
    this.artistLatin,
  }) : _givenCover = cover;

  final String title;
  final String artist;

  /// Latin forms of [title] and [artist] from music.db ([SearchHit.titleLatin]).
  final String? titleLatin;
  final String? artistLatin;

  /// A file path on the phone, or an http(s) address of a stream.
  final String source;

  /// Set when [source] is this YouTube video's audio.
  final String? youtubeVideoId;

  bool get isStream => source.startsWith('http');

  /// Seed for the placeholder cover, so the player shows the same art as the result list.
  final String coverSeed;

  final CoverRequest? _givenCover;

  /// The song's album cover; without one, just the placeholder.
  CoverRequest get cover =>
      _givenCover ??
      CoverRequest(
        artist: artist,
        title: title,
        seed: coverSeed,
        searchable: false,
      );

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

  /// Starts [track] while the song playing now goes on, fading it out over [fade] as [track]
  /// fades in ("Przenikanie utworów"); from then on [position], [duration], [state] and the
  /// controls are [track]'s.
  Future<void> crossfadeTo(NowPlaying track, Duration fade);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

/// The media session: the notification with previous / play-pause / next, lock-screen and
/// headset controls, and the foreground service that keeps music playing in the background.
/// Created once in `main()` by `AudioService.init`; it owns the app's two [AudioPlayer]s — two
/// so songs can overlap while crossfading — and shows the [active] one.
class MediaSession extends BaseAudioHandler with SeekHandler {
  MediaSession() {
    for (final p in [players.$1, players.$2]) {
      p.playbackEventStream.listen((_) {
        if (identical(p, _active)) playbackState.add(_state());
      }, onError: (Object _) {});
    }
  }

  /// Ustawienia › Wygląd › "Nazwy w alfabecie łacińskim", for the notification.
  bool latinNames = true;

  final players = (AudioPlayer(), AudioPlayer());
  late AudioPlayer _active = players.$1;
  final _skips = StreamController<MediaSkip>.broadcast();

  /// Called before a pause from the notification, so a song fading out doesn't go on alone.
  VoidCallback? beforePause;

  AudioPlayer get active => _active;
  set active(AudioPlayer player) {
    _active = player;
    playbackState.add(_state());
  }

  Stream<MediaSkip> get skips => _skips.stream;

  /// What the notification shows.
  void show(NowPlaying track, Duration? duration, Uri? art) => mediaItem.add(
    MediaItem(
      id: track.youtubeVideoId ?? track.source,
      title: latinNames
          ? withLatin(track.title, track.titleLatin)
          : track.title,
      artist: latinNames
          ? withLatin(track.artist, track.artistLatin)
          : track.artist,
      duration: duration,
      artUri: art,
    ),
  );

  @override
  Future<void> play() => _active.play();

  @override
  Future<void> pause() {
    beforePause?.call();
    return _active.pause();
  }

  @override
  Future<void> seek(Duration position) => _active.seek(position);

  @override
  Future<void> stop() async {
    beforePause?.call();
    await _active.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => _skips.add(MediaSkip.next);

  @override
  Future<void> skipToPrevious() async => _skips.add(MediaSkip.previous);

  PlaybackState _state() {
    final player = _active;
    return PlaybackState(
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
}

class JustAudioBackend implements AudioBackend {
  /// Without a [session] (it failed to start) music still plays, just with no notification.
  /// [artFor] finds the cover file the notification shows; it's found again when [artChanged]
  /// notifies (e.g. another cover filter).
  JustAudioBackend([this._session, this._artFor, this._artChanged]) {
    _artChanged?.addListener(_refreshArt);
    _session?.beforePause = _endFade;
    for (final p in [_players.$1, _players.$2]) {
      _subs.addAll([
        p.positionStream.listen((v) {
          if (identical(p, _player)) _positions.add(v);
        }),
        p.durationStream.listen((v) {
          if (identical(p, _player)) _durationChanged(v);
        }),
        p.playerStateStream.listen((v) {
          if (identical(p, _player)) _states.add(_stateOf(v));
        }, onError: (Object _) {}),
      ]);
    }
  }

  final MediaSession? _session;
  final Future<Uri?> Function(NowPlaying track)? _artFor;
  final Listenable? _artChanged;

  void _refreshArt() {
    final track = _track;
    if (track != null) unawaited(_showArt(track));
  }

  Duration? _duration;
  Uri? _art;
  late final (AudioPlayer, AudioPlayer) _players =
      _session?.players ?? (AudioPlayer(), AudioPlayer());

  /// The player of the song playing now; while crossfading, the other one fades out the song
  /// before.
  late AudioPlayer _player = _session?.active ?? _players.$1;
  AudioPlayer get _other =>
      identical(_player, _players.$1) ? _players.$2 : _players.$1;
  Timer? _fade;
  AudioPlayer? _fadingOut;

  final _subs = <StreamSubscription<Object?>>[];
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  final _states =
      StreamController<({bool playing, bool completed})>.broadcast();
  NowPlaying? _track;

  static ({bool playing, bool completed}) _stateOf(PlayerState s) => (
    playing: s.playing,
    completed: s.processingState == ProcessingState.completed,
  );

  /// [changes], starting with the value now, as just_audio's own streams do.
  static Stream<T> _following<T>(Stream<T> changes, T Function() now) async* {
    yield now();
    yield* changes;
  }

  void _durationChanged(Duration? d) {
    _duration = d;
    _durations.add(d);
    final track = _track;
    if (track != null) _session?.show(track, d, _art);
  }

  @override
  Stream<Duration> get position =>
      _following(_positions.stream, () => _player.position);

  @override
  Stream<Duration?> get duration =>
      _following(_durations.stream, () => _player.duration);

  @override
  Stream<({bool playing, bool completed})> get state =>
      _following(_states.stream, () => _stateOf(_player.playerState));

  @override
  Stream<MediaSkip> get skips => _session?.skips ?? const Stream.empty();

  AudioSource _sourceOf(NowPlaying track) => track.isStream
      ? AudioSource.uri(Uri.parse(track.source))
      : AudioSource.file(track.source);

  void _showTrack(NowPlaying track) {
    _track = track;
    _art = null;
    _duration = null;
    _session?.show(track, null, null);
    unawaited(_showArt(track));
  }

  @override
  Future<void> open(NowPlaying track) async {
    _endFade();
    _showTrack(track);
    await _player.setVolume(1);
    await _player.setAudioSource(_sourceOf(track));
  }

  @override
  Future<void> crossfadeTo(NowPlaying track, Duration fade) async {
    _endFade();
    final outgoing = _player;
    final incoming = _other;
    await incoming.setVolume(0);
    try {
      await incoming.setAudioSource(_sourceOf(track));
    } catch (_) {
      unawaited(incoming.stop());
      rethrow;
    }
    // Started before it takes over, so the media session never sees a moment without music
    // (see PlayerController's completion handling).
    unawaited(incoming.play());
    _player = incoming;
    _session?.active = incoming;
    _showTrack(track);
    _durationChanged(incoming.duration);
    _states.add(_stateOf(incoming.playerState));
    _positions.add(incoming.position);

    _fadingOut = outgoing;
    final steps = max(1, fade.inMilliseconds ~/ _fadeStep.inMilliseconds);
    var step = 0;
    _fade = Timer.periodic(_fadeStep, (timer) {
      step++;
      if (step >= steps) {
        _endFade();
        return;
      }
      // Equal-power curves: the sum sounds as loud as one song all the way through.
      final t = step / steps;
      unawaited(incoming.setVolume(sin(t * pi / 2)));
      unawaited(outgoing.setVolume(cos(t * pi / 2)));
    });
  }

  static const _fadeStep = Duration(milliseconds: 50);

  /// Finishes a crossfade at once: the song before stops, the new one plays at full volume.
  void _endFade() {
    _fade?.cancel();
    _fade = null;
    final outgoing = _fadingOut;
    if (outgoing == null) return;
    _fadingOut = null;
    unawaited(outgoing.stop());
    unawaited(_player.setVolume(1));
  }

  /// The cover can take a while (a download), so the notification first shows the song without
  /// it.
  Future<void> _showArt(NowPlaying track) async {
    final session = _session;
    final artFor = _artFor;
    if (session == null || artFor == null) return;
    try {
      final art = await artFor(track);
      if (art == null || !identical(track, _track)) return;
      _art = art;
      session.show(track, _duration, art);
    } catch (e) {
      debugPrint('Cover for the notification failed: $e');
    }
  }

  @override
  Future<void> play() async {
    // just_audio's play() completes only when playback stops, so don't wait for it.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() {
    _endFade();
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() async {
    _endFade();
    _artChanged?.removeListener(_refreshArt);
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _players.$1.dispose();
    await _players.$2.dispose();
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

  /// "Przenikanie utworów": how long a song's end overlaps the next one's start; zero = off.
  Duration crossfade = Duration.zero;

  /// Asked once per song, [crossfade] before its end, whether something follows; the queue
  /// starts moving on there and then (returning true), and the [play] it ends with fades the
  /// two songs into each other. Only songs moving on by themselves fade, as in the reference
  /// app: "Następny" or a tapped song switch at once.
  bool Function()? onNearEnd;
  bool _nearEndAsked = false;

  /// The queue is moving on to the next song before this one ended ([onNearEnd]).
  bool _fadePending = false;
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
        // The queue moves on already; the next song just won't fade in.
        if (_fadePending) return;
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
    _positionSub = backend.position.listen((p) {
      _position = p;
      _checkNearEnd();
    });
    _skipSub = backend.skips.listen(_skips.add);
    return backend;
  }

  /// How long the fade into the next song lasts at the end of a song this long: at most half of
  /// it, so a short song still plays mostly on its own.
  Duration _fadeFor(Duration duration) =>
      crossfade < duration ~/ 2 ? crossfade : duration ~/ 2;

  void _checkNearEnd() {
    final duration = _duration;
    if (crossfade <= Duration.zero ||
        duration == null ||
        duration <= Duration.zero ||
        _nearEndAsked ||
        !_playing ||
        _resume != null ||
        duration - _position > _fadeFor(duration)) {
      return;
    }
    _nearEndAsked = true;
    // Set first: the queue may call [play] before [onNearEnd] returns.
    _fadePending = true;
    if (!(onNearEnd?.call() ?? false)) _fadePending = false;
  }

  /// The next song will start at once rather than fade in: the user picked it.
  void cancelFade() => _fadePending = false;

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
    // Moving on early found nothing to play: this song finishes, then the queue is asked again.
    _fadePending = false;
    final backend = _backend;
    if (backend == null || !_completed) return;
    await backend.pause();
    await backend.seek(Duration.zero);
  }

  /// Pauses whatever is loaded and shows [track] instead, not loaded; play calls [resume] (the
  /// queue stopping on a song it couldn't reach for want of a connection).
  Future<void> park(NowPlaying track, Future<void> Function() resume) async {
    _fadePending = false;
    await _backend?.pause();
    showRestored(track, position: Duration.zero, resume: resume);
  }

  /// Loads and starts [track]; returns whether it could be opened. Called by the queue
  /// moving on before the song ended ([onNearEnd]), it fades the two songs into each other
  /// over what's left of the song (still playing if the new one fails).
  Future<bool> play(NowPlaying track) async {
    _resume = null;
    final backend = _ensureBackend();
    final duration = _duration;
    final left = duration == null ? Duration.zero : duration - _position;
    final fade = _fadePending && !_completed && left > Duration.zero;
    final before = (current: _current, duration: _duration);
    _current = track;
    _duration = null;
    _lastError = null;
    notifyListeners();
    try {
      if (fade) {
        await backend.crossfadeTo(track, left);
      } else {
        await backend.open(track);
        await backend.play();
      }
      _fadePending = false;
      _nearEndAsked = false;
      _completed = false;
      _position = Duration.zero;
      return true;
    } catch (e) {
      debugPrint('Playing ${track.source} failed: $e');
      _lastError = track.isStream
          ? 'Nie udało się odtworzyć utworu „${track.title}” z YouTube'
          : 'Nie udało się odtworzyć pliku ${track.source.split('/').last}';
      if (fade) {
        // The song before plays on to its end.
        _current = before.current;
        _duration = before.duration;
      } else {
        _fadePending = false;
        _nearEndAsked = false;
        _completed = false;
        _position = Duration.zero;
        _current = null;
        _playing = false;
      }
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
    if (!_fadePending) _nearEndAsked = false;
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
