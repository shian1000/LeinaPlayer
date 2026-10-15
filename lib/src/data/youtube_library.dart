import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'song_catalog.dart';
import 'text_normalizer.dart';
import 'youtube_video.dart';

/// One cached audio file.
class YouTubeCacheEntry {
  const YouTubeCacheEntry({
    required this.videoId,
    required this.file,
    required this.sizeBytes,
    required this.lastPlayed,
  });

  final String videoId;
  final File file;
  final int sizeBytes;
  final DateTime lastPlayed;
}

/// What the phone itself knows about YouTube, in `local.db` (tables created by
/// [LocalLibrary]):
///
/// - `youtube_matches`: the video the phone found for a MusicDatabase song without
///   `youtube_video_id` (ADR 0003 — local and temporary; music.db's own link wins).
/// - `youtube_track_matches`: the same for a track known only by artist and title (from a
///   Spotify playlist), until it's recognised as a MusicDatabase song.
/// - `youtube_not_found`: songs (either kind) the phone searched YouTube for without finding a
///   sure match — remembered for [notFoundFor], so they aren't searched again on every play.
/// - `youtube_removed_videos`: videos YouTube no longer has ([markVideoRemoved]); a playlist's
///   or the phone's own video that's among them isn't used ([isVideoRemoved]).
/// - `youtube_cache`: audio of played videos, in `<support dir>/youtube_cache/`, at most the
///   user's limit; the least recently played goes first.
///
/// A file gets into the cache by [download], started next to playback: YouTube throttles one
/// long request to about playback speed, but answers 1 MB `Range` requests at full speed, so the
/// file is complete within seconds instead of only at the end of the song.
class YouTubeLibrary extends ChangeNotifier {
  YouTubeLibrary(
    this._database, {
    Future<Directory> Function()? storageRoot,
    DateTime Function()? now,
  }) : _storageRoot = storageRoot ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now;

  final Future<Database> Function() _database;
  final Future<Directory> Function() _storageRoot;
  final DateTime Function() _now;

  Map<int, String> _matches = const {};
  Map<String, String> _trackMatches = const {};
  Map<String, DateTime> _notFound = const {};
  Set<String> _removedVideos = const {};

  /// Whether YouTube no longer has [videoId] (playing or re-importing found out).
  bool isVideoRemoved(String videoId) =>
      _removedVideos.contains(videoId) ||
      _badVideos.everySong.contains(videoId);

  /// MusicDatabase turned [videoId] down for this song ([BadVideos.forSong]).
  bool isWrongFor(int mainDbId, String videoId) =>
      _badVideos.isWrongFor(mainDbId, videoId);

  // Kept in memory only: MusicDatabase takes a video off its list when the owner picks it, and
  // the phone must follow (a stored mark would outlive that).
  BadVideos _badVideos = BadVideos.none;

  /// The videos MusicDatabase found bad, from the music.db just loaded. The phone's own matches
  /// to them are forgotten, so those songs are searched again; returns how many.
  Future<int> useBadVideos(BadVideos bad) async {
    _badVideos = bad;
    final db = await _database();
    var forgotten = 0;
    await db.transaction((txn) async {
      for (final video in bad.everySong) {
        forgotten += await txn.delete(
          'youtube_matches',
          where: 'video_id = ?',
          whereArgs: [video],
        );
        forgotten += await txn.delete(
          'youtube_track_matches',
          where: 'video_id = ?',
          whereArgs: [video],
        );
      }
      for (final MapEntry(key: song, value: videos) in bad.forSong.entries) {
        for (final video in videos) {
          forgotten += await txn.delete(
            'youtube_matches',
            where: 'main_db_id = ? AND video_id = ?',
            whereArgs: [song, video],
          );
        }
      }
    });
    if (forgotten > 0) {
      _matches = {..._matches}
        ..removeWhere(
          (song, v) => bad.everySong.contains(v) || bad.isWrongFor(song, v),
        );
      _trackMatches = {..._trackMatches}
        ..removeWhere((_, v) => bad.everySong.contains(v));
    }
    notifyListeners();
    return forgotten;
  }

  // Kept in memory only: the outbox holds the corrections they come from (main.dart).
  Map<int, UserYouTubeLinks> _userLinks = const {};

  /// The YouTube links the user set for this MusicDatabase song, while music.db still has the
  /// value they correct.
  UserYouTubeLinks? userLinksFor(int mainDbId) => _userLinks[mainDbId];

  void useUserLinks(Map<int, UserYouTubeLinks> links) {
    if (mapEquals(links, _userLinks)) return;
    _userLinks = Map.unmodifiable(links);
    notifyListeners();
  }

  /// Every video found removed so far on the phone (not MusicDatabase's [useBadVideos]).
  Set<String> get removedVideos => Set.unmodifiable(_removedVideos);

  /// How long "not found on YouTube" holds before the queue searches again — the video may have
  /// been uploaded since. A tap on the song searches right away.
  static const notFoundFor = Duration(days: 30);
  Map<String, YouTubeCacheEntry> _cache = const {};
  final _downloading = <String>{};

  static const _chunkSize = 1024 * 1024;

  /// The video the phone found for this MusicDatabase song, if any.
  String? matchFor(int mainDbId) => _matches[mainDbId];

  /// MusicDatabase songs the phone found a video for.
  Iterable<int> get matchedSongIds => _matches.keys.toList();

  /// [matchFor] with the title and channel saved with it.
  Future<YouTubeVideo?> matchDetailsFor(int mainDbId) async {
    final rows = await (await _database()).query(
      'youtube_matches',
      where: 'main_db_id = ?',
      whereArgs: [mainDbId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return YouTubeVideo(
      id: row['video_id']! as String,
      title: row['video_title'] as String? ?? '',
      channel: row['channel'] as String? ?? '',
    );
  }

  /// The video the phone found for a track that isn't a MusicDatabase song, if any.
  String? matchForTrack(String artist, String title) =>
      _trackMatches[_trackKey(artist, title)];

  static String _trackKey(String artist, String title) =>
      '${normalizeForSearch(artist)}\n${normalizeForSearch(title)}';

  static String _songNotFoundKey(int mainDbId) => 'db:$mainDbId';
  static String _trackNotFoundKey(String artist, String title) =>
      'track:${_trackKey(artist, title)}';

  bool _isNotFound(String key) {
    final checked = _notFound[key];
    return checked != null && _now().difference(checked) < notFoundFor;
  }

  /// Whether the phone searched YouTube for this MusicDatabase song lately and found nothing.
  bool notFoundSong(int mainDbId) => _isNotFound(_songNotFoundKey(mainDbId));

  /// The same for a track that isn't a MusicDatabase song.
  bool notFoundTrack(String artist, String title) =>
      _isNotFound(_trackNotFoundKey(artist, title));

  /// Videos the phone found itself (MusicDatabase songs and tracks known only by name).
  int get phoneMatchCount => _matches.length + _trackMatches.length;

  /// Songs searched on YouTube lately without result (not yet expired).
  int get notFoundCount => _notFound.keys.where(_isNotFound).length;

  /// The MusicDatabase song the phone matched to this video, if any.
  int? songForVideo(String videoId) {
    for (final entry in _matches.entries) {
      if (entry.value == videoId) return entry.key;
    }
    return null;
  }

  int get cachedCount => _cache.length;
  int get cachedBytes =>
      _cache.values.fold(0, (sum, entry) => sum + entry.sizeBytes);

  Future<Directory> _cacheDir() async =>
      Directory('${(await _storageRoot()).path}/youtube_cache')
          .create(recursive: true);

  Future<void> load() async {
    final db = await _database();
    _matches = {
      for (final row in await db.query('youtube_matches'))
        row['main_db_id']! as int: row['video_id']! as String,
    };
    _trackMatches = {
      for (final row in await db.query('youtube_track_matches'))
        row['track_key']! as String: row['video_id']! as String,
    };
    _removedVideos = {
      for (final row in await db.query('youtube_removed_videos'))
        row['video_id']! as String,
    };
    await db.delete(
      'youtube_not_found',
      where: 'checked_at <= ?',
      whereArgs: [_now().subtract(notFoundFor).millisecondsSinceEpoch],
    );
    _notFound = {
      for (final row in await db.query('youtube_not_found'))
        row['not_found_key']! as String: DateTime.fromMillisecondsSinceEpoch(
          row['checked_at']! as int,
        ),
    };
    await _reloadCache(db);
    // Left over from plays that stopped before the download finished.
    await for (final file in (await _cacheDir()).list()) {
      if (file is File && file.path.endsWith('.part')) {
        await file.delete();
      }
    }
  }

  Future<void> _reloadCache(Database db) async {
    final dir = await _cacheDir();
    final entries = <String, YouTubeCacheEntry>{};
    for (final row in await db.query('youtube_cache')) {
      final entry = YouTubeCacheEntry(
        videoId: row['video_id']! as String,
        file: File('${dir.path}/${row['file_name']}'),
        sizeBytes: row['size_bytes']! as int,
        lastPlayed: DateTime.fromMillisecondsSinceEpoch(
          row['last_played_at']! as int,
        ),
      );
      if (await entry.file.exists()) {
        entries[entry.videoId] = entry;
      } else {
        await db.delete(
          'youtube_cache',
          where: 'video_id = ?',
          whereArgs: [entry.videoId],
        );
      }
    }
    _cache = entries;
    notifyListeners();
  }

  Future<void> saveMatch(int mainDbId, YouTubeVideo video) async {
    await (await _database()).insert('youtube_matches', {
      'main_db_id': mainDbId,
      'video_id': video.id,
      'video_title': video.title,
      'channel': video.channel,
      'matched_at': _now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _matches = {..._matches, mainDbId: video.id};
    await _clearNotFound(_songNotFoundKey(mainDbId));
    notifyListeners();
  }

  /// Remembers that searching YouTube for this song (MusicDatabase's [mainDbId], else [artist] +
  /// [title]) found no sure match.
  Future<void> saveNotFound({
    int? mainDbId,
    required String artist,
    required String title,
  }) async {
    final key = mainDbId != null
        ? _songNotFoundKey(mainDbId)
        : _trackNotFoundKey(artist, title);
    final now = _now();
    await (await _database()).insert('youtube_not_found', {
      'not_found_key': key,
      'artist': artist,
      'title': title,
      'checked_at': now.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _notFound = {..._notFound, key: now};
    notifyListeners();
  }

  /// YouTube no longer has [videoId]: remembered, the playlist tracks with it are marked
  /// (`playlist_tracks.youtube_removed`), and the phone's own matches to it are dropped — so the
  /// songs show a dimmed icon and are searched again.
  Future<void> markVideoRemoved(String videoId) async {
    final db = await _database();
    await db.transaction((txn) async {
      await txn.insert('youtube_removed_videos', {
        'video_id': videoId,
        'found_at': _now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _markPlaylistsChanged(txn, videoId);
      await txn.update(
        'playlist_tracks',
        {'youtube_removed': 1},
        where: 'youtube_video_id = ?',
        whereArgs: [videoId],
      );
      await txn.delete(
        'youtube_matches',
        where: 'video_id = ?',
        whereArgs: [videoId],
      );
      await txn.delete(
        'youtube_track_matches',
        where: 'video_id = ?',
        whereArgs: [videoId],
      );
    });
    _removedVideos = {..._removedVideos, videoId};
    _matches = {..._matches}..removeWhere((_, v) => v == videoId);
    _trackMatches = {..._trackMatches}..removeWhere((_, v) => v == videoId);
    notifyListeners();
  }

  /// Account playlists holding [videoId] go to MusicDatabase again (`playlist_library.dart`).
  static Future<void> _markPlaylistsChanged(
    DatabaseExecutor db,
    String videoId,
  ) => db.rawUpdate(
    '''UPDATE playlists SET dirty = 1
       WHERE account IS NOT NULL AND id IN (
         SELECT playlist_id FROM playlist_tracks WHERE youtube_video_id = ?)''',
    [videoId],
  );

  /// These videos are on YouTube after all (back in a playlist).
  Future<void> clearVideosRemoved(Iterable<String> videoIds) async {
    final back = videoIds.where(_removedVideos.contains).toSet();
    if (back.isEmpty) return;
    final db = await _database();
    for (final id in back) {
      await db.delete(
        'youtube_removed_videos',
        where: 'video_id = ?',
        whereArgs: [id],
      );
      await _markPlaylistsChanged(db, id);
      await db.update(
        'playlist_tracks',
        {'youtube_removed': 0},
        where: 'youtube_video_id = ?',
        whereArgs: [id],
      );
    }
    _removedVideos = {..._removedVideos}..removeAll(back);
    notifyListeners();
  }

  /// After a new `music.db`: drops what the phone worked out for MusicDatabase songs that
  /// MusicDatabase now settles itself — a video link or "N/A" ([settled]) — as its value wins
  /// anyway. Returns how many entries went.
  Future<int> forgetSettled(bool Function(int mainDbId) settled) async {
    final songs = _matches.keys.where(settled).toList();
    final notFound = [
      for (final key in _notFound.keys)
        if (key.startsWith('db:') && settled(int.parse(key.substring(3)))) key,
    ];
    if (songs.isEmpty && notFound.isEmpty) return 0;
    final db = await _database();
    await db.transaction((txn) async {
      for (final id in songs) {
        await txn.delete(
          'youtube_matches',
          where: 'main_db_id = ?',
          whereArgs: [id],
        );
      }
      for (final key in notFound) {
        await txn.delete(
          'youtube_not_found',
          where: 'not_found_key = ?',
          whereArgs: [key],
        );
      }
    });
    _matches = {..._matches}..removeWhere((id, _) => songs.contains(id));
    _notFound = {..._notFound}..removeWhere((key, _) => notFound.contains(key));
    notifyListeners();
    return songs.length + notFound.length;
  }

  /// Forgets every video the phone found itself, so the songs are searched again (e.g. with a
  /// better search method). Their cached audio stays until it's pushed out.
  Future<void> forgetPhoneMatches() async {
    final db = await _database();
    await db.delete('youtube_matches');
    await db.delete('youtube_track_matches');
    _matches = const {};
    _trackMatches = const {};
    notifyListeners();
  }

  /// Forgets every "not found on YouTube", so those songs are searched again.
  Future<void> forgetNotFound() async {
    await (await _database()).delete('youtube_not_found');
    _notFound = const {};
    notifyListeners();
  }

  Future<void> _clearNotFound(String key) async {
    if (!_notFound.containsKey(key)) return;
    await (await _database()).delete(
      'youtube_not_found',
      where: 'not_found_key = ?',
      whereArgs: [key],
    );
    _notFound = {..._notFound}..remove(key);
  }

  Future<void> saveTrackMatch(
    String artist,
    String title,
    YouTubeVideo video,
  ) async {
    final key = _trackKey(artist, title);
    await (await _database()).insert('youtube_track_matches', {
      'track_key': key,
      'artist': artist,
      'title': title,
      'video_id': video.id,
      'video_title': video.title,
      'channel': video.channel,
      'matched_at': _now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _trackMatches = {..._trackMatches, key: video.id};
    await _clearNotFound(_trackNotFoundKey(artist, title));
    notifyListeners();
  }

  /// The complete cached audio of [videoId], marked as just played; `null` when not cached.
  Future<File?> cachedFile(String videoId) async {
    final entry = _cache[videoId];
    if (entry == null) return null;
    if (!await entry.file.exists()) {
      await _reloadCache(await _database());
      return null;
    }
    final now = _now();
    await (await _database()).update(
      'youtube_cache',
      {'last_played_at': now.millisecondsSinceEpoch},
      where: 'video_id = ?',
      whereArgs: [videoId],
    );
    _cache = {
      ..._cache,
      videoId: YouTubeCacheEntry(
        videoId: videoId,
        file: entry.file,
        sizeBytes: entry.sizeBytes,
        lastPlayed: now,
      ),
    };
    return entry.file;
  }

  /// Whether [videoId]'s audio is in the cache (without marking it played).
  bool isCached(String videoId) => _cache.containsKey(videoId);

  /// Where a new download of [videoId] should be written.
  Future<File> newCacheFile(String videoId, String extension) async =>
      File('${(await _cacheDir()).path}/$videoId.$extension');

  /// Saves [url]'s audio as [videoId]'s cache file and records it, dropping the least recently
  /// played beyond [limit]. Failures only leave nothing cached; playback doesn't depend on it.
  /// Returns whether the audio is cached now (or being downloaded already).
  Future<bool> download(
    String videoId,
    String url,
    String extension,
    int limit,
  ) async {
    if (_cache.containsKey(videoId) || !_downloading.add(videoId)) return true;
    final file = await newCacheFile(videoId, extension);
    final part = File('${file.path}.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      // Not openWrite(): its errors (e.g. the cache folder deleted meanwhile) escape the
      // try/catch, and a failed download must never crash anything.
      final out = await part.open(mode: FileMode.write);
      try {
        var offset = 0;
        int? total;
        while (true) {
          final request = await client.getUrl(Uri.parse(url));
          request.headers.set(
            HttpHeaders.rangeHeader,
            'bytes=$offset-${offset + _chunkSize - 1}',
          );
          final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
          final partial = response.statusCode == HttpStatus.partialContent;
          if (!partial && response.statusCode != HttpStatus.ok) {
            throw HttpException('HTTP ${response.statusCode}');
          }
          total ??= _totalLength(response.headers.value('content-range'));
          var received = 0;
          await for (final chunk in response.timeout(
            const Duration(seconds: 20),
          )) {
            await out.writeFrom(chunk);
            received += chunk.length;
          }
          offset += received;
          // A server ignoring Range sends everything at once; a short chunk is the last one.
          if (!partial ||
              received < _chunkSize ||
              (total != null && offset >= total)) {
            break;
          }
        }
      } finally {
        await out.close();
      }
      await part.rename(file.path);
      await cacheComplete(videoId, file, limit);
      return true;
    } catch (e) {
      debugPrint('Caching YouTube audio $videoId failed: $e');
      if (await part.exists()) await part.delete();
      return false;
    } finally {
      client.close(force: true);
      _downloading.remove(videoId);
    }
  }

  /// "bytes 0-1048575/3886372" → 3886372.
  static int? _totalLength(String? contentRange) {
    final slash = contentRange?.lastIndexOf('/') ?? -1;
    return slash < 0 ? null : int.tryParse(contentRange!.substring(slash + 1));
  }

  /// Records a finished download and drops the least recently played files beyond [limit].
  Future<void> cacheComplete(String videoId, File file, int limit) async {
    if (!await file.exists()) return;
    final db = await _database();
    final now = _now().millisecondsSinceEpoch;
    await db.insert('youtube_cache', {
      'video_id': videoId,
      'file_name': file.uri.pathSegments.last,
      'size_bytes': await file.length(),
      'downloaded_at': now,
      'last_played_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _reloadCache(db);
    await trim(limit);
  }

  /// Deletes the least recently played files until at most [limit] are left.
  Future<void> trim(int limit) async {
    final byAge = _cache.values.toList()
      ..sort((a, b) => a.lastPlayed.compareTo(b.lastPlayed));
    final excess = byAge.length - limit;
    if (excess <= 0) return;
    for (final entry in byAge.take(excess)) {
      await _remove(entry);
    }
    await _reloadCache(await _database());
  }

  /// The cached songs, most recently played first.
  List<YouTubeCacheEntry> get cacheEntries =>
      _cache.values.toList()
        ..sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));

  /// Title and artist the phone has seen for each of [videoIds] — in a playlist, the history or
  /// a match it found — for videos MusicDatabase doesn't know.
  Future<Map<String, ({String title, String? artist})>> knownTitles(
    Iterable<String> videoIds,
  ) async {
    final ids = videoIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final marks = List.filled(ids.length, '?').join(', ');
    final db = await _database();
    final found = <String, ({String title, String? artist})>{};
    for (final query in [
      'SELECT youtube_video_id AS id, title, artist FROM playlist_tracks '
          'WHERE youtube_video_id IN ($marks)',
      'SELECT youtube_video_id AS id, title, artist FROM play_history '
          'WHERE youtube_video_id IN ($marks)',
      'SELECT video_id AS id, title, artist FROM youtube_track_matches '
          'WHERE video_id IN ($marks)',
      'SELECT video_id AS id, video_title AS title, channel AS artist FROM youtube_matches '
          'WHERE video_id IN ($marks)',
    ]) {
      for (final row in await db.rawQuery(query, ids)) {
        final title = row['title'] as String?;
        if (title == null) continue;
        found.putIfAbsent(
          row['id']! as String,
          () => (title: title, artist: row['artist'] as String?),
        );
      }
    }
    return found;
  }

  /// Deletes one song's cached audio.
  Future<void> removeFromCache(String videoId) async {
    final entry = _cache[videoId];
    if (entry == null) return;
    await _remove(entry);
    await _reloadCache(await _database());
  }

  Future<void> clearCache() async {
    for (final entry in _cache.values.toList()) {
      await _remove(entry);
    }
    await _reloadCache(await _database());
  }

  Future<void> _remove(YouTubeCacheEntry entry) async {
    for (final path in [entry.file.path, '${entry.file.path}.mime']) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await (await _database()).delete(
      'youtube_cache',
      where: 'video_id = ?',
      whereArgs: [entry.videoId],
    );
  }
}

/// Makes the [YouTubeLibrary] reachable from any screen.
class YouTubeLibraryScope extends InheritedNotifier<YouTubeLibrary> {
  const YouTubeLibraryScope({
    super.key,
    required YouTubeLibrary super.notifier,
    required super.child,
  });

  static YouTubeLibrary of(BuildContext context) => maybeOf(context)!;

  static YouTubeLibrary? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<YouTubeLibraryScope>()
      ?.notifier;
}
