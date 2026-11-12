import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/cover_credit.dart';
import '../data/track_ref.dart';
import '../data/version_names.dart';
import 'playback_queue.dart';
import 'player_controller.dart';

/// Remembers the queue and the song in the player across app restarts, like the reference app:
/// after a restart the mini player shows the last song paused where it was, and "Odtwórz"
/// carries on from there with the same playlist, order and added songs. The queue playing
/// something else replaced ([PlaybackQueue.replaced]) is kept too.
///
/// The song shows at once ([showSaved]), from what the player showed when it was saved; the
/// queue comes back later ([restore]), once the songs it refers to can be found — music.db
/// takes seconds to load on a slow phone.
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

  Future<void>? _showing;

  /// The song [showSaved] put in the player, until [restore].
  NowPlaying? _shownEarly;

  final _restored = Completer<void>();

  /// Shows the saved song in the player, paused, before its queue can be put back: "Odtwórz"
  /// tapped now plays it once [restore] has. A session saved before the player's view was kept
  /// waits for [restore].
  Future<void> showSaved() => _showing ??= _showSaved();

  Future<void> _showSaved() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null || player.current != null || queue.current != null) {
        return;
      }
      final json = jsonDecode(raw) as Map<String, Object?>;
      final shown = json['shown'];
      if (shown is! Map) return;
      final track = _shownEarly = _nowPlayingFromJson(shown.cast());
      final durationMs = json['duration_ms'] as int?;
      player.showRestored(
        track,
        position: Duration(milliseconds: json['position_ms'] as int? ?? 0),
        duration: durationMs == null
            ? null
            : Duration(milliseconds: durationMs),
        resume: () async {
          await _restored.future;
          await _resume();
        },
      );
    } catch (e) {
      debugPrint('Showing the saved song failed: $e');
    }
  }

  /// Puts back the saved session (unless something else is playing by now), then keeps saving.
  Future<void> restore() async {
    await _showing;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final early = _shownEarly;
      final shownEarly = early != null && identical(player.current, early);
      if (raw != null &&
          queue.current == null &&
          (player.current == null || shownEarly)) {
        _restore(jsonDecode(raw) as Map<String, Object?>, shownEarly);
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
    _shownEarly = null;
    if (!_restored.isCompleted) _restored.complete();
    _start();
  }

  void _restore(Map<String, Object?> json, bool shownEarly) {
    queue.restore((json['queue'] as Map).cast(), resolve);
    // "Odtwórz" was tapped on the song shown early: its play goes on now, nothing to show.
    if (shownEarly && !player.restored) return;
    final durationMs = json['duration_ms'] as int?;
    player.showRestored(
      queue.currentShown!,
      // Where the song shown early was moved to meanwhile.
      position: shownEarly
          ? player.currentPosition
          : Duration(milliseconds: json['position_ms'] as int? ?? 0),
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
          if (queue.currentShown case final shown?)
            'shown': _nowPlayingToJson(shown),
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

/// What the player shows of [track], for [QueueSession.showSaved].
Map<String, Object?> _nowPlayingToJson(NowPlaying track) {
  final cover = track.cover;
  return {
    'title': track.title,
    'artist': track.artist,
    'title_latin': ?track.titleLatin,
    'artist_latin': ?track.artistLatin,
    if (track.coverOf case final covered?)
      'cover_of': {'name': covered.name, 'latin': ?covered.latin},
    if (track.version case final version?)
      'version': {
        'kind': version.kind.name,
        'label': ?version.label,
        'original_id': ?version.originalId,
      },
    'source': track.source,
    'youtube_video_id': ?track.youtubeVideoId,
    'cover_seed': track.coverSeed,
    'cover': {
      'artist': cover.artist,
      'title': cover.title,
      'album': ?cover.album,
      'video_id': ?cover.videoId,
      'file_path': ?cover.filePath,
      'server_file_id': ?cover.serverFileId,
      'seed': cover.seed,
      'searchable': cover.searchable,
    },
    'playlist_name': ?track.playlistName,
    'search_query': ?track.searchQuery,
  };
}

NowPlaying _nowPlayingFromJson(Map<String, Object?> json) {
  final coverOf = (json['cover_of'] as Map?)?.cast<String, Object?>();
  final version = (json['version'] as Map?)?.cast<String, Object?>();
  final cover = (json['cover']! as Map).cast<String, Object?>();
  return NowPlaying(
    title: json['title']! as String,
    artist: json['artist']! as String,
    titleLatin: json['title_latin'] as String?,
    artistLatin: json['artist_latin'] as String?,
    coverOf: coverOf == null
        ? null
        : CoverOf(coverOf['name']! as String, coverOf['latin'] as String?),
    version: version == null
        ? null
        : SongVersion(
            VersionKind.of(version['kind']! as String),
            label: version['label'] as String?,
            originalId: version['original_id'] as int?,
          ),
    source: json['source']! as String,
    youtubeVideoId: json['youtube_video_id'] as String?,
    coverSeed: json['cover_seed']! as String,
    // No video search: it needs the song from music.db, which the queue brings back later.
    cover: CoverRequest(
      artist: cover['artist']! as String,
      title: cover['title']! as String,
      album: cover['album'] as String?,
      videoId: cover['video_id'] as String?,
      filePath: cover['file_path'] as String?,
      serverFileId: cover['server_file_id'] as int?,
      seed: cover['seed']! as String,
      searchable: cover['searchable']! as bool,
    ),
    playlistName: json['playlist_name'] as String?,
    searchQuery: json['search_query'] as String?,
  );
}
