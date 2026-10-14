import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'combined_search.dart';
import 'custom_covers.dart';
import 'playlist_sync.dart';
import 'song_catalog.dart';
import 'spotify_playlist.dart';
import 'youtube_library.dart';
import 'youtube_playlist.dart';
import 'youtube_video.dart';

/// Where a playlist was imported from: a YouTube or Spotify playlist, a Spotify album, or (in
/// MusicDatabase's menu) a music folder on the server.
enum PlaylistSource {
  youtube,
  spotify,
  spotifyAlbum,
  folder;

  bool get isSpotify => this == spotify || this == spotifyAlbum;
}

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
    this.account,
    this.cover,
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

  /// The MusicDatabase user whose playlists it's synced with; `null` = only on this phone.
  final String? account;

  /// The picked cover's hash ([CustomCovers]); `null`: a collage of its tracks' covers.
  final String? cover;

  /// The YouTube playlist it was imported from (`list=` in its address).
  String? get youTubeId => source == PlaylistSource.youtube ? sourceId : null;

  /// The playlist's page where it was imported from, for sharing it; `null` for one that lives
  /// only on the phone.
  Uri? get link => switch (source) {
    PlaylistSource.youtube => Uri.https('www.youtube.com', '/playlist', {
      'list': sourceId,
    }),
    PlaylistSource.spotify => spotifyPlaylistUri(sourceId!),
    PlaylistSource.spotifyAlbum => spotifyAlbumUri(sourceId!),
    PlaylistSource.folder || null => null,
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
///
/// While a MusicDatabase user is logged in, new playlists belong to that account and [sync]
/// exchanges them with MusicDatabase ([ADR 0007](../../../docs/decisions/0007-playlist-sync.md)).
/// Only the logged-in account's playlists and the phone-only ones are shown; another account's
/// stay in `local.db`, hidden until it logs in again.
class PlaylistLibrary extends ChangeNotifier {
  PlaylistLibrary(
    this._database,
    this._catalog,
    this._youTube, {
    DateTime Function()? now,
    String? Function()? userName,
    String? Function()? authToken,
    this.covers,
  }) : _now = now ?? DateTime.now,
       _userName = userName ?? (() => null),
       _authToken = authToken ?? (() => null);

  final Future<Database> Function() _database;
  final SongCatalog _catalog;

  /// Where cover pictures are kept, sent from and downloaded to; `null` in tests without them.
  final CustomCovers? covers;
  final YouTubeLibrary _youTube;
  final DateTime Function() _now;

  /// The logged-in MusicDatabase user ([Account]); `null` while logged out.
  final String? Function() _userName;
  final String? Function() _authToken;

  /// A playlist was changed here, e.g. to send it to MusicDatabase soon.
  VoidCallback? onChanged;

  /// The server didn't accept [_authToken] (HTTP 401): the user has to log in again.
  VoidCallback? onUnauthorized;

  List<PlaylistSummary> _playlists = const [];

  /// Most recently updated first.
  List<PlaylistSummary> get playlists => _playlists;

  /// Rows of the account logged in now, or phone-only ones ([_userName] `null`: only those).
  ({String where, List<Object?> args}) _scope([String prefix = '']) {
    final user = _userName();
    return user == null
        ? (where: '${prefix}account IS NULL', args: const [])
        : (
            where: '(${prefix}account IS NULL OR ${prefix}account = ?)',
            args: [user],
          );
  }

  Future<void> load() async {
    final scope = _scope('p.');
    final rows = await (await _database()).rawQuery('''
      SELECT p.id, p.name, p.owner, p.updated_at, p.source, p.source_id, p.account,
             p.cover_sha256,
             COUNT(t.position) AS tracks, COALESCE(SUM(t.duration_s), 0) AS seconds
      FROM playlists p LEFT JOIN playlist_tracks t ON t.playlist_id = p.id
      WHERE p.deleted_at IS NULL AND ${scope.where}
      GROUP BY p.id ORDER BY p.updated_at DESC''', scope.args);
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
          account: row['account'] as String?,
          cover: row['cover_sha256'] as String?,
        ),
    ];
    final lead = <int, List<PlaylistTrack>>{};
    for (final row in await (await _database()).rawQuery(
      '''
      SELECT t.* FROM playlist_tracks t JOIN playlists p ON p.id = t.playlist_id
      WHERE t.position < ? AND p.deleted_at IS NULL AND ${scope.where}
      ORDER BY t.playlist_id, t.position''',
      [leadTrackCount, ...scope.args],
    )) {
      (lead[row['playlist_id']! as int] ??= []).add(_track(row));
    }
    _leadTracks = lead;
    notifyListeners();
  }

  Future<List<PlaylistTrack>> tracks(int playlistId) async {
    final rows = await (await _database()).query(
      'playlist_tracks',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'position',
    );
    return [for (final row in rows) _track(row)];
  }

  static PlaylistTrack _track(Map<String, Object?> row) => PlaylistTrack(
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
  );

  /// How many tracks from the start [leadTracks] keeps: enough to find four different albums
  /// for the collage in most playlists.
  static const leadTrackCount = 12;

  Map<int, List<PlaylistTrack>> _leadTracks = const {};

  /// The first [leadTrackCount] tracks of a playlist in [playlists], for its cover collage
  /// without reading the whole playlist.
  List<PlaylistTrack> leadTracks(int playlistId) =>
      _leadTracks[playlistId] ?? const [];

  /// The Biblioteka playlist [id] as now loaded, if it's still there.
  PlaylistSummary? byId(int id) =>
      _playlists.where((p) => p.id == id).firstOrNull;

  /// Gives the playlist the picked cover [hash] (`null`: back to the collage); synced like a
  /// rename.
  Future<void> setCover(int playlistId, String? hash) async {
    await (await _database()).update(
      'playlists',
      {
        'cover_sha256': hash,
        'updated_at': _now().millisecondsSinceEpoch,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [playlistId],
    );
    await load();
    onChanged?.call();
  }

  /// Every cover hash a playlist on the phone refers to (any account's), so [CustomCovers.prune]
  /// keeps them.
  Future<Set<String>> usedCovers() async => {
    for (final row in await (await _database()).rawQuery(
      'SELECT DISTINCT cover_sha256 FROM playlists WHERE cover_sha256 IS NOT NULL',
    ))
      row['cover_sha256']! as String,
  };

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
    final scope = _scope();
    final rows = await (await _database()).query(
      'playlists',
      columns: ['id'],
      where:
          'source = ? AND source_id = ? AND deleted_at IS NULL AND ${scope.where}',
      whereArgs: [source.name, sourceId, ...scope.args],
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
  /// An album becomes a playlist of its own.
  Future<PlaylistImportResult> importSpotify(SpotifyPlaylistData data) async {
    await _catalog.ensureLoaded();
    return _save(
      source: data.album ? PlaylistSource.spotifyAlbum : PlaylistSource.spotify,
      sourceId: data.id,
      name: data.name,
      owner: data.owner,
      tracks: [for (final track in data.tracks) _spotifyTrack(track)],
    );
  }

  /// A new playlist of [songs] made on the phone (e.g. the queue saved), with no source to
  /// re-import it from. A song keeps music.db's id and, only when it has no MusicDatabase song,
  /// the video it plays — music.db's own link stays music.db's (ADR 0003). A song only on the
  /// phone is kept by its title and artist ([playlistHit] finds its file again).
  Future<PlaylistSummary> create(String name, List<SearchHit> songs) async {
    final db = await _database();
    final now = _now().millisecondsSinceEpoch;
    late int playlistId;
    await db.transaction((txn) async {
      playlistId = await txn.insert('playlists', {
        'name': name,
        'created_at': now,
        'updated_at': now,
        'uid': newPlaylistUid(),
        'account': _userName(),
        'dirty': 1,
      });
      final batch = txn.batch();
      for (final (position, hit) in songs.indexed) {
        final song = hit.mainSong;
        batch.insert('playlist_tracks', {
          'playlist_id': playlistId,
          'position': position,
          'artist': song != null
              ? song.artistLabel
              : hit.onPhone
              ? hit.phoneFiles.first.artist
              : hit.artistLabel,
          'title': hit.title,
          'main_db_id': song?.id,
          'youtube_video_id':
              hit.playlistVideoId ?? (song == null ? hit.youtubeVideoId : null),
          'spotify_track_id': hit.spotifyTrackId,
        });
      }
      await batch.commit(noResult: true);
    });
    await load();
    onChanged?.call();
    return _playlists.firstWhere((p) => p.id == playlistId);
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
    final scope = _scope();
    late int playlistId;
    var updated = false;
    await db.transaction((txn) async {
      // A playlist deleted here but not yet on MusicDatabase comes back under its own id.
      final existing = await txn.query(
        'playlists',
        columns: ['id', 'deleted_at'],
        where: 'source = ? AND source_id = ? AND ${scope.where}',
        whereArgs: [source.name, sourceId, ...scope.args],
        orderBy: 'deleted_at IS NOT NULL',
      );
      if (existing.isEmpty) {
        playlistId = await txn.insert('playlists', {
          'name': name,
          'owner': owner,
          'source': source.name,
          'source_id': sourceId,
          'created_at': now,
          'updated_at': now,
          'uid': newPlaylistUid(),
          'account': _userName(),
          'dirty': 1,
        });
      } else {
        updated = existing.first['deleted_at'] == null;
        playlistId = existing.first['id']! as int;
        await txn.update(
          'playlists',
          {
            'name': name,
            'owner': owner,
            'updated_at': now,
            'dirty': 1,
            'deleted_at': null,
          },
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
    onChanged?.call();
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

  /// Removes the playlist. An account's playlist stays as a marker without tracks until
  /// MusicDatabase hears of the deletion ([sync]), which deletes it on the account's other
  /// devices too (keeping a copy in its archive).
  Future<void> delete(int playlistId) async {
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete(
        'playlist_tracks',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      await txn.rawUpdate(
        'UPDATE playlists SET deleted_at = ?, dirty = 0, cover_sha256 = NULL '
        'WHERE id = ? AND account IS NOT NULL',
        [_now().millisecondsSinceEpoch, playlistId],
      );
      await txn.delete(
        'playlists',
        where: 'id = ? AND account IS NULL',
        whereArgs: [playlistId],
      );
    });
    await load();
    onChanged?.call();
  }

  /// Playlists that live only on this phone (made while logged out).
  Future<int> phoneOnlyCount() async {
    final rows = await (await _database()).rawQuery(
      'SELECT COUNT(*) AS n FROM playlists '
      'WHERE account IS NULL AND deleted_at IS NULL',
    );
    return rows.first['n']! as int;
  }

  /// The phone-only playlists become the logged-in account's, sent to MusicDatabase by [sync].
  Future<void> addPhoneOnlyToAccount() async {
    final user = _userName();
    if (user == null) return;
    await (await _database()).rawUpdate(
      'UPDATE playlists SET account = ?, dirty = 1, revision = 0 '
      'WHERE account IS NULL AND deleted_at IS NULL',
      [user],
    );
    await load();
    onChanged?.call();
  }

  bool _syncing = false;
  bool _syncAgain = false;
  PlaylistSyncResult? _lastSync;

  bool get syncing => _syncing;

  /// How the last [sync] went; `null` before the first one.
  PlaylistSyncResult? get lastSync => _lastSync;

  static String _revisionKey(String user) => 'playlists.sync_revision.$user';

  /// Exchanges the logged-in account's playlists with MusicDatabase on the first of [servers]
  /// that answers: first what changed there since the last time (a playlist changed here too
  /// waits — sending it settles which version stays), then the deletions and changes made
  /// here. MusicDatabase keeps whichever change is newer and answers with the stored playlist,
  /// which replaces the phone's. Nothing happens while logged out.
  Future<void> sync(List<Uri> servers) async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    final user = _userName();
    final token = _authToken();
    if (user == null || token == null || servers.isEmpty) return;
    _syncing = true;
    notifyListeners();
    try {
      do {
        _syncAgain = false;
        _lastSync = PlaylistSyncResult(
          at: _now(),
          problem: await _syncWith(servers, user, token),
        );
      } while (_syncAgain && _userName() == user && _authToken() == token);
    } finally {
      _syncing = false;
      await load();
    }
  }

  Future<String?> _syncWith(
    List<Uri> servers,
    String user,
    String token,
  ) async {
    String? problem;
    for (final server in servers) {
      final client = PlaylistSyncClient(server, user, token);
      try {
        return await _syncOn(client, user);
      } on _SyncStopped catch (e) {
        return e.problem;
      } catch (e) {
        debugPrint('Playlist sync on $server failed: $e');
        problem = 'Brak połączenia z serwerem MusicDatabase';
      } finally {
        client.close();
      }
    }
    return problem;
  }

  Future<String?> _syncOn(PlaylistSyncClient client, String user) async {
    final prefs = await SharedPreferences.getInstance();
    final since = prefs.getInt(_revisionKey(user)) ?? 0;
    var answer = await client.changedSince(since);
    _check(answer);
    var changes = answer.body! as Map<String, Object?>;
    // The counter went back (the account's data was restored or made again): fetch it all.
    if ((changes['revision']! as int) < since) {
      answer = await client.changedSince(0);
      _check(answer);
      changes = answer.body! as Map<String, Object?>;
    }
    final db = await _database();
    await db.transaction((txn) async {
      for (final playlist in changes['playlists']! as List) {
        final remote = playlist as Map<String, Object?>;
        final local = await txn.query(
          'playlists',
          columns: ['dirty', 'deleted_at'],
          where: 'uid = ?',
          whereArgs: [remote['uid']],
        );
        if (local.isNotEmpty &&
            (local.first['dirty'] == 1 || local.first['deleted_at'] != null)) {
          continue;
        }
        await _applyRemote(txn, remote, user);
      }
    });
    await prefs.setInt(_revisionKey(user), changes['revision']! as int);

    String? problem;
    for (final row in await db.query(
      'playlists',
      where: 'account = ? AND deleted_at IS NOT NULL',
      whereArgs: [user],
    )) {
      final deletedAt = row['deleted_at']! as int;
      final answer = await client.delete(
        row['uid']! as String,
        row['revision']! as int,
        deletedAt,
      );
      problem ??= _check(answer, keepGoing: true);
      if (answer.body is! Map) continue;
      await db.transaction((txn) async {
        // Brought back here while the answer was on its way: that's sent next time.
        final still = await txn.query(
          'playlists',
          columns: ['id'],
          where: 'id = ? AND deleted_at = ?',
          whereArgs: [row['id'], deletedAt],
        );
        if (still.isEmpty) return;
        final remote = answer.body! as Map<String, Object?>;
        if (remote['deleted'] == true) {
          await txn.delete(
            'playlists',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } else {
          await _applyRemote(txn, remote, user, intoId: row['id']! as int);
        }
      });
    }
    for (final row in await db.query(
      'playlists',
      where: 'account = ? AND dirty = 1 AND deleted_at IS NULL',
      whereArgs: [user],
    )) {
      final id = row['id']! as int;
      final answer = await putWithCover(
        client,
        covers,
        row['uid']! as String,
        await _toJson(db, row),
      );
      problem ??= _check(answer, keepGoing: true);
      if (answer.body is! Map) continue;
      final remote = answer.body! as Map<String, Object?>;
      await db.transaction((txn) async {
        final now = await txn.query(
          'playlists',
          columns: ['updated_at', 'deleted_at'],
          where: 'id = ?',
          whereArgs: [id],
        );
        if (now.isEmpty) return;
        // Changed again here while this was being sent: the answer's revision is the base the
        // newer change goes with next time; its tracks would undo that change.
        if (now.first['updated_at'] != row['updated_at'] ||
            now.first['deleted_at'] != null) {
          await txn.update(
            'playlists',
            {'revision': remote['revision'], 'uid': remote['uid']},
            where: 'id = ?',
            whereArgs: [id],
          );
          return;
        }
        await _applyRemote(txn, remote, user, intoId: id);
      });
    }
    await fetchCovers(client, covers, [
      for (final row in await db.query(
        'playlists',
        columns: ['cover_sha256'],
        where: 'account = ? AND cover_sha256 IS NOT NULL',
        whereArgs: [user],
      ))
        row['cover_sha256']! as String,
    ]);
    return problem;
  }

  /// Throws [_SyncStopped] for answers that end this sync (logged out, the server's drive
  /// missing) and returns the problem of one playlist's answer otherwise; `null` when it went.
  String? _check(SyncAnswer answer, {bool keepGoing = false}) {
    switch (answer.status) {
      case HttpStatus.ok || HttpStatus.conflict when answer.body is Map:
        return null;
      case HttpStatus.unauthorized:
        onUnauthorized?.call();
        throw const _SyncStopped(
          'Serwer nie przyjął logowania — zaloguj się ponownie (Ustawienia › Konto)',
        );
      case HttpStatus.serviceUnavailable:
        throw const _SyncStopped(
          'Serwer MusicDatabase nie może teraz zapisać playlist (dysk niepodłączony lub '
          'baza użytkownika jeszcze nieprzygotowana)',
        );
      case HttpStatus.notFound when !keepGoing:
        throw const _SyncStopped(
          'Serwer MusicDatabase nie obsługuje jeszcze playlist',
        );
    }
    final problem = 'Serwer odrzucił playlistę (HTTP ${answer.status})';
    if (keepGoing) return problem;
    throw _SyncStopped(problem);
  }

  /// [row] as MusicDatabase's PUT body: the whole playlist and the revision it's based on.
  Future<Map<String, Object?>> _toJson(
    Database db,
    Map<String, Object?> row,
  ) async => {
    'uid': row['uid'],
    'base_revision': row['revision'],
    'name': row['name'],
    'source': row['source'],
    'source_id': row['source_id'],
    'source_owner': row['owner'],
    'cover': row['cover_sha256'],
    'created_at': row['created_at'],
    'updated_at': row['updated_at'],
    'tracks': [
      for (final t in await tracks(row['id']! as int))
        {
          'song_id': t.mainDbId,
          'title': t.title,
          'artist': t.artist,
          'youtube_video_id': t.youtubeVideoId,
          'spotify_track_id': t.spotifyTrackId,
          'youtube_removed': t.videoRemoved,
          'duration_s': t.duration?.inSeconds,
        },
    ],
  };

  /// Stores MusicDatabase's [remote] playlist as [user]'s: in place of the row [intoId] (the
  /// one just sent — MusicDatabase may have given it another playlist's uid), else of the row
  /// with its uid, else as a new one. Local ids stay, as the queue and history refer to them.
  Future<void> _applyRemote(
    Transaction txn,
    Map<String, Object?> remote,
    String user, {
    int? intoId,
  }) async {
    final uid = remote['uid']! as String;
    final sameUid = [
      for (final row in await txn.query(
        'playlists',
        columns: ['id'],
        where: 'uid = ?',
        whereArgs: [uid],
      ))
        row['id']! as int,
    ];
    final id = intoId ?? sameUid.firstOrNull;
    for (final other in sameUid.where((other) => other != id)) {
      await txn.delete(
        'playlist_tracks',
        where: 'playlist_id = ?',
        whereArgs: [other],
      );
      await txn.delete('playlists', where: 'id = ?', whereArgs: [other]);
    }
    if (id != null) {
      await txn.delete(
        'playlist_tracks',
        where: 'playlist_id = ?',
        whereArgs: [id],
      );
    }
    if (remote['deleted'] == true) {
      if (id != null) {
        await txn.delete('playlists', where: 'id = ?', whereArgs: [id]);
      }
      return;
    }
    final values = {
      'uid': uid,
      'account': user,
      'revision': remote['revision'],
      'dirty': 0,
      'deleted_at': null,
      'name': remote['name'],
      'owner': remote['source_owner'],
      'source': remote['source'],
      'source_id': remote['source_id'],
      'created_at': remote['created_at'],
      'updated_at': remote['updated_at'],
      // A server from before covers says nothing about them.
      if (remote.containsKey('cover')) 'cover_sha256': remote['cover'],
    };
    if (id != null) {
      await txn.update('playlists', values, where: 'id = ?', whereArgs: [id]);
    }
    final playlistId = id ?? await txn.insert('playlists', values);
    final batch = txn.batch();
    for (final (position, track) in (remote['tracks']! as List).indexed) {
      final t = track as Map<String, Object?>;
      batch.insert('playlist_tracks', {
        'playlist_id': playlistId,
        'position': position,
        'title': t['title'],
        'artist': t['artist'],
        'main_db_id': t['song_id'],
        'youtube_video_id': t['youtube_video_id'],
        'spotify_track_id': t['spotify_track_id'],
        'youtube_removed': t['youtube_removed'] == true ? 1 : 0,
        'duration_s': t['duration_s'],
      });
    }
    await batch.commit(noResult: true);
  }
}

/// An answer that ends a [PlaylistLibrary.sync] early, with why (Polish, for display).
class _SyncStopped implements Exception {
  const _SyncStopped(this.problem);

  final String problem;
}

/// Makes the [PlaylistLibrary] reachable from any screen.
class PlaylistLibraryScope extends InheritedNotifier<PlaylistLibrary> {
  const PlaylistLibraryScope({
    super.key,
    required PlaylistLibrary super.notifier,
    required super.child,
  });

  static PlaylistLibrary of(BuildContext context) => maybeOf(context)!;

  /// `null` outside the app (widget tests that pump a single screen).
  static PlaylistLibrary? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PlaylistLibraryScope>()
      ?.notifier;
}
