import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

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
  Map<String, YouTubeCacheEntry> _cache = const {};
  final _downloading = <String>{};

  static const _chunkSize = 1024 * 1024;

  /// The video the phone found for this MusicDatabase song, if any.
  String? matchFor(int mainDbId) => _matches[mainDbId];

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

  static YouTubeLibrary of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<YouTubeLibraryScope>()!
      .notifier!;
}
