import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'combined_search.dart';
import 'custom_covers.dart';
import 'database_sync.dart';
import 'local_library.dart';
import 'playlist_sync.dart';
import 'song_catalog.dart';
import 'text_normalizer.dart';
import 'youtube_library.dart';

/// A "Nastrój": MusicDatabase songs with the same feel, in no order
/// ([ADR 0008](../../../docs/decisions/0008-moods.md)). Global moods come from the downloaded
/// `tag.db` and everyone sees them, logged in or not; a user's own moods are synced with their
/// MusicDatabase account, and ones made while logged out live only on the phone.
class Mood {
  const Mood._({
    required this.name,
    required this.songIds,
    this.globalId,
    this.localId,
    this.phoneOnly = false,
    this.cover,
    this.createdAt,
  });

  final String name;

  /// music.db's `songs.id`s; some may be missing from an older music.db on the phone.
  final Set<int> songIds;

  /// tag.db's `tags.id` of a global mood.
  final int? globalId;

  /// `moods.id` in `local.db` of the user's own mood.
  final int? localId;

  bool get global => globalId != null;

  /// Made while logged out: not in any MusicDatabase account (yet).
  final bool phoneOnly;

  /// The picked cover's hash ([CustomCovers]) — for a global mood the user's own; `null`: a
  /// collage of its songs' covers.
  final String? cover;

  /// When the user made it; `null` for a global mood (tag.db doesn't say).
  final DateTime? createdAt;

  /// Tells moods apart across reloads (a user's mood may get another `uid` from MusicDatabase,
  /// never another local id).
  String get key => global ? 'g$globalId' : 'u$localId';
}

/// The moods the phone knows: global ones read from `tag.db` (`tags.kind = 'mood'`) and the
/// user's own, kept in `local.db`. Like playlists, the logged-in account's are exchanged with
/// MusicDatabase by [sync] (`/users/<name>/moods`: whole moods, newer change wins, deleting
/// deletes everywhere) and ones made while logged out stay on the phone until
/// [addPhoneOnlyToAccount]; another account's are hidden until it logs in again.
///
/// A user with the `edit_global_moods` permission may also add songs to global moods and take
/// them out. MusicDatabase applies those changes to its tag.db later, so the phone keeps each
/// one (shown on top of its own tag.db) until a downloaded tag.db has it.
class MoodLibrary extends ChangeNotifier {
  MoodLibrary(
    this._database,
    this._sync, {
    this.factoryOverride,
    DateTime Function()? now,
    String? Function()? userName,
    String? Function()? authToken,
    bool Function()? canEditGlobal,
    this.covers,
  }) : _now = now ?? DateTime.now,
       _userName = userName ?? (() => null),
       _authToken = authToken ?? (() => null),
       _canEditGlobal = canEditGlobal ?? (() => false) {
    _sync.addListener(_onSyncChanged);
  }

  /// A change MusicDatabase accepted but its tag.db (as downloaded) still doesn't show is
  /// dropped after this: someone else may have undone it, or the owner may have.
  static const sentChangeKept = Duration(days: 7);

  final Future<Database> Function() _database;
  final DatabaseSync _sync;

  /// SQLite implementation for reading tag.db instead of sqflite's global `databaseFactory`.
  final DatabaseFactory? factoryOverride;
  final DateTime Function() _now;
  final String? Function() _userName;
  final String? Function() _authToken;
  final bool Function() _canEditGlobal;

  /// Where cover pictures are kept, sent from and downloaded to; `null` in tests without them.
  final CustomCovers? covers;

  /// A mood was changed here, e.g. to send it to MusicDatabase soon.
  VoidCallback? onChanged;

  /// The server didn't accept [_authToken] (HTTP 401): the user has to log in again.
  VoidCallback? onUnauthorized;

  /// MusicDatabase refused a global mood change for lack of this permission (revoked since
  /// the phone last asked).
  void Function(String permission)? onPermissionRevoked;

  /// tag.db's moods by `tags.id`: name and songs.
  Map<int, ({String name, Set<int> songs})> _tagMoods = const {};

  DateTime? _tagDbFor;
  bool _tagDbLoaded = false;

  List<Mood> _userMoods = const [];
  List<Mood> _globalMoods = const [];

  /// The logged-in user's own moods, by name.
  List<Mood> get userMoods => _userMoods;

  /// Every global mood, by name, with this phone's changes not yet in tag.db.
  List<Mood> get globalMoods => _globalMoods;

  /// A MusicDatabase user is logged in, so they can have moods of their own.
  bool get loggedIn => _userName() != null;

  /// May add songs to global moods and take them out.
  bool get canEditGlobal => _userName() != null && _canEditGlobal();

  /// The same mood as now loaded (or `null` when it's gone), e.g. for a screen showing it.
  Mood? current(Mood mood) => [
    ..._userMoods,
    ..._globalMoods,
  ].where((m) => m.key == mood.key).firstOrNull;

  Future<void> load() async {
    if (!_tagDbLoaded || _sync.lastSync != _tagDbFor) await _loadTagDb();
    await _loadLocal();
  }

  void _onSyncChanged() {
    if (!_tagDbLoaded || _sync.downloading || _sync.lastSync == _tagDbFor) {
      return;
    }
    load().catchError((Object e) => debugPrint('Loading moods failed: $e'));
  }

  Future<void> _loadTagDb() async {
    final syncTime = _sync.lastSync;
    final moods = <int, ({String name, Set<int> songs})>{};
    var hasMoods = false;
    try {
      final file = await _sync.localFile('tag.db');
      if (await file.exists()) {
        final db = await (factoryOverride ?? databaseFactory).openDatabase(
          file.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        try {
          final columns = {
            for (final c in await db.rawQuery('PRAGMA table_info(tags)'))
              c['name'],
          };
          hasMoods = columns.contains('kind');
          if (hasMoods) {
            for (final row in await db.rawQuery('''
              SELECT t.id, t.name, s.song_id
              FROM tags t LEFT JOIN song_tags s ON s.tag_id = t.id
              WHERE t.kind = 'mood' ''')) {
              final mood = moods[row['id']! as int] ??= (
                name: row['name']! as String,
                songs: <int>{},
              );
              final songId = row['song_id'] as int?;
              if (songId != null) mood.songs.add(songId);
            }
          }
        } finally {
          await db.close();
        }
      }
    } catch (e) {
      debugPrint('Reading moods from tag.db failed: $e');
    }
    _tagMoods = moods;
    _tagDbFor = syncTime;
    _tagDbLoaded = true;
    // A tag.db from before moods (no `tags.kind`) says nothing about them.
    if (hasMoods) await _forgetSettledChanges();
  }

  /// Drops this phone's global mood changes the downloaded tag.db already shows, those
  /// overtaken by a later change to the same song, and those MusicDatabase accepted long ago.
  Future<void> _forgetSettledChanges() async {
    final db = await _database();
    final rows = await db.query(
      'global_mood_changes',
      where: 'sent_at IS NOT NULL',
    );
    final keepUntil = _now().subtract(sentChangeKept).millisecondsSinceEpoch;
    for (final row in rows) {
      final later = await db.query(
        'global_mood_changes',
        columns: ['id'],
        where: 'account = ? AND mood_id = ? AND song_id = ? AND id > ?',
        whereArgs: [row['account'], row['mood_id'], row['song_id'], row['id']],
        limit: 1,
      );
      final mood = _tagMoods[row['mood_id']! as int];
      final settled =
          later.isNotEmpty ||
          mood == null ||
          mood.songs.contains(row['song_id']! as int) == (row['added'] == 1) ||
          (row['sent_at']! as int) < keepUntil;
      if (settled) {
        await db.delete(
          'global_mood_changes',
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }

  Future<void> _loadLocal() async {
    final db = await _database();
    final user = _userName();
    final userMoods = <Mood>[];
    final global = {
      for (final MapEntry(:key, :value) in _tagMoods.entries)
        key: (name: value.name, songs: {...value.songs}),
    };
    final scope = _scope('m.');
    final songs = <int, Set<int>>{};
    for (final row in await db.rawQuery(
      'SELECT s.mood_id, s.song_id FROM mood_songs s '
      'JOIN moods m ON m.id = s.mood_id WHERE ${scope.where}',
      scope.args,
    )) {
      (songs[row['mood_id']! as int] ??= {}).add(row['song_id']! as int);
    }
    for (final row in await db.rawQuery(
      'SELECT m.id, m.name, m.account, m.cover_sha256, m.created_at FROM moods m '
      'WHERE m.deleted_at IS NULL AND ${scope.where}',
      scope.args,
    )) {
      final id = row['id']! as int;
      userMoods.add(
        Mood._(
          name: row['name']! as String,
          songIds: songs[id] ?? const {},
          localId: id,
          phoneOnly: row['account'] == null,
          cover: row['cover_sha256'] as String?,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row['created_at']! as int,
          ),
        ),
      );
    }
    // The account's own cover of a global mood wins over one set while logged out.
    final globalCovers = <int, String?>{};
    final coverScope = _scope();
    for (final row in await db.query(
      'global_mood_covers',
      where: coverScope.where,
      whereArgs: coverScope.args,
      orderBy: 'account IS NOT NULL',
    )) {
      globalCovers[row['mood_id']! as int] = row['cover_sha256'] as String?;
    }
    if (user != null) {
      // In the order they were made, so the last change to a song is what counts.
      for (final row in await db.query(
        'global_mood_changes',
        where: 'account = ?',
        whereArgs: [user],
        orderBy: 'id',
      )) {
        final mood = global[row['mood_id']! as int];
        if (mood == null) continue;
        final songId = row['song_id']! as int;
        row['added'] == 1 ? mood.songs.add(songId) : mood.songs.remove(songId);
      }
    }
    int byName(Mood a, Mood b) =>
        normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name));
    _userMoods = userMoods..sort(byName);
    _globalMoods = [
      for (final MapEntry(:key, :value) in global.entries)
        Mood._(
          name: value.name,
          songIds: value.songs,
          globalId: key,
          cover: globalCovers[key],
        ),
    ]..sort(byName);
    final names = <int, List<String>>{};
    final keys = <int, Set<String>>{};
    for (final mood in [..._userMoods, ..._globalMoods]) {
      for (final songId in mood.songIds) {
        (names[songId] ??= []).add(mood.name);
        (keys[songId] ??= {}).add(mood.key);
      }
    }
    _moodNames = names;
    _moodKeys = keys;
    _allKeys = {
      for (final mood in [..._userMoods, ..._globalMoods]) mood.key,
    };
    notifyListeners();
  }

  Map<int, List<String>> _moodNames = const {};
  Map<int, Set<String>> _moodKeys = const {};
  Set<String> _allKeys = const {};

  /// The [Mood.key]s of the shown moods [songId] is in.
  Set<String> moodKeysOf(int songId) => _moodKeys[songId] ?? const {};

  /// The [Mood.key]s of every shown mood.
  Set<String> get moodKeys => _allKeys;

  /// The names of the shown moods [songId] is in, in order.
  List<String> moodNameListOf(int songId) => _moodNames[songId] ?? const [];

  /// The names of the shown moods [songId] is in, for song search (`SearchField.mood`).
  String moodNamesOf(int songId) => _moodNames[songId]?.join(' ') ?? '';

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

  /// Moods that live only on this phone (made while logged out).
  int get phoneOnlyCount => _userMoods.where((m) => m.phoneOnly).length;

  /// The phone-only moods become the logged-in account's, sent to MusicDatabase by [sync]
  /// (which merges one into the account's mood of the same name).
  Future<void> addPhoneOnlyToAccount() async {
    final user = _userName();
    if (user == null) return;
    final db = await _database();
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE moods SET account = ?, dirty = 1, revision = 0 '
        'WHERE account IS NULL AND deleted_at IS NULL',
        [user],
      );
      // Covers of global moods set while logged out replace the account's.
      for (final row in await txn.query(
        'global_mood_covers',
        where: 'account IS NULL',
      )) {
        final own = await txn.query(
          'global_mood_covers',
          columns: ['id'],
          where: 'account = ? AND mood_id = ?',
          whereArgs: [user, row['mood_id']],
        );
        if (own.isEmpty) {
          await txn.update(
            'global_mood_covers',
            {'account': user, 'dirty': 1, 'revision': 0},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } else {
          await txn.update(
            'global_mood_covers',
            {
              'cover_sha256': row['cover_sha256'],
              'updated_at': row['updated_at'],
              'dirty': 1,
            },
            where: 'id = ?',
            whereArgs: [own.first['id']],
          );
          await txn.delete(
            'global_mood_covers',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    });
    await _loadLocal();
    onChanged?.call();
  }

  /// Makes a mood of the logged-in user (logged out: only on this phone), with [songIds] in it. Returns why it couldn't
  /// (Polish, for display), `null` when it's made.
  Future<String?> create(
    String name, {
    Iterable<int> songIds = const [],
  }) async {
    final user = _userName();
    final problem = _nameProblem(name.trim());
    if (problem != null) return problem;
    final now = _now().millisecondsSinceEpoch;
    final db = await _database();
    await db.transaction((txn) async {
      final id = await txn.insert('moods', {
        'uid': newPlaylistUid(),
        'account': user,
        'name': name.trim(),
        'created_at': now,
        'updated_at': now,
        'dirty': 1,
      });
      for (final songId in songIds) {
        await txn.insert('mood_songs', {
          'mood_id': id,
          'song_id': songId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    await _loadLocal();
    onChanged?.call();
    return null;
  }

  /// The user's own [mood] under another name; returns why not, like [create].
  Future<String?> rename(Mood mood, String name) async {
    if (mood.global) return 'Nazwę nastroju globalnego zmienia MusicDatabase';
    if (name.trim() == mood.name) return null;
    final problem = _nameProblem(name.trim());
    if (problem != null) return problem;
    await (await _database()).update(
      'moods',
      {
        'name': name.trim(),
        'updated_at': _now().millisecondsSinceEpoch,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [mood.localId],
    );
    await _loadLocal();
    onChanged?.call();
    return null;
  }

  /// Names are unique among the user's moods (MusicDatabase would merge two of a name).
  String? _nameProblem(String name) {
    if (name.isEmpty) return 'Wpisz nazwę nastroju';
    if (_userMoods.any((m) => m.name == name)) {
      return 'Nastrój „$name” już istnieje';
    }
    return null;
  }

  /// Removes the user's own [mood] (not its songs). An account's stays as a marker until
  /// MusicDatabase hears of it ([sync]), which deletes it on the account's other phones too.
  Future<void> delete(Mood mood) async {
    if (mood.global) return;
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete(
        'mood_songs',
        where: 'mood_id = ?',
        whereArgs: [mood.localId],
      );
      if (mood.phoneOnly) {
        await txn.delete('moods', where: 'id = ?', whereArgs: [mood.localId]);
      } else {
        await txn.update(
          'moods',
          {
            'deleted_at': _now().millisecondsSinceEpoch,
            'dirty': 0,
            'cover_sha256': null,
          },
          where: 'id = ?',
          whereArgs: [mood.localId],
        );
      }
    });
    await _loadLocal();
    onChanged?.call();
  }

  /// Gives [mood] the picked cover [hash] (`null`: back to the collage). The user's own mood
  /// syncs it like a rename; a global mood's cover is the user's own, synced with
  /// `/users/<name>/global-mood-covers` (phone-only while logged out).
  Future<void> setCover(Mood mood, String? hash) async {
    final db = await _database();
    final now = _now().millisecondsSinceEpoch;
    if (!mood.global) {
      await db.update(
        'moods',
        {'cover_sha256': hash, 'updated_at': now, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [mood.localId],
      );
    } else {
      final user = _userName();
      final values = {
        'cover_sha256': hash,
        'updated_at': now,
        'dirty': user == null ? 0 : 1,
      };
      final where = user == null
          ? 'account IS NULL AND mood_id = ?'
          : 'account = ? AND mood_id = ?';
      final args = [?user, mood.globalId];
      final changed = await db.update(
        'global_mood_covers',
        values,
        where: where,
        whereArgs: args,
      );
      if (changed == 0) {
        await db.insert('global_mood_covers', {
          ...values,
          'account': user,
          'mood_id': mood.globalId,
        });
      }
    }
    await _loadLocal();
    onChanged?.call();
  }

  /// Every cover hash a mood on the phone refers to (any account's), so [CustomCovers.prune]
  /// keeps them.
  Future<Set<String>> usedCovers() async {
    final db = await _database();
    return {
      for (final table in ['moods', 'global_mood_covers'])
        for (final row in await db.rawQuery(
          'SELECT DISTINCT cover_sha256 FROM $table WHERE cover_sha256 IS NOT NULL',
        ))
          row['cover_sha256']! as String,
    };
  }

  /// Puts [songId] into [mood] or takes it out ([inMood]). A global mood needs
  /// [canEditGlobal]; the change goes to MusicDatabase with the next [sync].
  Future<void> setSong(Mood mood, int songId, bool inMood) =>
      setSongs(mood, [songId], inMood);

  /// [setSong] for many songs at once (a whole playlist or the queue).
  Future<void> setSongs(Mood mood, Iterable<int> songIds, bool inMood) async {
    final ids = songIds.toSet();
    if (ids.isEmpty) return;
    final user = _userName();
    final db = await _database();
    if (!mood.global) {
      await db.transaction((txn) async {
        for (final songId in ids) {
          if (inMood) {
            await txn.insert('mood_songs', {
              'mood_id': mood.localId,
              'song_id': songId,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          } else {
            await txn.delete(
              'mood_songs',
              where: 'mood_id = ? AND song_id = ?',
              whereArgs: [mood.localId, songId],
            );
          }
        }
        await txn.update(
          'moods',
          {'updated_at': _now().millisecondsSinceEpoch, 'dirty': 1},
          where: 'id = ?',
          whereArgs: [mood.localId],
        );
      });
    } else {
      if (user == null || !canEditGlobal) return;
      await db.transaction((txn) async {
        for (final songId in ids) {
          final pair = [user, mood.globalId, songId];
          // Changed back before it was sent: neither change has to go.
          await txn.delete(
            'global_mood_changes',
            where: 'account = ? AND mood_id = ? AND song_id = ? AND sent_at IS NULL',
            whereArgs: pair,
          );
          final sent = await txn.query(
            'global_mood_changes',
            columns: ['added'],
            where: 'account = ? AND mood_id = ? AND song_id = ?',
            whereArgs: pair,
            orderBy: 'id DESC',
            limit: 1,
          );
          final there = sent.isNotEmpty
              ? sent.first['added'] == 1
              : _tagMoods[mood.globalId]?.songs.contains(songId) ?? false;
          if (there == inMood) continue;
          await txn.insert('global_mood_changes', {
            'account': user,
            'mood_id': mood.globalId,
            'song_id': songId,
            'added': inMood ? 1 : 0,
            'made_at': _now().millisecondsSinceEpoch,
          });
        }
      });
    }
    await _loadLocal();
    onChanged?.call();
  }

  bool _syncing = false;
  bool _syncAgain = false;
  PlaylistSyncResult? _lastSync;

  bool get syncing => _syncing;

  /// How the last [sync] went; `null` before the first one.
  PlaylistSyncResult? get lastSync => _lastSync;

  static String _revisionKey(String user) => 'moods.sync_revision.$user';

  /// Exchanges the logged-in user's moods with MusicDatabase on the first of [servers] that
  /// answers, like `PlaylistLibrary.sync`, then sends the changes to global moods made here.
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
      await _loadLocal();
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
        collection: 'moods',
      );
      try {
        final moods = await _syncOn(client, user);
        final global = await _sendGlobalChanges(client, user);
        final covers = await _syncGlobalCovers(server, user, token);
        return moods ?? global ?? covers;
      } on _SyncStopped catch (e) {
        return e.problem;
      } catch (e) {
        debugPrint('Mood sync on $server failed: $e');
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
      for (final mood in changes['moods']! as List) {
        final remote = mood as Map<String, Object?>;
        final local = await txn.query(
          'moods',
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
      'moods',
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
        final remote = answer.body! as Map<String, Object?>;
        if (remote['deleted'] == true) {
          await txn.delete('moods', where: 'id = ?', whereArgs: [row['id']]);
        } else {
          await _applyRemote(txn, remote, user, intoId: row['id']! as int);
        }
      });
    }
    for (final row in await db.query(
      'moods',
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
          'moods',
          columns: ['updated_at', 'deleted_at'],
          where: 'id = ?',
          whereArgs: [id],
        );
        if (now.isEmpty) return;
        // Changed again here while this was being sent: the answer's revision is the base the
        // newer change goes with next time; its songs would undo that change.
        if (remote['deleted'] != true &&
            (now.first['updated_at'] != row['updated_at'] ||
                now.first['deleted_at'] != null)) {
          await _adoptUid(txn, id, remote);
          return;
        }
        await _applyRemote(txn, remote, user, intoId: id);
      });
    }
    await fetchCovers(client, covers, [
      for (final row in await db.query(
        'moods',
        columns: ['cover_sha256'],
        where: 'account = ? AND cover_sha256 IS NOT NULL',
        whereArgs: [user],
      ))
        row['cover_sha256']! as String,
    ]);
    return problem;
  }

  static String _coverRevisionKey(String user) =>
      'moods.global_cover_revision.$user';

  /// Exchanges the user's own covers of global moods with MusicDatabase, like the moods
  /// themselves: rows changed there since the last time (one changed here too waits), then
  /// the ones changed here — the newer `updated_at` stays, a removal is `cover: null`.
  Future<String?> _syncGlobalCovers(
    Uri server,
    String user,
    String token,
  ) async {
    final client = PlaylistSyncClient(
      server,
      user,
      token,
      collection: 'global-mood-covers',
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      final since = prefs.getInt(_coverRevisionKey(user)) ?? 0;
      var answer = await client.changedSince(since);
      _check(answer);
      var changes = answer.body! as Map<String, Object?>;
      if ((changes['revision']! as int) < since) {
        answer = await client.changedSince(0);
        _check(answer);
        changes = answer.body! as Map<String, Object?>;
      }
      final db = await _database();
      await db.transaction((txn) async {
        for (final row in changes['covers']! as List) {
          final remote = row as Map<String, Object?>;
          final local = await txn.query(
            'global_mood_covers',
            columns: ['dirty'],
            where: 'account = ? AND mood_id = ?',
            whereArgs: [user, remote['mood_id']],
          );
          if (local.isNotEmpty && local.first['dirty'] == 1) continue;
          await _applyGlobalCover(txn, remote, user);
        }
      });
      await prefs.setInt(_coverRevisionKey(user), changes['revision']! as int);

      String? problem;
      for (final row in await db.query(
        'global_mood_covers',
        where: 'account = ? AND dirty = 1',
        whereArgs: [user],
      )) {
        final answer = await putWithCover(client, covers, '${row['mood_id']}', {
          'base_revision': row['revision'],
          'updated_at': row['updated_at'],
          'cover': row['cover_sha256'],
        }, required: true);
        problem ??= _check(answer, keepGoing: true);
        if (answer.body is! Map) continue;
        final remote = answer.body! as Map<String, Object?>;
        await db.transaction((txn) async {
          final now = await txn.query(
            'global_mood_covers',
            columns: ['updated_at'],
            where: 'id = ?',
            whereArgs: [row['id']],
          );
          if (now.isEmpty) return;
          // Changed again while this was on its way: only the base for sending that.
          if (now.first['updated_at'] != row['updated_at']) {
            await txn.update(
              'global_mood_covers',
              {'revision': remote['revision']},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
            return;
          }
          await _applyGlobalCover(txn, remote, user);
        });
      }
      await fetchCovers(client, covers, [
        for (final row in await db.query(
          'global_mood_covers',
          columns: ['cover_sha256'],
          where: 'account = ? AND cover_sha256 IS NOT NULL',
          whereArgs: [user],
        ))
          row['cover_sha256']! as String,
      ]);
      return problem;
    } finally {
      client.close();
    }
  }

  Future<void> _applyGlobalCover(
    Transaction txn,
    Map<String, Object?> remote,
    String user,
  ) async {
    final values = {
      'cover_sha256': remote['cover'],
      'updated_at': remote['updated_at'],
      'revision': remote['revision'],
      'dirty': 0,
    };
    final changed = await txn.update(
      'global_mood_covers',
      values,
      where: 'account = ? AND mood_id = ?',
      whereArgs: [user, remote['mood_id']],
    );
    if (changed == 0) {
      await txn.insert('global_mood_covers', {
        ...values,
        'account': user,
        'mood_id': remote['mood_id'],
      });
    }
  }

  /// Sends the global mood changes made here, oldest first. MusicDatabase applies them later;
  /// until a downloaded tag.db shows them they stay, marked as sent.
  Future<String?> _sendGlobalChanges(
    PlaylistSyncClient client,
    String user,
  ) async {
    final db = await _database();
    String? problem;
    for (final row in await db.query(
      'global_mood_changes',
      where: 'account = ? AND sent_at IS NULL',
      whereArgs: [user],
      orderBy: 'id',
    )) {
      final answer = await client.changeGlobalMood(
        row['mood_id']! as int,
        row['song_id']! as int,
        row['added'] == 1,
      );
      final body = answer.body;
      switch (answer.status) {
        case HttpStatus.accepted:
          // MusicDatabase answers with the song's id after merges.
          final songId = body is Map ? body['song_id'] : null;
          await db.update(
            'global_mood_changes',
            {
              'sent_at': _now().millisecondsSinceEpoch,
              if (songId is int) 'song_id': songId,
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        case HttpStatus.unauthorized:
          onUnauthorized?.call();
          throw const _SyncStopped(
            'Serwer nie przyjął logowania — zaloguj się ponownie (Ustawienia › Konto)',
          );
        case HttpStatus.serviceUnavailable:
          throw const _SyncStopped(
            'Serwer MusicDatabase nie może teraz przyjąć zmian w nastrojach '
            '(dysk niepodłączony)',
          );
        case HttpStatus.forbidden ||
            HttpStatus.notFound ||
            HttpStatus.badRequest:
          // No permission (any more), the mood or the song is gone, or a bug: it can't go.
          await db.delete(
            'global_mood_changes',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
          if (body is Map && body['error'] == 'permission') {
            onPermissionRevoked?.call(body['permission'] as String);
            problem ??=
                'Nie masz już uprawnień do zmieniania nastrojów globalnych';
          }
        default:
          problem ??= 'Serwer odrzucił zmianę nastroju (HTTP ${answer.status})';
      }
    }
    return problem;
  }

  /// Throws [_SyncStopped] for answers that end this sync and returns the problem of one
  /// mood's answer otherwise; `null` when it went.
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
          'Serwer MusicDatabase nie może teraz zapisać nastrojów (dysk niepodłączony lub '
          'baza użytkownika jeszcze nieprzygotowana)',
        );
      case HttpStatus.notFound when !keepGoing:
        throw const _SyncStopped(
          'Serwer MusicDatabase nie obsługuje jeszcze nastrojów',
        );
    }
    final problem = 'Serwer odrzucił nastrój (HTTP ${answer.status})';
    if (keepGoing) return problem;
    throw _SyncStopped(problem);
  }

  Future<Map<String, Object?>> _toJson(
    Database db,
    Map<String, Object?> row,
  ) async => {
    'uid': row['uid'],
    'base_revision': row['revision'],
    'name': row['name'],
    'cover': row['cover_sha256'],
    'created_at': row['created_at'],
    'updated_at': row['updated_at'],
    'song_ids': [
      for (final s in await db.query(
        'mood_songs',
        columns: ['song_id'],
        where: 'mood_id = ?',
        whereArgs: [row['id']],
        orderBy: 'song_id',
      ))
        s['song_id'],
    ],
  };

  /// The row [id] takes MusicDatabase's revision and uid (another one when it merged the mood
  /// into one of the same name), dropping a row that already had that uid.
  Future<void> _adoptUid(
    Transaction txn,
    int id,
    Map<String, Object?> remote,
  ) async {
    await _dropOthers(txn, remote['uid']! as String, id);
    await txn.update(
      'moods',
      {'revision': remote['revision'], 'uid': remote['uid']},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _dropOthers(Transaction txn, String uid, int? keep) async {
    for (final row in await txn.query(
      'moods',
      columns: ['id'],
      where: 'uid = ?',
      whereArgs: [uid],
    )) {
      if (row['id'] == keep) continue;
      await txn.delete(
        'mood_songs',
        where: 'mood_id = ?',
        whereArgs: [row['id']],
      );
      await txn.delete('moods', where: 'id = ?', whereArgs: [row['id']]);
    }
  }

  /// Stores MusicDatabase's [remote] mood as [user]'s: in place of the row [intoId] (the one
  /// just sent), else of the row with its uid, else as a new one. A deleted one — also one the
  /// owner promoted to a global mood or merged into another — goes.
  Future<void> _applyRemote(
    Transaction txn,
    Map<String, Object?> remote,
    String user, {
    int? intoId,
  }) async {
    final uid = remote['uid']! as String;
    final id =
        intoId ??
        (await txn.query(
              'moods',
              columns: ['id'],
              where: 'uid = ?',
              whereArgs: [uid],
            )).firstOrNull?['id']
            as int?;
    await _dropOthers(txn, uid, id);
    if (id != null) {
      await txn.delete('mood_songs', where: 'mood_id = ?', whereArgs: [id]);
    }
    if (remote['deleted'] == true) {
      if (id != null) {
        await txn.delete('moods', where: 'id = ?', whereArgs: [id]);
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
      'created_at': remote['created_at'],
      'updated_at': remote['updated_at'],
      // A server from before covers says nothing about them.
      if (remote.containsKey('cover')) 'cover_sha256': remote['cover'],
    };
    if (id != null) {
      await txn.update('moods', values, where: 'id = ?', whereArgs: [id]);
    }
    final moodId = id ?? await txn.insert('moods', values);
    for (final songId in remote['song_ids']! as List) {
      await txn.insert('mood_songs', {
        'mood_id': moodId,
        'song_id': songId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  @override
  void dispose() {
    _sync.removeListener(_onSyncChanged);
    super.dispose();
  }
}

/// An answer that ends a [MoodLibrary.sync] early, with why (Polish, for display).
class _SyncStopped implements Exception {
  const _SyncStopped(this.problem);

  final String problem;
}

/// [mood]'s songs that the phone's music.db has, as rows (with their phone files and what the
/// phone found on YouTube), by title.
List<SearchHit> moodHits(
  Mood mood,
  SongCatalog catalog,
  LocalLibrary library,
  YouTubeLibrary youTube,
) {
  final hits = [
    for (final id in mood.songIds)
      if (catalog.byId(id) case final song?)
        withPhoneYouTube(SearchHit.main(song, library.filesOf(id)), youTube),
  ];
  final titles = {for (final hit in hits) hit: normalizeForSearch(hit.title)};
  return hits..sort((a, b) => titles[a]!.compareTo(titles[b]!));
}

/// Makes the [MoodLibrary] reachable from any screen.
class MoodLibraryScope extends InheritedNotifier<MoodLibrary> {
  const MoodLibraryScope({
    super.key,
    required MoodLibrary super.notifier,
    required super.child,
  });

  static MoodLibrary of(BuildContext context) => maybeOf(context)!;

  /// `null` outside the app (widget tests that pump a single screen).
  static MoodLibrary? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MoodLibraryScope>()?.notifier;
}
