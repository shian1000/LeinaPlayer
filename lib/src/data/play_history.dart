import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'track_ref.dart';

/// One song that started playing.
class PlayedTrack {
  const PlayedTrack({
    required this.track,
    required this.playedAt,
    this.playlistId,
    this.playlistName,
  });

  final TrackRef track;
  final DateTime playedAt;

  /// The playlist it was played from; `null` for a song played on its own (search, "Dodaj do
  /// kolejki").
  final int? playlistId;
  final String? playlistName;
}

/// What was played, newest first ("Ostatnie" in the profile menu), in the phone's `local.db`
/// (table created by `LocalLibrary`). Plays older than [keepDays] (Ustawienia › Historia
/// odtwarzania) are deleted, and never more than the newest [limit] are kept.
class PlayHistory extends ChangeNotifier {
  PlayHistory(this._database, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const limit = 1000;
  static const _keepDaysKey = 'history.keep_days';
  static const defaultKeepDays = 90;

  /// The choices offered in the settings; 0 = keep everything (up to [limit]).
  static const keepDaysChoices = [7, 30, 90, 180, 365, 0];

  final Future<Database> Function() _database;
  final DateTime Function() _now;

  List<PlayedTrack> _entries = const [];
  int _keepDays = defaultKeepDays;

  /// How long plays are kept, in days; 0 = with no time limit.
  int get keepDays => _keepDays;

  /// Newest first.
  List<PlayedTrack> get entries => _entries;

  Future<void> load() async {
    _keepDays =
        (await SharedPreferences.getInstance()).getInt(_keepDaysKey) ??
        _keepDays;
    await _deleteOld();
    final rows = await (await _database()).query(
      'play_history',
      orderBy: 'played_at DESC, id DESC',
      limit: limit,
    );
    _entries = [for (final row in rows) _fromRow(row)];
    notifyListeners();
  }

  Future<void> record(
    TrackRef track, {
    int? playlistId,
    String? playlistName,
  }) async {
    final entry = PlayedTrack(
      track: track,
      playedAt: _now(),
      playlistId: playlistId,
      playlistName: playlistName,
    );
    _entries = [entry, ..._entries.take(limit - 1)];
    notifyListeners();
    final db = await _database();
    await db.insert('play_history', {
      'played_at': entry.playedAt.millisecondsSinceEpoch,
      'title': track.title,
      'artist': track.artist,
      'main_db_id': track.mainDbId,
      'file_path': track.filePath,
      'youtube_video_id': track.videoId,
      'spotify_track_id': track.spotifyTrackId,
      'playlist_id': playlistId,
      'playlist_name': playlistName,
    });
    await db.rawDelete(
      'DELETE FROM play_history WHERE id NOT IN '
      '(SELECT id FROM play_history ORDER BY played_at DESC, id DESC LIMIT ?)',
      [limit],
    );
    await _deleteOld();
  }

  Future<void> setKeepDays(int days) async {
    _keepDays = days;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(_keepDaysKey, days);
    await _deleteOld();
  }

  /// "Wyczyść historię".
  Future<void> clear() async {
    await (await _database()).delete('play_history');
    _entries = const [];
    notifyListeners();
  }

  Future<void> _deleteOld() async {
    if (_keepDays == 0) return;
    final cutoff = _now().subtract(Duration(days: _keepDays));
    await (await _database()).delete(
      'play_history',
      where: 'played_at < ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
    final kept = [
      for (final e in _entries)
        if (!e.playedAt.isBefore(cutoff)) e,
    ];
    if (kept.length != _entries.length) _entries = kept;
    notifyListeners();
  }

  static PlayedTrack _fromRow(Map<String, Object?> row) => PlayedTrack(
    track: TrackRef(
      title: row['title'] as String,
      artist: row['artist'] as String?,
      mainDbId: row['main_db_id'] as int?,
      filePath: row['file_path'] as String?,
      videoId: row['youtube_video_id'] as String?,
      spotifyTrackId: row['spotify_track_id'] as String?,
    ),
    playedAt: DateTime.fromMillisecondsSinceEpoch(row['played_at'] as int),
    playlistId: row['playlist_id'] as int?,
    playlistName: row['playlist_name'] as String?,
  );
}

/// Makes the [PlayHistory] reachable from any screen.
class PlayHistoryScope extends InheritedNotifier<PlayHistory> {
  const PlayHistoryScope({
    super.key,
    required PlayHistory super.notifier,
    required super.child,
  });

  static PlayHistory of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayHistoryScope>()!.notifier!;
}
