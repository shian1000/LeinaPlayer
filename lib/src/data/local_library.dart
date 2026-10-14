import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'playlist_sync.dart';
import 'song_catalog.dart';
import 'text_normalizer.dart';

/// Audio file extensions picked up by a scan.
const audioExtensions = [
  '.mp3', '.flac', '.m4a', '.mp4', '.ogg', '.opus', '.wav', '.ape', //
  '.aif', '.aiff', '.webm',
];

/// Artist and title of a music file, the way MusicDatabase's mp3 import reads them: ID3 (or
/// other) tags first; only when tags lack a title or an artist, "Artist - Title" from the file
/// name.
class FileSongInfo {
  const FileSongInfo({required this.title, this.artist, this.album, this.year});

  final String title;
  final String? artist;
  final String? album;
  final int? year;
}

FileSongInfo readFileSongInfo(String path) {
  final fileName = path.split('/').last;
  final dot = fileName.lastIndexOf('.');
  final stem = (dot > 0 ? fileName.substring(0, dot) : fileName).trim();
  String? clean(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  try {
    final tags = readMetadata(File(path), getImage: false);
    final title = clean(tags.title);
    final artist = clean(tags.artist);
    if (title != null && artist != null) {
      final year = tags.year?.year;
      return FileSongInfo(
        title: title,
        artist: artist,
        album: clean(tags.album),
        // The tag reader reports a missing year as year 0.
        year: year == null || year < 1 ? null : year,
      );
    }
  } catch (_) {
    // Unreadable or tagless file: fall back to the name, as MusicDatabase does.
  }
  final (artist, title) = splitArtistTitle(stem);
  return FileSongInfo(title: title, artist: artist);
}

/// "Artist - Title" from a file name — port of the first two stages of MusicDatabase's
/// `split_artist_title()` (`docs/agent-notes/normalization-and-matching.md` there): a spaced
/// separator (` - `, ` – `, ` — `, ` _ `) first; only if there is none, a bare `-`, `_` or `~`.
/// Without any separator the whole name is the title and the artist is unknown.
(String?, String) splitArtistTitle(String name) {
  for (final separator in [' - ', ' – ', ' — ', ' _ ']) {
    final at = name.indexOf(separator);
    if (at > 0) {
      final artist = name.substring(0, at).trim();
      final title = name.substring(at + separator.length).trim();
      if (artist.isNotEmpty && title.isNotEmpty) return (artist, title);
    }
  }
  final bare = RegExp(r'[-_~]').firstMatch(name);
  if (bare != null && bare.start > 0) {
    const junk = '-_~ ';
    String strip(String s) {
      var start = 0, end = s.length;
      while (start < end && junk.contains(s[start])) {
        start++;
      }
      while (end > start && junk.contains(s[end - 1])) {
        end--;
      }
      return s.substring(start, end);
    }

    final artist = strip(name.substring(0, bare.start));
    final title = strip(name.substring(bare.end));
    if (artist.isNotEmpty && title.isNotEmpty) return (artist, title);
  }
  return (null, name);
}

/// A row of the phone's own `local.db`.
class LocalSong {
  LocalSong({
    required this.id,
    required this.filePath,
    required this.title,
    this.artist,
    this.album,
    this.year,
    this.mainDbId,
    required this.pending,
  }) : normalizedTitle = normalizeForSearch(title),
       _fieldTexts = {
         SearchField.title: normalizeForSearch(title),
         SearchField.artist: normalizeForSearch(artist),
         SearchField.album: normalizeForSearch(album),
         SearchField.year: year?.toString() ?? '',
       };

  final int id;
  final String filePath;
  final String title;
  final String? artist;
  final String? album;
  final int? year;

  /// `songs.id` in MusicDatabase's `music.db` when the file is a song already there.
  final int? mainDbId;

  /// The file isn't in MusicDatabase yet (a candidate to add there).
  final bool pending;

  String get fileName => filePath.split('/').last;

  final String normalizedTitle;

  /// Normalized searchable text per field; the phone only knows title, artist, album and year
  /// of a file, so language/origin filters never match phone-only songs.
  final Map<SearchField, String> _fieldTexts;

  /// Whether every word occurs in the chosen [fields] (same rule as MusicDatabase search).
  bool matches(List<String> words, Set<SearchField> fields) {
    final text = [for (final field in fields) ?_fieldTexts[field]].join(' ');
    return words.every(text.contains);
  }
}

class ScanResult {
  const ScanResult({
    required this.added,
    required this.removed,
    required this.newPending,
    required this.mainDatabaseAvailable,
  });

  /// Files found for the first time.
  final int added;

  /// Rows dropped because their file (or its folder) is gone.
  final int removed;

  /// How many of the added files aren't in MusicDatabase.
  final int newPending;

  /// False when no `music.db` was downloaded: nothing could be matched, so every file counts as
  /// pending until a later scan with the database.
  final bool mainDatabaseAvailable;
}

/// Music files kept on the phone: the folders to scan ("Ustawienia › Źródła muzyki › Muzyka
/// lokalna") and the phone's own `local.db` describing every file found, linked to
/// MusicDatabase (`main_db_id`) or marked `pending` when the song isn't there yet.
class LocalLibrary extends ChangeNotifier {
  LocalLibrary(
    this._catalog, {
    Future<Directory> Function()? storageRoot,
    this.factoryOverride,
    DateTime Function()? now,
  }) : _storageRoot = storageRoot ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now;

  static const _foldersKey = 'local_music.folders';
  static const _lastScanKey = 'local_music.last_scan_ms';

  final SongCatalog _catalog;
  final Future<Directory> Function() _storageRoot;
  final DateTime Function() _now;

  /// SQLite implementation to use instead of sqflite's global one (tests use FFI).
  final DatabaseFactory? factoryOverride;

  List<String> _folders = const [];
  DateTime? _lastScan;
  int _songCount = 0;
  int _pendingCount = 0;
  bool _scanning = false;
  Future<Database>? _db;

  List<String> get folders => _folders;
  DateTime? get lastScan => _lastScan;
  bool get scanning => _scanning;

  /// "Utwory zapisane na urządzeniu".
  int get songCount => _songCount;

  /// "Nowe utwory spoza bazy danych".
  int get pendingCount => _pendingCount;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _folders = prefs.getStringList(_foldersKey) ?? const [];
    final ms = prefs.getInt(_lastScanKey);
    _lastScan = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    await _refreshCounts();
  }

  Future<void> addFolder(String path) async {
    final folder = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    if (_folders.contains(folder)) return;
    await _saveFolders([..._folders, folder]);
  }

  Future<void> removeFolder(String path) =>
      _saveFolders([..._folders]..remove(path));

  Future<void> _saveFolders(List<String> folders) async {
    _folders = List.unmodifiable(folders);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setStringList(
      _foldersKey,
      _folders,
    );
  }

  /// Opened once; concurrent callers share the same opening. Also used by [YouTubeLibrary],
  /// whose tables live in the same file.
  Future<Database> database() => _db ??= _open();

  Future<Database> _open() async {
    final dir = await Directory('${(await _storageRoot()).path}/local')
        .create(recursive: true);
    return (factoryOverride ?? databaseFactory).openDatabase(
      '${dir.path}/local.db',
      options: OpenDatabaseOptions(
        version: 14,
        onCreate: (db, _) async {
          await db.execute('''
          CREATE TABLE local_songs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            -- Same columns as MusicDatabase's songs table, filled from the file's tags/name
            -- (artist is a name here, there is no artists table on the phone).
            title VARCHAR NOT NULL,
            album VARCHAR,
            year INTEGER,
            language VARCHAR,
            artist VARCHAR,
            nostalgic INTEGER,
            melancholic INTEGER,
            party INTEGER,
            youtube_video_id VARCHAR,
            spotify_url VARCHAR,
            -- Phone-only columns.
            file_path VARCHAR NOT NULL UNIQUE,
            main_db_id INTEGER,
            pending INTEGER NOT NULL DEFAULT 0,
            added_at INTEGER NOT NULL,
            checked_at INTEGER
          )''');
          await _createYouTubeTables(db);
          await _createPlaylistTables(db);
          await _createHistoryTable(db);
          await _createCoverTables(db);
          await _createTrackMatchTable(db);
          await _createNotFoundTable(db);
          await _addSpotifyTrackColumn(db);
          await _addVideoRemovedColumn(db);
          await _createRemovedVideosTable(db);
          await _addPlaylistSyncColumns(db);
          await _createMoodTables(db);
          await _addCoverColumns(db);
        },
        onUpgrade: (db, from, _) async {
          if (from < 2) await _createYouTubeTables(db);
          if (from < 3) await _createPlaylistTables(db);
          if (from < 4) await _createHistoryTable(db);
          if (from < 5) await _createCoverTables(db);
          if (from < 6) await _createTrackMatchTable(db);
          if (from < 7) await _createNotFoundTable(db);
          if (from < 8) await _addSpotifyTrackColumn(db);
          if (from < 9) await _addVideoRemovedColumn(db);
          if (from < 10) await _createRemovedVideosTable(db);
          if (from < 11) await _addPlaylistSyncColumns(db);
          if (from < 12) await _createMoodTables(db);
          if (from == 12) await _allowPhoneOnlyMoods(db);
          if (from < 14) await _addCoverColumns(db);
        },
      ),
    );
  }

  /// Version 14: covers picked for playlists and moods (`custom_covers.dart`, ADR 0009), by
  /// the SHA-256 of the image; synced with MusicDatabase with the playlist or mood. A global
  /// mood's cover is the user's own (`account` NULL: phone-only, like playlists), synced as its
  /// own small collection.
  static Future<void> _addCoverColumns(Database db) async {
    await db.execute('ALTER TABLE playlists ADD COLUMN cover_sha256 VARCHAR');
    await db.execute('ALTER TABLE moods ADD COLUMN cover_sha256 VARCHAR');
    await db.execute('''
      CREATE TABLE global_mood_covers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account VARCHAR,
        -- tag.db's tags.id.
        mood_id INTEGER NOT NULL,
        -- NULL: the cover was removed (kept so the removal is sent).
        cover_sha256 VARCHAR,
        updated_at INTEGER NOT NULL,
        revision INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 0
      )''');
  }

  /// Version 13: moods made while logged out stay on the phone (`account` NULL), like
  /// playlists; version 12 had `account NOT NULL`, which SQLite can only drop by copying.
  static Future<void> _allowPhoneOnlyMoods(Database db) async {
    await db.execute('ALTER TABLE moods RENAME TO moods_v12');
    await db.execute('''
      CREATE TABLE moods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid VARCHAR NOT NULL UNIQUE,
        account VARCHAR,
        name VARCHAR NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        revision INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER
      )''');
    await db.execute('INSERT INTO moods SELECT * FROM moods_v12');
    await db.execute('DROP TABLE moods_v12');
  }

  /// Version 12: moods (see `moods.dart`, ADR 0008). The logged-in user's own moods, synced with
  /// MusicDatabase like playlists; and changes to global moods (tag.db's) made here, kept until
  /// a downloaded tag.db has them.
  static Future<void> _createMoodTables(Database db) async {
    await db.execute('''
      CREATE TABLE moods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid VARCHAR NOT NULL UNIQUE,
        -- NULL: made while logged out, only on this phone.
        account VARCHAR,
        name VARCHAR NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        revision INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER
      )''');
    await db.execute('''
      CREATE TABLE mood_songs (
        mood_id INTEGER NOT NULL,
        -- music.db's songs.id: only MusicDatabase songs can be in a mood.
        song_id INTEGER NOT NULL,
        PRIMARY KEY (mood_id, song_id)
      )''');
    await db.execute('''
      CREATE TABLE global_mood_changes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account VARCHAR NOT NULL,
        -- tag.db's tags.id and music.db's songs.id.
        mood_id INTEGER NOT NULL,
        song_id INTEGER NOT NULL,
        added INTEGER NOT NULL,
        made_at INTEGER NOT NULL,
        -- When MusicDatabase accepted it (202); NULL: waiting to be sent.
        sent_at INTEGER
      )''');
  }

  /// Version 11: playlists synced with the user's MusicDatabase account (see
  /// `playlist_library.dart`, ADR 0007): the id shared with MusicDatabase, whose account the
  /// playlist belongs to (NULL: only on this phone), the server's revision last seen, a change
  /// waiting to be sent, and a deletion waiting to be sent (the row stays, without tracks).
  static Future<void> _addPlaylistSyncColumns(Database db) async {
    for (final column in [
      'uid VARCHAR',
      'account VARCHAR',
      'revision INTEGER NOT NULL DEFAULT 0',
      'dirty INTEGER NOT NULL DEFAULT 0',
      'deleted_at INTEGER',
    ]) {
      await db.execute('ALTER TABLE playlists ADD COLUMN $column');
    }
    for (final row in await db.query('playlists', columns: ['id'])) {
      await db.update(
        'playlists',
        {'uid': newPlaylistUid()},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await db.execute('CREATE UNIQUE INDEX ix_playlists_uid ON playlists (uid)');
  }

  /// Version 10: videos YouTube no longer has (found out by playing them or re-importing a
  /// playlist), so the phone doesn't offer them again (see `youtube_library.dart`).
  static Future<void> _createRemovedVideosTable(Database db) async {
    await db.execute('''
      CREATE TABLE youtube_removed_videos (
        video_id VARCHAR PRIMARY KEY,
        found_at INTEGER NOT NULL
      )''');
    // Playlist tracks marked by an import before this table existed.
    await db.execute('''
      INSERT OR IGNORE INTO youtube_removed_videos (video_id, found_at)
      SELECT DISTINCT youtube_video_id, CAST(strftime('%s', 'now') AS INTEGER) * 1000
      FROM playlist_tracks
      WHERE youtube_removed = 1 AND youtube_video_id IS NOT NULL''');
  }

  /// Version 9: a playlist track whose video YouTube removed (it vanished from the playlist and
  /// the video itself is gone) stays, marked, so it's searched again (see `playlist_library.dart`).
  static Future<void> _addVideoRemovedColumn(Database db) => db.execute(
    'ALTER TABLE playlist_tracks ADD COLUMN youtube_removed INTEGER NOT NULL DEFAULT 0',
  );

  /// Version 8: a Spotify playlist's track keeps its Spotify id (also in the history), for
  /// sharing the song.
  static Future<void> _addSpotifyTrackColumn(Database db) async {
    await db.execute(
      'ALTER TABLE playlist_tracks ADD COLUMN spotify_track_id VARCHAR',
    );
    await db.execute(
      'ALTER TABLE play_history ADD COLUMN spotify_track_id VARCHAR',
    );
  }

  /// Version 7: songs the phone searched YouTube for and found nothing (see
  /// `youtube_library.dart`), so the queue doesn't search for them again every time.
  static Future<void> _createNotFoundTable(Database db) async {
    // not_found_key: 'db:<songs.id>' or 'track:<normalised artist>\n<normalised title>'.
    await db.execute('''
      CREATE TABLE youtube_not_found (
        not_found_key VARCHAR PRIMARY KEY,
        artist VARCHAR,
        title VARCHAR NOT NULL,
        checked_at INTEGER NOT NULL
      )''');
  }

  /// Version 6: the video the phone found for a track known only by name — a Spotify playlist's
  /// track that isn't a MusicDatabase song (see `youtube_library.dart`). Keyed by the normalised
  /// artist + title, so it outlives re-importing the playlist and serves every playlist with it.
  static Future<void> _createTrackMatchTable(Database db) async {
    await db.execute('''
      CREATE TABLE youtube_track_matches (
        track_key VARCHAR PRIMARY KEY,
        artist VARCHAR,
        title VARCHAR NOT NULL,
        video_id VARCHAR NOT NULL,
        video_title VARCHAR,
        channel VARCHAR,
        matched_at INTEGER NOT NULL
      )''');
  }

  /// Version 5: album covers (see `album_covers.dart`).
  static Future<void> _createCoverTables(Database db) async {
    // What a source (iTunes, Deezer) said about an album — or a song, when there's no album —
    // so it's asked once. NULL urls: it has no cover.
    await db.execute('''
      CREATE TABLE cover_lookups (
        cover_key VARCHAR NOT NULL,
        source VARCHAR NOT NULL,
        small_url VARCHAR,
        large_url VARCHAR,
        checked_at INTEGER NOT NULL,
        PRIMARY KEY (cover_key, source)
      )''');
    // Downloaded cover images, up to the user's size limit (least recently shown goes first).
    await db.execute('''
      CREATE TABLE cover_cache (
        url VARCHAR PRIMARY KEY,
        file_name VARCHAR NOT NULL,
        size_bytes INTEGER NOT NULL,
        last_used_at INTEGER NOT NULL
      )''');
  }

  /// Version 4: what was played ("Ostatnie", see `play_history.dart`). A song is kept by what
  /// identifies it (MusicDatabase id, file, video) plus its title/artist as shown then.
  static Future<void> _createHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE play_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        played_at INTEGER NOT NULL,
        title VARCHAR NOT NULL,
        artist VARCHAR,
        main_db_id INTEGER,
        file_path VARCHAR,
        youtube_video_id VARCHAR,
        -- Played as part of this playlist (playlists.id), else on its own.
        playlist_id INTEGER,
        playlist_name VARCHAR
      )''');
  }

  /// Version 3: the user's playlists (see `playlist_library.dart`).
  static Future<void> _createPlaylistTables(Database db) async {
    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name VARCHAR NOT NULL,
        owner VARCHAR,
        -- Where it was imported from ('youtube' or 'spotify' + the playlist id), for
        -- re-importing and sharing.
        source VARCHAR,
        source_id VARCHAR,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE playlist_tracks (
        playlist_id INTEGER NOT NULL,
        position INTEGER NOT NULL,
        artist VARCHAR,
        title VARCHAR NOT NULL,
        -- The MusicDatabase song, when the track was recognised (music.db's songs.id).
        main_db_id INTEGER,
        youtube_video_id VARCHAR,
        duration_s INTEGER,
        PRIMARY KEY (playlist_id, position)
      )''');
  }

  /// Version 2: what the phone knows about YouTube itself (see `youtube_library.dart`).
  static Future<void> _createYouTubeTables(Database db) async {
    // A video the phone found for a MusicDatabase song that has no youtube_video_id. Kept
    // even after the audio leaves the cache; music.db's own link wins once it has one.
    await db.execute('''
      CREATE TABLE youtube_matches (
        main_db_id INTEGER PRIMARY KEY,
        video_id VARCHAR NOT NULL,
        video_title VARCHAR,
        channel VARCHAR,
        matched_at INTEGER NOT NULL
      )''');
    // Audio of played YouTube videos, kept on the phone up to the user's limit (least recently
    // played goes first).
    await db.execute('''
      CREATE TABLE youtube_cache (
        video_id VARCHAR PRIMARY KEY,
        file_name VARCHAR NOT NULL,
        size_bytes INTEGER NOT NULL,
        downloaded_at INTEGER NOT NULL,
        last_played_at INTEGER NOT NULL
      )''');
  }

  /// Re-reads `local.db` into memory (a few hundred/thousand rows) so search can use it on every
  /// keystroke without querying SQLite.
  Future<void> _refreshCounts() async {
    final rows = await (await database()).query('local_songs');
    _songs = [for (final row in rows) _fromRow(row)];
    _byMainId = {};
    for (final song in _songs) {
      if (song.mainDbId != null) (_byMainId[song.mainDbId!] ??= []).add(song);
    }
    _songCount = _songs.length;
    _pendingCount = _songs.where((s) => s.pending).length;
    notifyListeners();
  }

  List<LocalSong> _songs = const [];
  Map<int, List<LocalSong>> _byMainId = const {};

  /// The phone song stored at [path], if it's still known.
  LocalSong? fileAt(String path) =>
      _songs.where((s) => s.filePath == path).firstOrNull;

  /// Files on the phone that are this MusicDatabase song (`main_db_id`).
  List<LocalSong> filesOf(int mainDbId) => _byMainId[mainDbId] ?? const [];

  /// A phone song not in MusicDatabase with exactly this [title] and [artist] (a playlist keeps
  /// such a song only by those).
  LocalSong? pendingFile({required String title, String? artist}) => _songs
      .where((s) => s.pending && s.title == title && s.artist == artist)
      .firstOrNull;

  /// Phone songs not in MusicDatabase whose chosen [fields] contain every word of [query].
  List<LocalSong> searchPending(String query, Set<SearchField> fields) {
    final normalized = normalizeForSearch(query);
    if (normalized.isEmpty) return const [];
    final words = normalized.split(' ');
    return [
      for (final song in _songs)
        if (song.pending && song.matches(words, fields)) song,
    ];
  }

  Future<List<LocalSong>> pendingSongs() async {
    final rows = await (await database()).query(
      'local_songs',
      where: 'pending = 1',
      orderBy: 'artist COLLATE NOCASE, title COLLATE NOCASE',
    );
    return [for (final row in rows) _fromRow(row)];
  }

  static LocalSong _fromRow(Map<String, Object?> row) => LocalSong(
    id: row['id']! as int,
    filePath: row['file_path']! as String,
    title: row['title']! as String,
    artist: row['artist'] as String?,
    album: row['album'] as String?,
    year: row['year'] as int?,
    mainDbId: row['main_db_id'] as int?,
    pending: row['pending'] == 1,
  );

  /// Finds every audio file in [folders], adds new ones to `local.db` (each checked against
  /// MusicDatabase right away: `main_db_id` when it's there, `pending` when it isn't), drops
  /// rows whose files are gone, and re-checks earlier pending files in case MusicDatabase has
  /// gained them since.
  Future<ScanResult> scan() async {
    if (_scanning) {
      return const ScanResult(
        added: 0,
        removed: 0,
        newPending: 0,
        mainDatabaseAvailable: true,
      );
    }
    _scanning = true;
    notifyListeners();
    try {
      await _catalog.ensureLoaded();
      final matching = _catalog.status == CatalogStatus.ready;
      final files = await _audioFiles(_folders);
      final db = await database();
      final known = {
        for (final row in await db.query('local_songs', columns: ['file_path']))
          row['file_path']! as String,
      };

      final gone = known.difference(files);
      for (final path in gone) {
        await db.delete(
          'local_songs',
          where: 'file_path = ?',
          whereArgs: [path],
        );
      }

      final newPaths = (files.difference(known).toList()..sort());
      // Tag parsing is synchronous; keep it off the UI thread on the old phone.
      final infos = await Isolate.run(
        () => [for (final path in newPaths) readFileSongInfo(path)],
      );
      final now = _now().millisecondsSinceEpoch;
      var newPending = 0;
      final batch = db.batch();
      for (var i = 0; i < newPaths.length; i++) {
        final info = infos[i];
        final match = matching ? _match(info.title, info.artist) : null;
        if (match == null) newPending++;
        batch.insert('local_songs', {
          'file_path': newPaths[i],
          'title': info.title,
          'artist': info.artist,
          'album': info.album,
          'year': info.year,
          'main_db_id': match?.id,
          'pending': match == null ? 1 : 0,
          'added_at': now,
          'checked_at': matching ? now : null,
        });
      }
      await batch.commit(noResult: true);

      if (matching) await _recheckPending(db, now);

      _lastScan = _now();
      await (await SharedPreferences.getInstance()).setInt(
        _lastScanKey,
        _lastScan!.millisecondsSinceEpoch,
      );
      await _refreshCounts();
      return ScanResult(
        added: newPaths.length,
        removed: gone.length,
        newPending: newPending,
        mainDatabaseAvailable: matching,
      );
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  CatalogSong? _match(String title, String? artist) =>
      artist == null ? null : _catalog.findExact(title: title, artist: artist);

  Future<void> _recheckPending(Database db, int now) async {
    final rows = await db.query(
      'local_songs',
      columns: ['id', 'title', 'artist'],
      where: 'pending = 1',
    );
    final batch = db.batch();
    for (final row in rows) {
      final match = _match(row['title']! as String, row['artist'] as String?);
      batch.update(
        'local_songs',
        {
          'main_db_id': match?.id,
          'pending': match == null ? 1 : 0,
          'checked_at': now,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<Set<String>> _audioFiles(List<String> folders) async {
    final result = <String>{};
    for (final folder in folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          final lower = entity.path.toLowerCase();
          if (entity is File && audioExtensions.any(lower.endsWith)) {
            result.add(entity.path);
          }
        }
      } on FileSystemException catch (e) {
        debugPrint('Listing $folder failed: $e');
      }
    }
    return result;
  }

  @override
  void dispose() {
    _db?.then((db) => db.close());
    super.dispose();
  }
}

/// Makes the [LocalLibrary] reachable from any screen.
class LocalLibraryScope extends InheritedNotifier<LocalLibrary> {
  const LocalLibraryScope({
    super.key,
    required LocalLibrary super.notifier,
    required super.child,
  });

  static LocalLibrary of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LocalLibraryScope>()!
      .notifier!;
}
