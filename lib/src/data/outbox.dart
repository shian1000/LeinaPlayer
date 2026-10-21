import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'song_catalog.dart';
import 'song_requests.dart';
import 'text_normalizer.dart';
import 'youtube_video.dart';

/// Requests for MusicDatabase, waiting on the phone until it can hand them over
/// ([ADR 0005](../../../docs/decisions/0005-outbox-for-musicdatabase.md)). Each request is a small
/// SQLite file in `<support dir>/outbox/`, named `[<user>_]<date>_<time>_<number>.db` — no user
/// part while the app has no user name. Its tables mirror music.db's where they can (song ids
/// are `songs.id`); the format is described in
/// `docs/handoffs/musicdatabase-outbox.md` for the MusicDatabase side.
///
/// New findings go into the newest request waiting in the outbox (a request holds one song or
/// many). [send] hands the waiting requests to MusicDatabase's inbox (`PUT /inbox/<name>` on the
/// sharing server — MusicDatabase's `docs/handoffs/inbox-for-musicdatabaseapp.md`); a received
/// one moves to `outbox/sent/`, so the next finding starts a new request. One the server refuses
/// as malformed moves to `outbox/rejected/` and isn't sent again. Both folders are kept: they
/// stop a link from being reported twice and a number from being reused. Without a server, the
/// waiting requests go as a `.zip` package through the share sheet ([exportPackage],
/// [ADR 0014](../../../docs/decisions/0014-github-database-and-request-packages.md)) and count
/// as sent the same way.
class Outbox extends ChangeNotifier {
  Outbox({
    Future<Directory> Function()? storageRoot,
    this.factoryOverride,
    DateTime Function()? now,
    String? Function()? userName,
    String? Function()? authToken,
  }) : _storageRoot = storageRoot ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now,
       _userName = userName ?? (() => null),
       _authToken = authToken ?? (() => null);

  /// Version of the request file layout, stored in each file's `request` table.
  static const format = 1;

  final Future<Directory> Function() _storageRoot;
  final DateTime Function() _now;
  final String? Function() _userName;

  /// The logged-in user's token ([Account]), sent with each request so MusicDatabase knows who
  /// sent it; `null` sends without one.
  final String? Function() _authToken;

  /// The server didn't accept [_authToken] (HTTP 401): the user has to log in again.
  VoidCallback? onUnauthorized;

  /// SQLite implementation to use instead of sqflite's global one (tests use FFI).
  final DatabaseFactory? factoryOverride;

  // Playing and caching ahead may report at the same time, and a send may be under way; one
  // at a time keeps two reports from both starting a new request file, and a report from
  // writing into a file while it's being sent.
  Future<void> _writes = Future.value();

  int _waiting = 0;
  bool _sending = false;
  OutboxSendResult? _lastSend;

  /// Requests waiting to be sent (as of the last report, send or [refresh]).
  int get waiting => _waiting;
  bool get sending => _sending;

  /// How the last [send] went; `null` before the first one.
  OutboxSendResult? get lastSend => _lastSend;

  static const _autoSendKey = 'outbox.auto_send';
  static const _heldOnKey = 'outbox.held_on_ms';
  static const _packageSenderKey = 'outbox.package_sender';
  static const _lastPackageKey = 'outbox.last_package';

  String? _typedSender;
  List<String> _lastPackage = const [];

  bool _autoSend = true;
  DateTime? _heldOn;

  /// Whether requests go to MusicDatabase by themselves ("Wysyłaj zgłoszenia automatycznie");
  /// off, they wait for "Wyślij teraz".
  bool get autoSend => _autoSend;

  /// The server refused to take requests today (inbox full, its drive not mounted): automatic
  /// sending waits for tomorrow — the next daily download — or a manual send.
  bool get heldForToday {
    final held = _heldOn;
    if (held == null) return false;
    final now = _now();
    return held.year == now.year &&
        held.month == now.month &&
        held.day == now.day;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _autoSend = prefs.getBool(_autoSendKey) ?? true;
    final held = prefs.getInt(_heldOnKey);
    _heldOn = held == null ? null : DateTime.fromMillisecondsSinceEpoch(held);
    _typedSender = prefs.getString(_packageSenderKey);
    _lastPackage = prefs.getStringList(_lastPackageKey) ?? const [];
    await refresh();
  }

  Future<void> setAutoSend(bool value) async {
    _autoSend = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_autoSendKey, value);
  }

  Future<void> _setHeld(DateTime? day) async {
    _heldOn = day;
    final prefs = await SharedPreferences.getInstance();
    await (day == null
        ? prefs.remove(_heldOnKey)
        : prefs.setInt(_heldOnKey, day.millisecondsSinceEpoch));
  }

  /// Called after a new finding was reported, e.g. to try sending it right away.
  VoidCallback? onReported;

  Future<void> refresh() async {
    _waiting = (await pending()).length;
    await _inTurn(_loadCorrections);
    notifyListeners();
  }

  Future<Directory> directory() async =>
      Directory('${(await _storageRoot()).path}/outbox')
          .create(recursive: true);

  /// The requests waiting to be sent, oldest first.
  Future<List<File>> pending() async {
    final files = [
      await for (final f in (await directory()).list())
        if (f is File && _requestName.hasMatch(_baseName(f.path))) f,
    ];
    files.sort((a, b) => _number(a.path).compareTo(_number(b.path)));
    return files;
  }

  /// The dead links reported in the requests waiting to be sent, in the order they were found.
  Future<List<DeadLinkReport>> waitingReports() => _inTurn(() async {
    final factory = factoryOverride ?? databaseFactory;
    final reports = <DeadLinkReport>[];
    for (final file in await pending()) {
      final db = await factory.openDatabase(
        file.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        if (!await _hasTable(db, _deadLinks)) continue;
        for (final row in await db.query(_deadLinks)) {
          reports.add(DeadLinkReport._fromRow(row));
        }
      } finally {
        await db.close();
      }
    }
    // Parsed: across a change of summer time the offsets differ.
    DateTime when(DeadLinkReport r) =>
        DateTime.tryParse(r.detectedAt) ?? DateTime(0);
    reports.sort((a, b) => when(a).compareTo(when(b)));
    return reports;
  });

  /// YouTube no longer plays music.db's link [deadVideoId] of [song]. Reported once: a link
  /// already in a request (waiting or sent) isn't added again. Returns whether it was added now.
  Future<bool> reportDeadYouTubeLink(CatalogSong song, String deadVideoId) =>
      _write(
        (db) async => db.insert('dead_youtube_links', {
          'song_id': song.id,
          'title': song.title,
          'artist': song.artistLabel,
          'dead_video_id': deadVideoId,
          'detected_at': _timestamp(_now()),
        }, conflictAlgorithm: ConflictAlgorithm.ignore),
        unless: () =>
            _reported(_deadLinks, 'dead_video_id', song.id, deadVideoId),
      );

  /// The phone found [video] for [song], which music.db has no link for — a suggestion for
  /// MusicDatabase, not a decision. Reported once: a video already in a request (waiting or
  /// sent) for the song isn't added again. Returns whether it was added now.
  Future<bool> reportFoundYouTubeLink(CatalogSong song, YouTubeVideo video) =>
      _write(
        (db) async => db.insert(_foundLinks, {
          'song_id': song.id,
          'title': song.title,
          'artist': song.artistLabel,
          'video_id': video.id,
          'video_title': video.title,
          'video_channel': video.channel,
          'found_at': _timestamp(_now()),
        }, conflictAlgorithm: ConflictAlgorithm.ignore),
        unless: () => _reported(_foundLinks, 'video_id', song.id, video.id),
        table: _foundLinks,
      );

  /// The phone plays [song], which music.db doesn't have: MusicDatabase's owner is asked to add
  /// it. Asked once: a song already in any request (waiting, sent or refused) by the same
  /// artist and title, or the same YouTube video, isn't added again. Returns whether it was
  /// added now.
  Future<bool> requestSong(SongRequest song) => _write(
    (db) async => db.insert(_songRequests, {
      'title': song.title,
      'artist': song.artist,
      'album': song.album,
      'year': song.year,
      'youtube_video_id': song.youtubeVideoId,
      'spotify_track_id': song.spotifyTrackId,
      'source': song.source.code,
      'requested_at': _timestamp(_now()),
    }),
    unless: () => _songRequested(song),
    table: _songRequests,
  );

  /// The songs asked to be added in the requests waiting to be sent, in the order they were
  /// asked for.
  Future<List<SongRequest>> waitingSongRequests() => _inTurn(() async {
    final factory = factoryOverride ?? databaseFactory;
    final requests = <SongRequest>[];
    for (final file in await pending()) {
      final db = await factory.openDatabase(
        file.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        if (!await _hasTable(db, _songRequests)) continue;
        for (final row in await db.query(
          _songRequests,
          orderBy: 'requested_at',
        )) {
          requests.add(_songRequestOf(row));
        }
      } finally {
        await db.close();
      }
    }
    return requests;
  });

  static SongRequest _songRequestOf(Map<String, Object?> row) => SongRequest(
    title: row['title']! as String,
    artist: row['artist'] as String?,
    source: SongRequestSource.values.firstWhere(
      (s) => s.code == row['source'],
      orElse: () => SongRequestSource.youtube,
    ),
    album: row['album'] as String?,
    year: row['year'] as int?,
    youtubeVideoId: row['youtube_video_id'] as String?,
    spotifyTrackId: row['spotify_track_id'] as String?,
  );

  Future<bool> _songRequested(SongRequest song) async {
    final dir = await directory();
    final factory = factoryOverride ?? databaseFactory;
    for (final folder in _numbered(dir)) {
      if (!await folder.exists()) continue;
      await for (final f in folder.list()) {
        if (!_requestName.hasMatch(_baseName(f.path))) continue;
        final db = await factory.openDatabase(f.path);
        try {
          if (!await _hasTable(db, _songRequests)) continue;
          for (final row in await db.query(_songRequests)) {
            final asked = _songRequestOf(row);
            if (asked.key == song.key ||
                (song.youtubeVideoId != null &&
                    asked.youtubeVideoId == song.youtubeVideoId)) {
              return true;
            }
          }
        } finally {
          await db.close();
        }
      }
    }
    return false;
  }

  /// The links found for songs without one in the requests waiting to be sent, in the order
  /// they were found.
  Future<List<FoundLinkReport>> waitingFoundLinks() => _inTurn(() async {
    final factory = factoryOverride ?? databaseFactory;
    final reports = <FoundLinkReport>[];
    for (final file in await pending()) {
      final db = await factory.openDatabase(
        file.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        if (!await _hasTable(db, _foundLinks)) continue;
        for (final row in await db.query(_foundLinks)) {
          reports.add(FoundLinkReport._fromRow(row));
        }
      } finally {
        await db.close();
      }
    }
    DateTime when(FoundLinkReport r) =>
        DateTime.tryParse(r.foundAt) ?? DateTime(0);
    reports.sort((a, b) => when(a).compareTo(when(b)));
    return reports;
  });

  /// The phone found [video] to play instead of [song]'s dead link [deadVideoId] — a suggestion
  /// for MusicDatabase, not a decision.
  Future<void> reportReplacement(
    CatalogSong song,
    String deadVideoId,
    YouTubeVideo video,
  ) async => _write((db) async {
    await db.insert('dead_youtube_links', {
      'song_id': song.id,
      'title': song.title,
      'artist': song.artistLabel,
      'dead_video_id': deadVideoId,
      'detected_at': _timestamp(_now()),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.update(
      'dead_youtube_links',
      {
        'replacement_video_id': video.id,
        'replacement_title': video.title,
        'replacement_channel': video.channel,
        'replacement_found_at': _timestamp(_now()),
      },
      where: 'song_id = ? AND dead_video_id = ?',
      whereArgs: [song.id, deadVideoId],
    );
  });

  Map<({String table, int rowId, String column}), FieldCorrection> _known =
      const {};

  /// The user's correction of [column] in music.db's [table] row [rowId], waiting or sent,
  /// while the downloaded music.db still has the value it corrects ([current]); `null` once
  /// music.db's value changed (accepted, or settled otherwise) or when there's none.
  FieldCorrection? correctionOf(
    String table,
    int rowId,
    String column,
    Object? current,
  ) {
    final correction = _known[(table: table, rowId: rowId, column: column)];
    if (correction == null || !_same(correction.oldValue, current)) return null;
    return correction;
  }

  /// Every correction known, waiting or sent, including those music.db has settled since
  /// (see [correctionOf]).
  Iterable<FieldCorrection> get corrections => _known.values;

  /// The corrections in the requests waiting to be sent, in the order they were made.
  List<FieldCorrection> get waitingCorrections {
    final waiting = [
      for (final c in _known.values)
        if (!c.sent) c,
    ];
    DateTime when(FieldCorrection c) =>
        DateTime.tryParse(c.correctedAt) ?? DateTime(0);
    waiting.sort((a, b) => when(a).compareTo(when(b)));
    return waiting;
  }

  /// The user corrected [column] of music.db's [table] row [rowId], which the downloaded
  /// music.db has as [oldValue], to [newValue] (`null` empties it), looking at [song]. A
  /// suggestion MusicDatabase's owner reviews; the phone keeps using music.db's value (except
  /// YouTube links, `main.dart`). Corrected again before it's sent, the newer value replaces the
  /// older; set back to [oldValue], the correction is dropped — or, once sent, taken back with a
  /// newer one giving [oldValue] again. [oldAsValue] is [oldValue] as a new value would give it,
  /// where the two differ: `songs.artist_id` is corrected with an artist's name.
  Future<void> correctField({
    required String table,
    required int rowId,
    required String column,
    required Object? oldValue,
    required Object? newValue,
    required CatalogSong song,
    Object? oldAsValue,
  }) => _inTurn(() async {
    final key = (table: table, rowId: rowId, column: column);
    final old = oldAsValue ?? oldValue;
    if (_same(old, newValue)) {
      if (_known[key]?.sent == false) {
        await _writeCorrection(key, null);
      }
      final sent = _known[key];
      final takeBack =
          sent != null &&
          _same(sent.oldValue, oldValue) &&
          !_same(sent.newValue, old);
      if (!takeBack) return;
    }
    await _writeCorrection(key, {
      'table_name': table,
      'row_id': rowId,
      'column_name': column,
      'old_value': oldValue,
      'new_value': newValue,
      'song_id': song.id,
      'title': song.title,
      'artist': song.artistLabel,
      'corrected_at': _timestamp(_now()),
    });
  });

  /// Puts [row] into the waiting corrections, replacing the one for [key]; with `null` only
  /// deletes that one.
  Future<void> _writeCorrection(
    ({String table, int rowId, String column}) key,
    Map<String, Object?>? row,
  ) async {
    final db = await _openRequest(_corrections);
    final file = File(db.path);
    bool empty;
    try {
      if (row == null) {
        await db.delete(
          _corrections,
          where: 'table_name = ? AND row_id = ? AND column_name = ?',
          whereArgs: [key.table, key.rowId, key.column],
        );
      } else {
        await db.insert(
          _corrections,
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      empty = (await db.query(_corrections, limit: 1)).isEmpty;
    } finally {
      await db.close();
    }
    // Never sent, so its number may be given again.
    if (empty) {
      await file.delete();
      final journal = File('${file.path}-journal');
      if (await journal.exists()) await journal.delete();
    }
    await _loadCorrections();
    _waiting = (await pending()).length;
    notifyListeners();
    if (!empty) onReported?.call();
  }

  Future<void> _loadCorrections() async {
    final dir = await directory();
    final factory = factoryOverride ?? databaseFactory;
    final files = <(File, bool)>[
      for (final (folder, sent) in [
        (Directory('${dir.path}/sent'), true),
        (dir, false),
      ])
        if (await folder.exists())
          await for (final f in folder.list())
            if (f is File && _requestName.hasMatch(_baseName(f.path)))
              (f, sent),
    ];
    files.sort((a, b) => _number(a.$1.path).compareTo(_number(b.$1.path)));
    final known =
        <({String table, int rowId, String column}), FieldCorrection>{};
    for (final (file, sent) in files) {
      final db = await factory.openDatabase(
        file.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      try {
        if (!await _hasTable(db, _corrections)) continue;
        for (final row in await db.query(_corrections)) {
          final c = FieldCorrection._fromRow(row, sent: sent);
          known[(table: c.table, rowId: c.rowId, column: c.column)] = c;
        }
      } catch (e) {
        debugPrint('Outbox: reading corrections from ${file.path} failed: $e');
      } finally {
        await db.close();
      }
    }
    _known = known;
  }

  static bool _same(Object? a, Object? b) =>
      a == null || b == null ? a == b : '$a' == '$b';

  /// Folders holding requests that already have a number: waiting, sent and refused ones.
  List<Directory> _numbered(Directory dir) => [
    dir,
    Directory('${dir.path}/sent'),
    Directory('${dir.path}/rejected'),
  ];

  Future<bool> _reported(
    String table,
    String videoColumn,
    int songId,
    String videoId,
  ) async {
    final dir = await directory();
    final factory = factoryOverride ?? databaseFactory;
    for (final folder in _numbered(dir)) {
      if (!await folder.exists()) continue;
      await for (final f in folder.list()) {
        if (!_requestName.hasMatch(_baseName(f.path))) continue;
        final db = await factory.openDatabase(f.path);
        try {
          if (!await _hasTable(db, table)) continue;
          final rows = await db.query(
            table,
            where: 'song_id = ? AND $videoColumn = ?',
            whereArgs: [songId, videoId],
            limit: 1,
          );
          if (rows.isNotEmpty) return true;
        } finally {
          await db.close();
        }
      }
    }
    return false;
  }

  /// [unless] is checked in turn with the writes, before any request file is opened. Returns
  /// whether [change] was made.
  Future<bool> _write(
    Future<void> Function(Database db) change, {
    Future<bool> Function()? unless,
    String table = _deadLinks,
  }) {
    return _inTurn(() async {
      if (unless != null && await unless()) return false;
      final db = await _openRequest(table);
      try {
        await change(db);
      } finally {
        await db.close();
      }
      _waiting = (await pending()).length;
      notifyListeners();
      onReported?.call();
      return true;
    });
  }

  Future<T> _inTurn<T>(Future<T> Function() work) {
    final done = _writes.then((_) => work());
    _writes = done.then((_) {}, onError: (_) {});
    return done;
  }

  /// Sends the waiting requests to the first of [servers] (base addresses of MusicDatabase's
  /// sharing server, best first) that answers. Requests that can't go now stay for the next try.
  /// Without [manual] nothing happens while [autoSend] is off or the server refused today
  /// ([heldForToday]); a manual send ("Wyślij teraz") always tries.
  Future<OutboxSendResult> send(
    List<Uri> servers, {
    bool manual = false,
  }) async {
    if (_sending) return _lastSend ?? const OutboxSendResult(sent: 0);
    if (!manual && (!_autoSend || heldForToday)) {
      return const OutboxSendResult(sent: 0);
    }
    // Nothing to do: no connection attempt, and the last result stays shown.
    if ((await pending()).isEmpty) return const OutboxSendResult(sent: 0);
    _sending = true;
    notifyListeners();
    try {
      final result = await _inTurn(() => _sendAll(servers));
      _lastSend = result;
      // Only the server saying "not now" holds sending back; no connection doesn't (the next
      // start or return to the app may well have one).
      if (result.serverRefused) {
        await _setHeld(_now());
      } else if (_heldOn != null && result.problem == null) {
        await _setHeld(null);
      }
      return result;
    } finally {
      _sending = false;
      _waiting = (await pending()).length;
      await _inTurn(_loadCorrections);
      notifyListeners();
    }
  }

  Future<OutboxSendResult> _sendAll(List<Uri> servers) async {
    final files = await pending();
    if (files.isEmpty) return const OutboxSendResult(sent: 0);
    if (servers.isEmpty) {
      return const OutboxSendResult(
        sent: 0,
        problem: 'Nie ustawiono adresu serwera MusicDatabase',
      );
    }
    final dir = await directory();
    final client = HttpClient()..connectionTimeout = sendTimeout;
    var sent = 0;
    var refused = 0;
    String? problem;
    try {
      for (final server in servers) {
        problem = null;
        var otherUser = 0;
        try {
          for (final file in await pending()) {
            final name = _baseName(file.path);
            final code = await _put(
              client,
              server.resolve('/inbox/$name'),
              file,
              _authToken(),
            );
            switch (code) {
              case HttpStatus.created || HttpStatus.ok:
                await _moveTo(file, Directory('${dir.path}/sent'));
                sent++;
              case HttpStatus.badRequest ||
                  HttpStatus.conflict ||
                  HttpStatus.lengthRequired ||
                  HttpStatus.requestEntityTooLarge:
                debugPrint('Outbox: the inbox refused $name ($code)');
                await _moveTo(file, Directory('${dir.path}/rejected'));
                refused++;
              // Named after another user than the one logged in (made before switching
              // accounts): only that user's token can send it, so it waits.
              case HttpStatus.forbidden:
                otherUser++;
              case HttpStatus.unauthorized:
                onUnauthorized?.call();
                return OutboxSendResult(
                  sent: sent,
                  refused: refused,
                  problem:
                      'Serwer nie przyjął logowania — zaloguj się ponownie '
                      '(Ustawienia › Konto)',
                );
              case HttpStatus.insufficientStorage:
                return OutboxSendResult(
                  sent: sent,
                  refused: refused,
                  problem: 'Skrzynka odbiorcza MusicDatabase jest pełna',
                  serverRefused: true,
                );
              case HttpStatus.serviceUnavailable:
                return OutboxSendResult(
                  sent: sent,
                  refused: refused,
                  problem: 'Dysk serwera MusicDatabase nie jest podłączony',
                  serverRefused: true,
                );
              default:
                throw HttpException('HTTP $code');
            }
          }
          return OutboxSendResult(
            sent: sent,
            refused: refused,
            problem: otherUser == 0
                ? null
                : 'Zgłoszenia innego użytkownika ($otherUser) wyślą się po '
                      'zalogowaniu na jego konto',
          );
        } catch (e) {
          debugPrint('Outbox: sending to $server failed: $e');
          problem = e is HttpException
              ? 'Serwer odpowiedział: ${e.message}'
              : 'Brak połączenia z serwerem MusicDatabase';
        }
      }
    } finally {
      client.close(force: true);
    }
    return OutboxSendResult(sent: sent, refused: refused, problem: problem);
  }

  // The limits of MusicDatabase's package import (its hand-off
  // `public-database-for-musicdatabaseapp.md`); a file over the inbox's own limit would be
  // refused over HTTP too.
  static const maxPackageFiles = 1000;
  static const maxPackageFileBytes = 1 << 20;
  static const maxPackageBytes = 50 << 20;

  /// The name typed for packages while logged out, cleaned ([cleanSenderName]): `null` before
  /// it was asked for, `''` when the user left it empty (packages without a name).
  String? get typedSender => _typedSender;

  /// Whether the first package still has to ask for a name: no account, nothing typed yet.
  bool get asksForSender =>
      _safeUserName(_userName()) == null && _typedSender == null;

  /// Who packages are from: the logged-in account, else the name typed for packages; `null`
  /// signs them with nothing.
  String? get packageSender {
    final account = _safeUserName(_userName());
    if (account != null) return account;
    final typed = _typedSender;
    return typed == null || typed.isEmpty ? null : typed;
  }

  Future<void> setTypedSender(String typed) async {
    _typedSender = cleanSenderName(typed) ?? '';
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _packageSenderKey,
      _typedSender!,
    );
  }

  /// The requests the last package held, still in `outbox/sent/` (for [rebuildLastPackage]).
  List<String> get lastPackage => _lastPackage;

  static final _senderPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{1,31}$');

  /// A typed name as MusicDatabase's inbox takes it (its username pattern): lowercase Latin
  /// letters, digits, `_` and `-`, at most 32. Accents are stripped and Cyrillic spelled in Latin
  /// letters, spaces become `-`, anything else is dropped; `null` when fewer than 2 characters
  /// are left — the files then go without a name, rather than with an invented one.
  static String? cleanSenderName(String typed) {
    final latin = normalizeForSearch(typed).split('').map((c) {
      return _cyrillic[c] ?? c;
    }).join();
    var name = latin
        .replaceAll(' ', '-')
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '')
        .replaceFirst(RegExp(r'^[_-]+'), '');
    if (name.length > 32) name = name.substring(0, 32);
    return _senderPattern.hasMatch(name) ? name : null;
  }

  static const _cyrillic = {
    'а': 'a',
    'б': 'b',
    'в': 'v',
    'г': 'g',
    'ґ': 'g',
    'д': 'd',
    'е': 'e',
    'ё': 'e',
    'є': 'ye',
    'ж': 'zh',
    'з': 'z',
    'и': 'i',
    'і': 'i',
    'ї': 'yi',
    'й': 'y',
    'к': 'k',
    'л': 'l',
    'м': 'm',
    'н': 'n',
    'о': 'o',
    'п': 'p',
    'р': 'r',
    'с': 's',
    'т': 't',
    'у': 'u',
    'ў': 'u',
    'ф': 'f',
    'х': 'kh',
    'ц': 'ts',
    'ч': 'ch',
    'ш': 'sh',
    'щ': 'shch',
    'ъ': '',
    'ы': 'y',
    'ь': '',
    'э': 'e',
    'ю': 'yu',
    'я': 'ya',
  };

  /// Packs the waiting requests into a `.zip` for the share sheet and counts them as sent: they
  /// move to `outbox/sent/` as after an upload, so findings made meanwhile start new requests.
  /// Unsigned requests get [packageSender] in their name on the way (never sent over HTTP, so
  /// no token has to match it). `null` when nothing is waiting. [undoExport] puts them back if
  /// the share sheet was closed without sharing.
  Future<RequestPackage?> exportPackage() async {
    final package = await _inTurn(() async {
      final files = await pending();
      if (files.isEmpty) return null;
      final dir = await directory();
      final sender = packageSender;
      final chosen = <File>[];
      var total = 0;
      var refused = 0;
      var leftOut = 0;
      for (final file in files) {
        final size = await file.length();
        if (size > maxPackageFileBytes) {
          await _moveTo(file, Directory('${dir.path}/rejected'));
          refused++;
        } else if (chosen.length >= maxPackageFiles ||
            total + size > maxPackageBytes) {
          leftOut++;
        } else {
          chosen.add(file);
          total += size;
        }
      }
      if (chosen.isEmpty) return null;
      final sent = Directory('${dir.path}/sent');
      final names = <String>[];
      final originals = <String>[];
      for (final file in chosen) {
        final original = _baseName(file.path);
        final name = sender != null && _userOf(file.path) == null
            ? '${sender}_$original'
            : original;
        await _moveTo(file, sent, name: name);
        names.add(name);
        originals.add(original);
      }
      final previous = _lastPackage;
      await _saveLastPackage(names);
      return RequestPackage._(
        file: await _zip(sent, names, sender),
        names: names,
        originals: originals,
        previous: previous,
        leftOut: leftOut,
        refused: refused,
      );
    });
    await refresh();
    return package;
  }

  /// Takes back an export nobody received: the requests wait again under their old names.
  Future<void> undoExport(RequestPackage package) async {
    await _inTurn(() async {
      final dir = await directory();
      for (var i = 0; i < package.names.length; i++) {
        final file = File('${dir.path}/sent/${package.names[i]}');
        if (await file.exists()) {
          await _moveTo(file, dir, name: package.originals[i]);
        }
      }
      await _saveLastPackage(package.previous);
      if (await package.file.exists()) await package.file.delete();
    });
    await refresh();
  }

  /// The last package again, from `outbox/sent/` ("Wyeksportuj ponownie ostatnią paczkę"), in
  /// case it got lost on the way; MusicDatabase skips files it already has. `null` when none
  /// of its requests are left.
  Future<RequestPackage?> rebuildLastPackage() => _inTurn(() async {
    final sent = Directory('${(await directory()).path}/sent');
    final names = [
      for (final name in _lastPackage)
        if (File('${sent.path}/$name').existsSync()) name,
    ];
    if (names.isEmpty) return null;
    return RequestPackage._(
      file: await _zip(sent, names, packageSender),
      names: names,
      originals: names,
      previous: _lastPackage,
    );
  });

  Future<void> _saveLastPackage(List<String> names) async {
    _lastPackage = names;
    await (await SharedPreferences.getInstance()).setStringList(
      _lastPackageKey,
      names,
    );
  }

  /// The `.zip` MusicDatabase's "Importuj paczkę" takes: the request files at the top level,
  /// names and contents unchanged, nothing else. Only the newest package is kept on the phone.
  Future<File> _zip(
    Directory folder,
    List<String> names,
    String? sender,
  ) async {
    final archive = Archive();
    for (final name in names) {
      archive.addFile(
        ArchiveFile.bytes(
          name,
          await File('${folder.path}/$name').readAsBytes(),
        ),
      );
    }
    final packages = Directory(
      '${(await _storageRoot()).path}/outbox_packages',
    );
    if (await packages.exists()) await packages.delete(recursive: true);
    await packages.create(recursive: true);
    final now = _now();
    final zip = File(
      '${packages.path}/zgloszenia-${sender ?? 'leina-radio'}-'
      '${_datePart(now)}_${_timePart(now)}.zip',
    );
    await zip.writeAsBytes(ZipEncoder().encodeBytes(archive));
    return zip;
  }

  /// How long to wait for the server before trying the next address (or giving up).
  static const sendTimeout = Duration(seconds: 8);

  static Future<int> _put(
    HttpClient client,
    Uri uri,
    File file,
    String? token,
  ) async {
    final bytes = await file.readAsBytes();
    final request = await client.putUrl(uri).timeout(sendTimeout);
    request.headers.contentType = ContentType.binary;
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close().timeout(sendTimeout);
    await response.drain<void>();
    return response.statusCode;
  }

  static Future<void> _moveTo(
    File file,
    Directory folder, {
    String? name,
  }) async {
    await folder.create(recursive: true);
    await file.rename('${folder.path}/${name ?? _baseName(file.path)}');
    // A rollback journal SQLite may leave next to the file.
    final journal = File('${file.path}-journal');
    if (await journal.exists()) await journal.delete();
  }

  /// The newest waiting request of the current user that holds [table], or a new one.
  Future<Database> _openRequest(String table) async {
    final user = _safeUserName(_userName());
    final factory = factoryOverride ?? databaseFactory;
    // Only a request made by the same user (or, logged out, an unsigned one) takes more: the
    // name says who sent it, and the server checks it against the token.
    final own = (await pending()).where((f) => _userOf(f.path) == user);
    for (final file in own.toList().reversed) {
      final db = await factory.openDatabase(file.path);
      if (await _hasTable(db, table)) return db;
      await db.close();
    }
    final dir = await directory();
    final created = _now();
    final number = await _nextNumber(dir);
    final name = [
      ?user,
      _datePart(created),
      _timePart(created),
      number.toString().padLeft(3, '0'),
    ].join('_');
    return factory.openDatabase(
      '${dir.path}/$name.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
          CREATE TABLE request (
            format INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            user_name TEXT,
            app TEXT NOT NULL
          )''');
          await db.insert('request', {
            'format': format,
            'created_at': _timestamp(created),
            'user_name': user,
            'app': 'Leina Radio',
          });
          await db.execute(_schemas[table]!);
        },
      ),
    );
  }

  static const _deadLinks = 'dead_youtube_links';
  static const _corrections = 'field_corrections';
  static const _foundLinks = 'found_youtube_links';
  static const _songRequests = 'song_requests';

  // Each kind of report gets files of its own: MusicDatabase keeps a whole file unprocessed
  // while it doesn't know one of its tables, and corrections came after dead links.
  static const _schemas = {
    _deadLinks: '''
    CREATE TABLE dead_youtube_links (
      song_id INTEGER NOT NULL,
      title TEXT NOT NULL,
      artist TEXT NOT NULL,
      dead_video_id TEXT NOT NULL,
      detected_at TEXT NOT NULL,
      replacement_video_id TEXT,
      replacement_title TEXT,
      replacement_channel TEXT,
      replacement_found_at TEXT,
      PRIMARY KEY (song_id, dead_video_id)
    )''',
    _corrections: '''
    CREATE TABLE field_corrections (
      table_name TEXT NOT NULL,
      row_id INTEGER NOT NULL,
      column_name TEXT NOT NULL,
      old_value,
      new_value,
      song_id INTEGER NOT NULL,
      title TEXT NOT NULL,
      artist TEXT NOT NULL,
      corrected_at TEXT NOT NULL,
      PRIMARY KEY (table_name, row_id, column_name)
    )''',
    _foundLinks: '''
    CREATE TABLE found_youtube_links (
      song_id INTEGER NOT NULL,
      title TEXT NOT NULL,
      artist TEXT NOT NULL,
      video_id TEXT NOT NULL,
      video_title TEXT,
      video_channel TEXT,
      found_at TEXT NOT NULL,
      PRIMARY KEY (song_id, video_id)
    )''',
    _songRequests: '''
    CREATE TABLE song_requests (
      title TEXT NOT NULL,
      artist TEXT,
      album TEXT,
      year INTEGER,
      duration_s INTEGER,
      youtube_video_id TEXT,
      spotify_track_id TEXT,
      source TEXT NOT NULL,
      requested_at TEXT NOT NULL
    )''',
  };

  static Future<bool> _hasTable(Database db, String table) async =>
      (await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      )).isNotEmpty;

  /// One more than any request ever numbered here, sent ones included, so a number isn't reused.
  Future<int> _nextNumber(Directory dir) async {
    var highest = 0;
    for (final folder in _numbered(dir)) {
      if (!await folder.exists()) continue;
      await for (final f in folder.list()) {
        if (!_requestName.hasMatch(_baseName(f.path))) continue;
        final n = _number(f.path);
        if (n > highest) highest = n;
      }
    }
    return highest + 1;
  }

  static final _requestName = RegExp(
    r'^(?:([A-Za-z0-9][A-Za-z0-9_-]*)_)?\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_(\d+)\.db$',
  );

  static String? _userOf(String path) =>
      _requestName.firstMatch(_baseName(path))!.group(1);

  static String _baseName(String path) => path.split('/').last;

  static int _number(String path) =>
      int.parse(_requestName.firstMatch(_baseName(path))!.group(2)!);

  /// A MusicDatabase username as is (lowercase letters, digits, `-`, `_` — its
  /// `USERNAME_PATTERN`); anything else becomes `-`. The date after it has a fixed shape, so a
  /// `_` in the name doesn't make the file name ambiguous. At most 40 (the inbox's limit).
  static String? _safeUserName(String? name) {
    final safe = name
        ?.trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^[_-]+'), '');
    if (safe == null || safe.isEmpty) return null;
    return safe.length > 40 ? safe.substring(0, 40) : safe;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _datePart(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';

  static String _timePart(DateTime t) =>
      '${_two(t.hour)}-${_two(t.minute)}-${_two(t.second)}';

  /// Local time with its UTC offset, e.g. `2026-10-12T23:44:05+02:00`.
  static String _timestamp(DateTime t) {
    final offset = t.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    return '${_datePart(t)}T${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}'
        '$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
  }
}

/// How one [Outbox.send] went; [problem] (Polish, for display) says why something is still
/// waiting, `null` when everything went.
class OutboxSendResult {
  const OutboxSendResult({
    required this.sent,
    this.refused = 0,
    this.problem,
    this.serverRefused = false,
  });

  /// Stored by the inbox (201), or found there already (200).
  final int sent;

  /// The server answered but can't take requests now (507 inbox full, 503 drive not mounted).
  final bool serverRefused;

  /// Refused by the inbox as malformed — kept in `outbox/rejected/`, not sent again.
  final int refused;
  final String? problem;
}

/// One row of a request's `dead_youtube_links`: music.db's link of a song that YouTube no longer
/// plays, with the video the phone plays instead, if it found one.
class DeadLinkReport {
  const DeadLinkReport({
    required this.songId,
    required this.title,
    required this.artist,
    required this.deadVideoId,
    required this.detectedAt,
    this.replacementVideoId,
    this.replacementTitle,
    this.replacementChannel,
  });

  DeadLinkReport._fromRow(Map<String, Object?> row)
    : songId = row['song_id']! as int,
      title = row['title']! as String,
      artist = row['artist']! as String,
      deadVideoId = row['dead_video_id']! as String,
      detectedAt = row['detected_at']! as String,
      replacementVideoId = row['replacement_video_id'] as String?,
      replacementTitle = row['replacement_title'] as String?,
      replacementChannel = row['replacement_channel'] as String?;

  final int songId;
  final String title;
  final String artist;
  final String deadVideoId;

  /// ISO 8601 with offset, as written to the request.
  final String detectedAt;
  final String? replacementVideoId;
  final String? replacementTitle;
  final String? replacementChannel;
}

/// A video the phone found for a song music.db has no link for.
class FoundLinkReport {
  FoundLinkReport._fromRow(Map<String, Object?> row)
    : songId = row['song_id']! as int,
      title = row['title']! as String,
      artist = row['artist']! as String,
      videoId = row['video_id']! as String,
      videoTitle = row['video_title'] as String?,
      videoChannel = row['video_channel'] as String?,
      foundAt = row['found_at']! as String;

  final int songId;
  final String title;
  final String artist;
  final String videoId;
  final String? videoTitle;
  final String? videoChannel;

  /// ISO 8601 with offset, as written to the request.
  final String foundAt;
}

/// A field of music.db the user corrected on the phone, for MusicDatabase to review.
class FieldCorrection {
  FieldCorrection._fromRow(Map<String, Object?> row, {required this.sent})
    : table = row['table_name']! as String,
      rowId = row['row_id']! as int,
      column = row['column_name']! as String,
      oldValue = row['old_value'],
      newValue = row['new_value'],
      songId = row['song_id']! as int,
      title = row['title']! as String,
      artist = row['artist']! as String,
      correctedAt = row['corrected_at']! as String;

  /// `songs`, `artists` or `albums`.
  final String table;
  final int rowId;
  final String column;

  /// What the phone's music.db had.
  final Object? oldValue;

  /// `null`: the user emptied the field.
  final Object? newValue;

  /// The song it was corrected from, as the phone showed it.
  final int songId;
  final String title;
  final String artist;

  /// ISO 8601 with offset.
  final String correctedAt;

  /// Already handed to MusicDatabase's inbox.
  final bool sent;
}

class OutboxScope extends InheritedNotifier<Outbox> {
  const OutboxScope({
    super.key,
    required Outbox super.notifier,
    required super.child,
  });

  static Outbox of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OutboxScope>()!.notifier!;

  static Outbox? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OutboxScope>()?.notifier;
}

/// A `.zip` of requests made by [Outbox.exportPackage] or [Outbox.rebuildLastPackage].
class RequestPackage {
  const RequestPackage._({
    required this.file,
    required this.names,
    required this.originals,
    required this.previous,
    this.leftOut = 0,
    this.refused = 0,
  });

  final File file;

  /// The request files in it.
  final List<String> names;

  /// [names] as they were while waiting (before a sender was added).
  final List<String> originals;

  /// [Outbox.lastPackage] before this one.
  final List<String> previous;

  /// Waiting requests over the package's limits, left for the next one.
  final int leftOut;

  /// Requests too big for MusicDatabase's inbox, put aside like ones the server refused.
  final int refused;
}
