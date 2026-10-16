import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'playlist_sync.dart';

/// Where a listened song played from.
enum ListenSource { phone, server, youtube }

/// One song that started playing, with how long it was really listened to: the listening
/// stats' raw data (`listens` in `local.db`).
class Listen {
  const Listen({
    required this.uid,
    required this.startedAt,
    required this.title,
    required this.source,
    this.account,
    this.listened = Duration.zero,
    this.duration,
    this.artist,
    this.album,
    this.songId,
    this.youtubeVideoId,
    this.spotifyTrackId,
    this.playlistUid,
    this.playlistName,
    this.moodUid,
    this.globalMoodId,
    this.moodName,
  });

  final String uid;
  final String? account;
  final DateTime startedAt;

  /// Time it was heard: the song's position moving on while playing, so a skip forward or a
  /// pause doesn't count.
  final Duration listened;
  final Duration? duration;
  final String title;
  final String? artist;
  final String? album;

  /// music.db's `songs.id`.
  final int? songId;
  final String? youtubeVideoId;
  final String? spotifyTrackId;
  final ListenSource source;
  final String? playlistUid;
  final String? playlistName;

  /// The mood it played from: the user's own ([moodUid], `moods.uid`) or a global one
  /// ([globalMoodId], tag.db's `tags.id`).
  final String? moodUid;
  final int? globalMoodId;
  final String? moodName;

  Listen copyWith({Duration? listened, Duration? duration, String? account}) =>
      Listen(
        uid: uid,
        account: account ?? this.account,
        startedAt: startedAt,
        listened: listened ?? this.listened,
        duration: duration ?? this.duration,
        title: title,
        artist: artist,
        album: album,
        songId: songId,
        youtubeVideoId: youtubeVideoId,
        spotifyTrackId: spotifyTrackId,
        source: source,
        playlistUid: playlistUid,
        playlistName: playlistName,
        moodUid: moodUid,
        globalMoodId: globalMoodId,
        moodName: moodName,
      );

  Map<String, Object?> toRow() => {
    'uid': uid,
    'account': account,
    'started_at': startedAt.millisecondsSinceEpoch,
    'listened_ms': listened.inMilliseconds,
    'duration_ms': duration?.inMilliseconds,
    'title': title,
    'artist': artist,
    'album': album,
    'song_id': songId,
    'youtube_video_id': youtubeVideoId,
    'spotify_track_id': spotifyTrackId,
    'source': source.name,
    'playlist_uid': playlistUid,
    'playlist_name': playlistName,
    'mood_uid': moodUid,
    'global_mood_id': globalMoodId,
    'mood_name': moodName,
  };

  /// As MusicDatabase gets it (`docs/handoffs/musicdatabase-listening-stats.md`).
  Map<String, Object?> toWire() => {...toRow()..remove('account')};

  static Listen fromRow(Map<String, Object?> row) => Listen(
    uid: row['uid']! as String,
    account: row['account'] as String?,
    startedAt: DateTime.fromMillisecondsSinceEpoch(row['started_at']! as int),
    listened: Duration(milliseconds: row['listened_ms'] as int? ?? 0),
    duration: switch (row['duration_ms']) {
      final int ms => Duration(milliseconds: ms),
      _ => null,
    },
    title: row['title'] as String? ?? '',
    artist: row['artist'] as String?,
    album: row['album'] as String?,
    songId: row['song_id'] as int?,
    youtubeVideoId: row['youtube_video_id'] as String?,
    spotifyTrackId: row['spotify_track_id'] as String?,
    source:
        ListenSource.values.where((s) => s.name == row['source']).firstOrNull ??
        ListenSource.phone,
    playlistUid: row['playlist_uid'] as String?,
    playlistName: row['playlist_name'] as String?,
    moodUid: row['mood_uid'] as String?,
    globalMoodId: row['global_mood_id'] as int?,
    moodName: row['mood_name'] as String?,
  );
}

/// Every play kept for the listening stats (Ja › Statystyki słuchania), counted from the
/// version that brought it; unlike `PlayHistory` ("Ostatnie") never cut down. Synced with the
/// logged-in MusicDatabase account by [sync] (`/users/<name>/listens`,
/// [ADR 0012](../../../docs/decisions/0012-listening-stats.md)): plays are only ever added or
/// listened to longer, so the longer time wins and nothing conflicts. Plays made while nobody
/// is logged in go to the next account that logs in.
class ListeningLog extends ChangeNotifier {
  ListeningLog(
    this._database, {
    String? Function()? userName,
    String? Function()? authToken,
    DateTime Function()? now,
  }) : _userName = userName ?? (() => null),
       _authToken = authToken ?? (() => null),
       _now = now ?? DateTime.now;

  /// The listened time of the current play is written after this much more of it (and when it
  /// ends, or the app goes to the background), so a killed app loses little.
  static const saveEvery = Duration(seconds: 30);

  /// Plays per request to MusicDatabase.
  static const batchSize = 500;

  /// A sync is asked for ([onManyUnsent]) once this many plays wait to be sent.
  static const unsentForSync = 20;

  final Future<Database> Function() _database;
  final String? Function() _userName;
  final String? Function() _authToken;
  final DateTime Function() _now;

  /// MusicDatabase no longer accepts the login.
  VoidCallback? onUnauthorized;

  /// Enough plays wait to go to MusicDatabase.
  VoidCallback? onManyUnsent;

  Listen? _current;
  Duration _saved = Duration.zero;
  int _finishedSinceSync = 0;

  /// Writes to `local.db` go one after another, in the order plays switch in memory.
  Future<void> _writes = Future.value();

  Future<void> _write(Future<void> Function(Database db) write) {
    final done = _writes.then((_) async => write(await _database()));
    _writes = done.catchError((Object _) {});
    return done;
  }

  /// The play going on now (its listened time may be ahead of the database).
  Listen? get current => _current;

  /// Starts a new play (the one before ends); returns its uid.
  Future<String> start({
    required String title,
    required ListenSource source,
    String? artist,
    String? album,
    int? songId,
    String? youtubeVideoId,
    String? spotifyTrackId,
    String? playlistUid,
    String? playlistName,
    String? moodUid,
    int? globalMoodId,
    String? moodName,
    Duration? duration,
  }) async {
    final ended = finish();
    final listen = _current = Listen(
      uid: newPlaylistUid(),
      account: _userName(),
      startedAt: _now(),
      title: title,
      artist: artist,
      album: album,
      songId: songId,
      youtubeVideoId: youtubeVideoId,
      spotifyTrackId: spotifyTrackId,
      source: source,
      playlistUid: playlistUid,
      playlistName: playlistName,
      moodUid: moodUid,
      globalMoodId: globalMoodId,
      moodName: moodName,
      duration: duration,
    );
    _saved = Duration.zero;
    final inserted = _write((db) => db.insert('listens', listen.toRow()));
    notifyListeners();
    await ended;
    await inserted;
    return listen.uid;
  }

  /// [step] more of the current play was heard; [duration]: the song's length, once known.
  Future<void> listened(Duration step, {Duration? duration}) async {
    final listen = _current;
    if (listen == null) return;
    final now = _current = listen.copyWith(
      listened: listen.listened + step,
      duration: duration,
    );
    if (now.listened - _saved >= saveEvery) await save();
  }

  /// Writes the current play's listened time.
  Future<void> save() {
    final listen = _current;
    if (listen == null) return Future.value();
    _saved = listen.listened;
    return _saveListened(listen);
  }

  Future<void> _saveListened(Listen listen) => _write(
    (db) => db.update(
      'listens',
      {
        'listened_ms': listen.listened.inMilliseconds,
        'duration_ms': listen.duration?.inMilliseconds,
      },
      where: 'uid = ?',
      whereArgs: [listen.uid],
    ),
  );

  /// The current play ended (another started, or nothing plays any more).
  Future<void> finish() {
    final listen = _current;
    if (listen == null) return Future.value();
    _current = null;
    if (++_finishedSinceSync >= unsentForSync) {
      _finishedSinceSync = 0;
      onManyUnsent?.call();
    }
    return _saveListened(listen);
  }

  /// The plays of [account] (and of nobody's, not sent yet) started from [from] to before [to],
  /// oldest first; the current one with its listened time so far.
  Future<List<Listen>> listens({
    required String? account,
    DateTime? from,
    DateTime? to,
  }) async {
    await _writes;
    final where = [
      account == null ? 'account IS NULL' : '(account = ? OR account IS NULL)',
      if (from != null) 'started_at >= ?',
      if (to != null) 'started_at < ?',
    ];
    final rows = await (await _database()).query(
      'listens',
      where: where.join(' AND '),
      whereArgs: [
        ?account,
        if (from != null) from.millisecondsSinceEpoch,
        if (to != null) to.millisecondsSinceEpoch,
      ],
      orderBy: 'started_at, uid',
    );
    final current = _current;
    return [
      for (final row in rows)
        if (current != null && row['uid'] == current.uid)
          current
        else
          Listen.fromRow(row),
    ];
  }

  bool _syncing = false;
  bool _syncAgain = false;
  PlaylistSyncResult? _lastSync;

  bool get syncing => _syncing;

  /// How the last [sync] went; `null` before the first one.
  PlaylistSyncResult? get lastSync => _lastSync;

  static String _revisionKey(String user) => 'listens.sync_revision.$user';

  /// Exchanges plays with the logged-in account on the first of [servers] that answers: the
  /// ones other phones sent first, then this phone's new ones and longer listened times.
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
      notifyListeners();
    }
  }

  Future<String?> _syncWith(
    List<Uri> servers,
    String user,
    String token,
  ) async {
    String? problem;
    for (final server in servers) {
      final client = PlaylistSyncClient(
        server,
        user,
        token,
        collection: 'listens',
      );
      try {
        return await _syncOn(client, user);
      } on _SyncStopped catch (e) {
        return e.problem;
      } catch (e) {
        debugPrint('Listening stats sync on $server failed: $e');
        problem = 'Brak połączenia z serwerem MusicDatabase';
      } finally {
        client.close();
      }
    }
    return problem;
  }

  Future<String?> _syncOn(PlaylistSyncClient client, String user) async {
    await _writes;
    final db = await _database();
    await db.update('listens', {'account': user}, where: 'account IS NULL');
    if (_current case final current? when current.account == null) {
      _current = current.copyWith(account: user);
    }

    final prefs = await SharedPreferences.getInstance();
    final known = prefs.getInt(_revisionKey(user)) ?? 0;
    var since = known;
    var restarted = false;
    while (true) {
      final changes = _check(
        await client.changedSince(since, limit: batchSize),
      );
      final revision = changes['revision']! as int;
      // The counter went back (the account's data was restored or made again): fetch it all.
      if (!restarted && since == known && revision < known) {
        restarted = true;
        since = 0;
        continue;
      }
      await _store(db, changes['listens']! as List, user);
      since = revision;
      await prefs.setInt(_revisionKey(user), since);
      if (changes['more'] != true) break;
    }
    notifyListeners();

    while (true) {
      final rows = await db.query(
        'listens',
        where: 'account = ? AND (sent_ms IS NULL OR sent_ms < listened_ms)',
        whereArgs: [user],
        orderBy: 'started_at, uid',
        limit: batchSize,
      );
      if (rows.isEmpty) return null;
      final current = _current;
      final listens = [
        for (final row in rows)
          if (current != null && row['uid'] == current.uid)
            current
          else
            Listen.fromRow(row),
      ];
      _check(
        await client.post({
          'listens': [for (final l in listens) l.toWire()],
        }),
      );
      final batch = db.batch();
      for (final listen in listens) {
        batch.rawUpdate(
          'UPDATE listens SET sent_ms = MAX(COALESCE(sent_ms, 0), ?) WHERE uid = ?',
          [listen.listened.inMilliseconds, listen.uid],
        );
      }
      await batch.commit(noResult: true);
      if (rows.length < batchSize) return null;
    }
  }

  /// Plays from MusicDatabase: new ones added, known ones heard longer elsewhere updated.
  Future<void> _store(Database db, List<Object?> remote, String user) async {
    if (remote.isEmpty) return;
    final batch = db.batch();
    for (final item in remote) {
      if (item is! Map<String, Object?> || item['uid'] is! String) continue;
      final ms = item['listened_ms'] as int? ?? 0;
      final listen = Listen.fromRow({...item, 'account': user});
      batch.insert('listens', {
        ...listen.toRow(),
        'sent_ms': ms,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      batch.rawUpdate(
        'UPDATE listens SET listened_ms = MAX(listened_ms, ?), '
        'sent_ms = MAX(COALESCE(sent_ms, 0), ?), '
        'duration_ms = COALESCE(duration_ms, ?) WHERE uid = ?',
        [ms, ms, item['duration_ms'], listen.uid],
      );
    }
    await batch.commit(noResult: true);
    final current = _current;
    if (current == null) return;
    for (final item in remote) {
      if (item is Map && item['uid'] == current.uid) {
        final ms = item['listened_ms'] as int? ?? 0;
        _current = current.copyWith(
          listened: Duration(
            milliseconds: max(ms, current.listened.inMilliseconds),
          ),
        );
      }
    }
  }

  /// The answer's JSON, or throws [_SyncStopped] with why the sync can't go on.
  Map<String, Object?> _check(SyncAnswer answer) {
    final body = answer.body;
    switch (answer.status) {
      case HttpStatus.ok when body is Map<String, Object?>:
        return body;
      case HttpStatus.unauthorized:
        onUnauthorized?.call();
        throw const _SyncStopped(
          'Serwer nie przyjął logowania — zaloguj się ponownie (Ustawienia › Konto)',
        );
      case HttpStatus.serviceUnavailable:
        throw const _SyncStopped(
          'Serwer MusicDatabase nie może teraz zapisać statystyk (dysk niepodłączony lub '
          'baza użytkownika jeszcze nieprzygotowana)',
        );
      case HttpStatus.notFound:
        throw const _SyncStopped(
          'Serwer MusicDatabase nie obsługuje jeszcze statystyk słuchania',
        );
    }
    throw _SyncStopped('Serwer odrzucił statystyki (HTTP ${answer.status})');
  }
}

/// An answer that ends a [ListeningLog.sync] early, with why (Polish, for display).
class _SyncStopped implements Exception {
  const _SyncStopped(this.problem);

  final String problem;
}

/// Makes the [ListeningLog] reachable from any screen.
class ListeningLogScope extends InheritedNotifier<ListeningLog> {
  const ListeningLogScope({
    super.key,
    required ListeningLog super.notifier,
    required super.child,
  });

  /// `null` in widget tests that don't set it up.
  static ListeningLog? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ListeningLogScope>()?.notifier;
}
