import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import '../data/combined_search.dart';
import '../data/server_downloads.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import 'download_notification.dart';
import 'track_player.dart';

/// How much of a list of songs "Pobierz" has kept on the phone.
enum DownloadState { none, some, all }

/// "Pobierz" for the screens: a song or a whole playlist kept on the phone for good
/// ([TrackPlayer.download]), what's waiting or downloading now, and taking songs off again.
/// Songs on the phone already count as downloaded.
///
/// The songs waiting are kept in `local.db`'s `download_queue`, so a download Android stopped
/// (the app frozen or killed in the background) carries on with [resume] when the app is back;
/// a song that failed [maxAttempts] times is given up. While it works, [DownloadNotification]
/// keeps a foreground service up, so Android lets it run with the screen off.
class Downloads extends ChangeNotifier {
  Downloads(
    this._tracks,
    this._server,
    this._youTube, {
    required this._database,
    required this._resolve,
    this._notification = const DownloadNotification(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _server.addListener(notifyListeners);
    _youTube.addListener(notifyListeners);
  }

  /// Runs (each start or return to the app) a song gets before it's dropped from the queue.
  static const maxAttempts = 3;

  final TrackPlayer _tracks;
  final ServerDownloads _server;
  final YouTubeLibrary _youTube;
  final Future<Database> Function() _database;
  final SearchHit Function(TrackRef) _resolve;
  final DownloadNotification _notification;
  final DateTime Function() _now;

  /// [TrackRef.key]s waiting in the queue.
  Set<String> _queued = const {};
  Future<void>? _running;

  /// Screens waiting for a song's turn in this run: whether it was downloaded.
  final _waiting = <String, Completer<bool>>{};

  static String _key(SearchHit hit) => TrackRef.of(hit).key;

  /// Kept on the phone: its own file, a downloaded server file or pinned YouTube audio.
  bool isDownloaded(SearchHit hit) => hit.onPhone || _tracks.isDownloaded(hit);

  /// Waiting in the queue or downloading now.
  bool isDownloading(SearchHit hit) => _queued.contains(_key(hit));

  bool isDownloadingAny(Iterable<SearchHit> hits) => hits.any(isDownloading);

  DownloadState stateOf(Iterable<SearchHit> hits) {
    final list = hits.toList();
    if (list.isEmpty) return DownloadState.none;
    final done = list.where(isDownloaded).length;
    return done == 0
        ? DownloadState.none
        : done == list.length
        ? DownloadState.all
        : DownloadState.some;
  }

  /// Queues [hits] not on the phone yet and waits for them; returns how many couldn't be
  /// downloaded this time (they stay queued for the next run until their tries are used up).
  Future<int> download(List<SearchHit> hits) async {
    final db = await _database();
    final wanted = <String>[];
    for (final hit in hits) {
      if (isDownloaded(hit)) continue;
      final ref = TrackRef.of(hit);
      wanted.add(ref.key);
      await db.insert('download_queue', {
        'track_key': ref.key,
        'track': jsonEncode(ref.toJson()),
        'added_at': _now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (wanted.isEmpty) return 0;
    _queued = {..._queued, ...wanted};
    final results = [
      for (final key in wanted) (_waiting[key] ??= Completer<bool>()).future,
    ];
    notifyListeners();
    // Already running: it picks the new rows up, since it reads the queue before each song.
    unawaited(resume());
    return (await Future.wait(results)).where((ok) => !ok).length;
  }

  /// Downloads whatever waits in the queue, one song at a time. Called on start, when the app
  /// comes back, and by [download].
  Future<void> resume() => _running ??= _run().whenComplete(() {
    _running = null;
  });

  Future<void> _run() async {
    final db = await _database();
    final tried = <String>{};
    var done = 0;
    try {
      while (true) {
        final rows = await db.query('download_queue', orderBy: 'added_at');
        _queued = {for (final r in rows) r['track_key']! as String};
        final row = rows
            .where((r) => !tried.contains(r['track_key']))
            .firstOrNull;
        if (row == null) break;
        final key = row['track_key']! as String;
        tried.add(key);
        final hit = _resolve(
          TrackRef.fromJson(
            (jsonDecode(row['track']! as String) as Map).cast(),
          ),
        );
        await _notification.show(
          done: done,
          total: done + rows.length - (tried.length - 1 - done),
          title: hit.title,
        );
        var ok = false;
        try {
          ok = await _tracks.download(hit) != DownloadOutcome.failed;
        } catch (e) {
          debugPrint('Downloading "${hit.title}" failed: $e');
        }
        final attempts = (row['attempts']! as int) + 1;
        if (ok || attempts >= maxAttempts) {
          await db.delete(
            'download_queue',
            where: 'track_key = ?',
            whereArgs: [key],
          );
        } else {
          await db.update(
            'download_queue',
            {'attempts': attempts},
            where: 'track_key = ?',
            whereArgs: [key],
          );
        }
        if (ok) done++;
        _waiting.remove(key)?.complete(ok);
        notifyListeners();
      }
    } finally {
      await _notification.hide();
      for (final waiting in _waiting.values) {
        if (!waiting.isCompleted) waiting.complete(false);
      }
      _waiting.clear();
      _queued = {
        for (final r in await db.query('download_queue'))
          r['track_key']! as String,
      };
      notifyListeners();
    }
  }

  /// The audio of [hit] the phone has apart from its own files — a downloaded server file or
  /// YouTube audio in the cache (downloaded or just played) — for "Udostępnij › Plik".
  File? fileOf(SearchHit hit) {
    if (hit.serverFile case final server?) {
      for (final download in _server.entries) {
        if (download.fileId == server.id) return download.file;
      }
    }
    final videoId = hit.youtubeVideoId;
    return videoId == null ? null : _youTube.cachedFileOf(videoId);
  }

  /// How many songs "Pobierz" keeps, and how much room they take.
  int get count => _server.entries.length + _youTube.pinnedEntries.length;
  int get bytes =>
      _server.totalBytes +
      _youTube.pinnedEntries.fold(0, (sum, e) => sum + e.sizeBytes);

  /// "Usuń wszystkie pobrane": server copies deleted, YouTube audio back in the cache.
  Future<void> removeAll() async {
    await (await _database()).delete('download_queue');
    _queued = const {};
    for (final download in _server.entries) {
      await _server.remove(download.fileId);
    }
    for (final entry in _youTube.pinnedEntries) {
      await _youTube.setPinned(
        entry.videoId,
        false,
        limit: _tracks.settings.cacheKeep,
      );
    }
  }

  /// Takes [hits] off the phone again (a file of the phone's own stays, of course).
  Future<void> remove(List<SearchHit> hits) async {
    final db = await _database();
    for (final hit in hits) {
      await db.delete(
        'download_queue',
        where: 'track_key = ?',
        whereArgs: [_key(hit)],
      );
      _queued = {..._queued}..remove(_key(hit));
      await _tracks.removeDownload(hit);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _server.removeListener(notifyListeners);
    _youTube.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Makes [Downloads] reachable from any screen; absent in tests that don't need it.
class DownloadsScope extends InheritedNotifier<Downloads> {
  const DownloadsScope({
    super.key,
    required Downloads super.notifier,
    required super.child,
  });

  static Downloads? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DownloadsScope>()?.notifier;
}
