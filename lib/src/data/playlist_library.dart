import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import 'song_catalog.dart';
import 'youtube_library.dart';
import 'youtube_playlist.dart';

/// One playlist in Biblioteka.
class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.owner,
    required this.trackCount,
    required this.duration,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String? owner;
  final int trackCount;

  /// Sum of the known track lengths.
  final Duration duration;
  final DateTime updatedAt;
}

/// One row of a playlist.
class PlaylistTrack {
  const PlaylistTrack({
    required this.position,
    required this.title,
    this.artist,
    this.mainDbId,
    this.youtubeVideoId,
    this.duration,
  });

  /// 0-based.
  final int position;
  final String title;
  final String? artist;

  /// The MusicDatabase song (`songs.id`), when the track was recognised.
  final int? mainDbId;
  final String? youtubeVideoId;
  final Duration? duration;
}

/// What an import did, for the message shown afterwards.
typedef PlaylistImportResult = ({
  PlaylistSummary playlist,
  int recognised,
  bool updated,
});

/// The user's playlists, in the phone's `local.db` (tables created by `LocalLibrary`). So far
/// only imported from YouTube; importing the same YouTube playlist again replaces its tracks.
class PlaylistLibrary extends ChangeNotifier {
  PlaylistLibrary(
    this._database,
    this._catalog,
    this._youTube, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<Database> Function() _database;
  final SongCatalog _catalog;
  final YouTubeLibrary _youTube;
  final DateTime Function() _now;

  List<PlaylistSummary> _playlists = const [];

  /// Most recently updated first.
  List<PlaylistSummary> get playlists => _playlists;

  Future<void> load() async {
    final rows = await (await _database()).rawQuery('''
      SELECT p.id, p.name, p.owner, p.updated_at,
             COUNT(t.position) AS tracks, COALESCE(SUM(t.duration_s), 0) AS seconds
      FROM playlists p LEFT JOIN playlist_tracks t ON t.playlist_id = p.id
      GROUP BY p.id ORDER BY p.updated_at DESC''');
    _playlists = [
      for (final row in rows)
        PlaylistSummary(
          id: row['id']! as int,
          name: row['name']! as String,
          owner: row['owner'] as String?,
          trackCount: row['tracks']! as int,
          duration: Duration(seconds: row['seconds']! as int),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            row['updated_at']! as int,
          ),
        ),
    ];
    notifyListeners();
  }

  Future<List<PlaylistTrack>> tracks(int playlistId) async {
    final rows = await (await _database()).query(
      'playlist_tracks',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position',
    );
    return [
      for (final row in rows)
        PlaylistTrack(
          position: row['position']! as int,
          title: row['title']! as String,
          artist: row['artist'] as String?,
          mainDbId: row['main_db_id'] as int?,
          youtubeVideoId: row['youtube_video_id'] as String?,
          duration: row['duration_s'] == null
              ? null
              : Duration(seconds: row['duration_s']! as int),
        ),
    ];
  }

  /// Saves [data] as a playlist (or replaces the tracks of the one imported from it before),
  /// recognising each video as a MusicDatabase song where possible ([matchSong]).
  Future<PlaylistImportResult> importYouTube(YouTubePlaylistData data) async {
    await _catalog.ensureLoaded();
    final db = await _database();
    final now = _now().millisecondsSinceEpoch;
    var recognised = 0;
    late int playlistId;
    var updated = false;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'playlists',
        columns: ['id'],
        where: "source = 'youtube' AND source_id = ?",
        whereArgs: [data.id],
      );
      if (existing.isEmpty) {
        playlistId = await txn.insert('playlists', {
          'name': data.name,
          'owner': data.owner,
          'source': 'youtube',
          'source_id': data.id,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        updated = true;
        playlistId = existing.first['id']! as int;
        await txn.update(
          'playlists',
          {'name': data.name, 'owner': data.owner, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [playlistId],
        );
        await txn.delete(
          'playlist_tracks',
          where: 'playlist_id = ?',
          whereArgs: [playlistId],
        );
      }
      final batch = txn.batch();
      for (final (position, video) in data.videos.indexed) {
        final parsed = parseYouTubeTrack(video.title, video.channel);
        final song = matchSong(
          videoId: video.id,
          artist: parsed.artist,
          title: parsed.title,
        );
        if (song != null) recognised++;
        batch.insert('playlist_tracks', {
          'playlist_id': playlistId,
          'position': position,
          // A recognised song keeps MusicDatabase's own spelling.
          'artist': song?.artistLabel ?? parsed.artist,
          'title': song?.title ?? parsed.title,
          'main_db_id': song?.id,
          'youtube_video_id': video.id,
          'duration_s': video.duration?.inSeconds,
        });
      }
      await batch.commit(noResult: true);
    });
    await load();
    return (
      playlist: _playlists.firstWhere((p) => p.id == playlistId),
      recognised: recognised,
      updated: updated,
    );
  }

  /// The MusicDatabase song a YouTube video is: first by the video itself (music.db's
  /// `youtube_video_id`, then a video the phone matched earlier), then by artist and title.
  CatalogSong? matchSong({
    required String videoId,
    required String artist,
    required String title,
  }) {
    final byVideo = _catalog.findByYouTubeId(videoId);
    if (byVideo != null) return byVideo;
    final phoneMatched = _youTube.songForVideo(videoId);
    if (phoneMatched != null) {
      final song = _catalog.byId(phoneMatched);
      if (song != null) return song;
    }
    return _catalog.findExact(title: title, artist: artist);
  }

  Future<void> delete(int playlistId) async {
    final db = await _database();
    await db.delete(
      'playlist_tracks',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
    await load();
  }
}

/// Makes the [PlaylistLibrary] reachable from any screen.
class PlaylistLibraryScope extends InheritedNotifier<PlaylistLibrary> {
  const PlaylistLibraryScope({
    super.key,
    required PlaylistLibrary super.notifier,
    required super.child,
  });

  static PlaylistLibrary of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PlaylistLibraryScope>()!
      .notifier!;
}
