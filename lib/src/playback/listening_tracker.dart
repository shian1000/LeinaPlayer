import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/listening_log.dart';
import '../data/moods.dart';
import 'playback_queue.dart';
import 'player_controller.dart';

/// Feeds the [ListeningLog]: a new play for each song the queue starts, and the time it is
/// heard, taken from the player's position moving on while it plays.
class ListeningTracker {
  ListeningTracker({
    required Stream<QueuePlay> played,
    required PlayerController player,
    required this.log,
    this.playlistUid,
    this.mood,
  }) : _player = player {
    _playedSub = played.listen(_started);
    _positionSub = player.positionChanges.listen(_moved);
  }

  /// A larger jump between two positions is a seek, not listening (positions come several
  /// times a second while playing).
  static const maxStep = Duration(seconds: 3);

  final PlayerController _player;
  final ListeningLog log;

  /// The synced id (`playlists.uid`) of a Biblioteka playlist.
  final String? Function(int playlistId)? playlistUid;

  /// The mood with this [Mood.key].
  final Mood? Function(String key)? mood;
  late final StreamSubscription<QueuePlay> _playedSub;
  late final StreamSubscription<Duration> _positionSub;
  Duration? _last;

  void _started(QueuePlay play) {
    _last = null;
    // In the YouTube app nothing tells how long it was heard.
    if (play.external) {
      log.finish().catchError(_failed);
      return;
    }
    final hit = play.hit;
    final now = _player.current;
    final playlistId = play.playlistId;
    final moodKey = play.moodKey;
    final mood = moodKey == null ? null : this.mood?.call(moodKey);
    log
        .start(
          title: hit.title,
          artist: hit.artistLabel,
          album: hit.album,
          songId: hit.mainSong?.id,
          youtubeVideoId: hit.youtubeVideoId,
          spotifyTrackId: hit.spotifyTrackId,
          source: now?.serverFileId != null
              ? ListenSource.server
              : now?.youtubeVideoId != null
              ? ListenSource.youtube
              : ListenSource.phone,
          playlistUid: playlistId == null
              ? null
              : playlistUid?.call(playlistId),
          playlistName: play.playlistName,
          moodUid: mood?.global == false ? mood?.uid : null,
          globalMoodId: mood?.global == true ? mood?.globalId : null,
          moodName: mood?.name,
          duration: _player.duration,
        )
        .catchError((Object e) {
          _failed(e);
          return '';
        });
  }

  void _moved(Duration position) {
    final last = _last;
    _last = position;
    if (last == null || !_player.playing) return;
    final step = position - last;
    if (step <= Duration.zero || step > maxStep) return;
    log.listened(step, duration: _player.duration).catchError(_failed);
  }

  /// Writes what's been heard so far (the app going to the background may be its last chance).
  Future<void> save() => log.save();

  static void _failed(Object e) =>
      debugPrint('Recording listening stats failed: $e');

  void dispose() {
    _playedSub.cancel();
    _positionSub.cancel();
  }
}
