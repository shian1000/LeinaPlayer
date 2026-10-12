import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import 'song_catalog.dart';
import 'spotify_playlist.dart';
import 'youtube_library.dart';
import 'youtube_playlist.dart';
import 'youtube_video.dart';

/// Where a playlist was imported from.
enum PlaylistSource { youtube, spotify }

/// One playlist in Biblioteka.
class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.owner,
    required this.trackCount,
    required this.duration,
    required this.updatedAt,
    this.source,
    this.sourceId,
  });

  final int id;
  final String name;
  final String? owner;
  final int trackCount;

  /// Sum of the known track lengths.
  final Duration duration;
  final DateTime updatedAt;

  /// Where it was imported from, and that playlist's id there.
  final PlaylistSource? source;
  final String? sourceId;

  /// The YouTube playlist it was imported from (`list=` in its address).
  String? get youTubeId => source == PlaylistSource.youtube ? sourceId : null;

  /// The playlist's page where it was imported from, for sharing it; `null` for one that lives
  /// only on the phone.
  Uri? get link => switch (source) {
    PlaylistSource.youtube => Uri.https('www.youtube.com', '/playlist', {
      'list': sourceId,
    }),
    PlaylistSource.spotify => spotifyPlaylistUri(sourceId!),
    null => null,
  };
}

/// One row of a playlist.
class PlaylistTrack {
  const PlaylistTrack({
    required this.position,
    required this.title,
    this.artist,
    this.mainDbId,
    this.youtubeVideoId,
    this.spotifyTrackId,
    this.duration,
    this.videoRemoved = false,
  });

  /// 0-based.
  final int position;
  final String title;
  final String? artist;

  /// The MusicDatabase song (`songs.id`), when the track was recognised.
  final int? mainDbId;
  final String? youtubeVideoId;

  /// The track on Spotify, for tracks imported from a Spotify playlist.
  final String? spotifyTrackId;
  final Duration? duration;

  /// YouTube removed [youtubeVideoId] (it dropped out of the playlist and the video is gone);
  /// the track stays, to be found on YouTube again.
  final bool videoRemoved;

  /// The video to play and show, unless YouTube removed it.
  String? get playableVideoId => videoRemoved ? null : youtubeVideoId;
}

/// What an import did, for the message shown afterwards.
typedef PlaylistImportResult = ({
  PlaylistSummary playlist,
  int recognised,
  bool updated,

  /// Tracks kept although YouTube removed their video.
  int removedVideos,
});

/// Whether a YouTube video still exists: `null` when it couldn't be checked (no connection).
typedef VideoExistsFn = Future<bool?> Function(String videoId);

/// A track about to be saved, already matched.
typedef _NewTrack = ({
  String? artist,
  String title,
  CatalogSong? song,
  String? videoId,
  String? spotifyTrackId,
  Duration? duration,
});

/// A track kept from the playlist as it was saved before.
typedef _KeptTrack = ({PlaylistTrack track, bool videoRemoved});

/// The user's playlists, in the phone's `local.db` (tables created by `LocalLibrary`). So far
/// only imported from YouTube or Spotify; importing the same playlist again replaces its tracks.
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
      SELECT p.id, p.name, p.owner, p.updated_at, p.source, p.source_id,
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
          source: PlaylistSource.values.asNameMap()[row['source']],
          sourceId: row['source_id'] as String?,
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
          spotifyTrackId: row['spotify_track_id'] as String?,
          duration: row['duration_s'] == null
              ? null
              : Duration(seconds: row['duration_s']! as int),
          videoRemoved: row['youtube_removed'] == 1,
        ),
    ];
  }

  /// The Biblioteka playlist imported from [source]'s playlist [sourceId], if there is one.
  PlaylistSummary? saved(PlaylistSource source, String sourceId) => _playlists
      .where((p) => p.source == source && p.sourceId == sourceId)
      .firstOrNull;

  /// [data]'s tracks as [importYouTube] would save them (recognised the same way), for showing
  /// a playlist found by search without saving it.
  Future<List<PlaylistTrack>> previewYouTube(YouTubePlaylistData data) async {
    await _catalog.ensureLoaded();
    return [
      for (final (i, video)
          in data.videos.where((v) => !_isUnavailableEntry(v)).indexed)
        _unsaved(i, _youTubeTrack(video)),
    ];
  }

  /// Like [previewYouTube], for [importSpotify].
  Future<List<PlaylistTrack>> previewSpotify(SpotifyPlaylistData data) async {
    await _catalog.ensureLoaded();
    return [
      for (final (i, track) in data.tracks.indexed)
        _unsaved(i, _spotifyTrack(track)),
    ];
  }

  static PlaylistTrack _unsaved(int position, _NewTrack track) => PlaylistTrack(
    position: position,
    title: track.song?.title ?? track.title,
    artist: track.song?.artistLabel ?? track.artist,
    mainDbId: track.song?.id,
    youtubeVideoId: track.videoId,
    spotifyTrackId: track.spotifyTrackId,
    duration: track.duration,
  );

  /// Saves [data] as a playlist (or replaces the tracks of the one imported from it before),
  /// recognising each video as a MusicDatabase song where possible ([matchSong]).
  ///
  /// YouTube hides removed videos from a playlist, so a track saved before that's missing now
  /// is checked with [videoExists]: still on YouTube → the owner took it out, it goes; gone →
  /// it stays where it was, marked [PlaylistTrack.videoRemoved]; unknown → it stays as it was.
  /// Without [videoExists] the old tracks are simply replaced.
  Future<PlaylistImportResult> importYouTube(
    YouTubePlaylistData data, {
    VideoExistsFn? videoExists,
  }) async {
    await _catalog.ensureLoaded();
    final videos = [
      for (final video in data.videos)
        if (!_isUnavailableEntry(video)) video,
    ];
    final fetched = {for (final v in videos) v.id};
    final before = await _savedTracks(PlaylistSource.youtube, data.id);
    // Old tracks no longer listed, by the fetched video they followed (null: the start).
    final keptAfter = <String?, List<_KeptTrack>>{};
    String? anchor;
    for (final track in before) {
      final videoId = track.youtubeVideoId;
      if (videoId != null && fetched.contains(videoId)) {
        anchor = videoId;
        continue;
      }
      // Without a way to check, the playlist is simply replaced.
      final exists = videoExists == null
          ? true
          : videoId == null || track.videoRemoved
          ? false
          : await videoExists(videoId);
      if (exists ?? false) continue;
      (keptAfter[anchor] ??= []).add((
        track: track,
        videoRemoved: track.videoRemoved || exists == false,
      ));
    }
    final kept = [for (final list in keptAfter.values) ...list];
    await _youTube.clearVideosRemoved(fetched);
    for (final k in kept) {
      final videoId = k.track.youtubeVideoId;
      if (k.videoRemoved && videoId != null) {
        await _youTube.markVideoRemoved(videoId);
      }
    }
    return _save(
      source: PlaylistSource.youtube,
      sourceId: data.id,
      name: data.name,
      owner: data.owner,
      tracks: [
        ...?keptAfter[null],
        for (final video in videos) ...[
          _youTubeTrack(video),
          ...?keptAfter[video.id],
        ],
      ],
      removedVideos: kept.where((k) => k.videoRemoved).length,
    );
  }

  /// "[Deleted video]" / "[Private video]": entries YouTube may still list in a playlist.
  static bool _isUnavailableEntry(YouTubeVideo video) => RegExp(
    r'^\[(deleted|private) video\]$',
    caseSensitive: false,
  ).hasMatch(video.title.trim());

  Future<List<PlaylistTrack>> _savedTracks(
    PlaylistSource source,
    String sourceId,
  ) async {
    final rows = await (await _database()).query(
      'playlists',
      columns: ['id'],
      where: 'source = ? AND source_id = ?',
      whereArgs: [source.name, sourceId],
    );
    return rows.isEmpty ? const [] : tracks(rows.first['id']! as int);
  }

  _NewTrack _youTubeTrack(YouTubeVideo video) {
    final parsed = parseYouTubeTrack(video.title, video.channel);
    return (
      artist: parsed.artist,
      title: parsed.title,
      song: matchSong(
        videoId: video.id,
        artist: parsed.artist,
        title: parsed.title,
      ),
      videoId: video.id,
      spotifyTrackId: null,
      duration: video.duration,
    );
  }

  /// Saves [data] like [importYouTube]. Spotify tracks have no video, so they're recognised by
  /// title and artist only ([matchSpotifyTrack]); the rest are found on YouTube when played.
  Future<PlaylistImportResult> importSpotify(SpotifyPlaylistData data) async {
    await _catalog.ensureLoaded();
    return _save(
      source: PlaylistSource.spotify,
      sourceId: data.id,
      name: data.name,
      owner: data.owner,
      tracks: [for (final track in data.tracks) _spotifyTrack(track)],
    );
  }

  _NewTrack _spotifyTrack(SpotifyTrack track) => (
    artist: track.artists.isEmpty ? null : track.artists.join(', '),
    title: cleanSpotifyTitle(track.title),
    song: matchSpotifyTrack(track),
    videoId: null,
    spotifyTrackId: track.id,
    duration: track.duration,
  );

  Future<PlaylistImportResult> _save({
    required PlaylistSource source,
    required String sourceId,
    required String name,
    required String? owner,
    required List<Object> tracks,
    int removedVideos = 0,
  }) async {
    final db = await _database();
    final now = _now().millisecondsSinceEpoch;
    late int playlistId;
    var updated = false;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'playlists',
        columns: ['id'],
        where: 'source = ? AND source_id = ?',
        whereArgs: [source.name, sourceId],
      );
      if (existing.isEmpty) {
        playlistId = await txn.insert('playlists', {
          'name': name,
          'owner': owner,
          'source': source.name,
          'source_id': sourceId,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        updated = true;
        playlistId = existing.first['id']! as int;
        await txn.update(
          'playlists',
          {'name': name, 'owner': owner, 'updated_at': now},
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
      for (final (position, entry) in tracks.indexed) {
        batch.insert('playlist_tracks', {
          'playlist_id': playlistId,
          'position': position,
          ...switch (entry) {
            _NewTrack(:final song) => {
              // A recognised song keeps MusicDatabase's own spelling.
              'artist': song?.artistLabel ?? entry.artist,
              'title': song?.title ?? entry.title,
              'main_db_id': song?.id,
              'youtube_video_id': entry.videoId,
              'spotify_track_id': entry.spotifyTrackId,
              'duration_s': entry.duration?.inSeconds,
            },
            _KeptTrack(:final track) => {
              'artist': track.artist,
              'title': track.title,
              'main_db_id': track.mainDbId,
              'youtube_video_id': track.youtubeVideoId,
              'spotify_track_id': track.spotifyTrackId,
              'duration_s': track.duration?.inSeconds,
              'youtube_removed': entry.videoRemoved ? 1 : 0,
            },
            _ => throw ArgumentError.value(entry),
          },
        });
      }
      await batch.commit(noResult: true);
    });
    await load();
    return (
      playlist: _playlists.firstWhere((p) => p.id == playlistId),
      recognised: tracks
          .where(
            (t) => switch (t) {
              _NewTrack(:final song) => song != null,
              _KeptTrack(:final track) => track.mainDbId != null,
              _ => false,
            },
          )
          .length,
      updated: updated,
      removedVideos: removedVideos,
    );
  }

  /// The MusicDatabase song a Spotify track is: exact title (as Spotify has it, then without
  /// its "- Remastered …" suffix) with all its artists together or any one of them.
  CatalogSong? matchSpotifyTrack(SpotifyTrack track) {
    final titles = {track.title, cleanSpotifyTitle(track.title)};
    final artists = {track.artists.join(', '), ...track.artists};
    for (final title in titles) {
      for (final artist in artists) {
        final song = _catalog.findExact(title: title, artist: artist);
        if (song != null) return song;
      }
    }
    return null;
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
