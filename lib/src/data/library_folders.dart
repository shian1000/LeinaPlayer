import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'moods.dart';
import 'playlist_library.dart';
import 'playlist_sync.dart';
import 'text_normalizer.dart';

/// How Biblioteka is ordered ("Sortuj wg").
enum LibrarySort {
  recent('Ostatnie'),
  added('Ostatnio dodane'),
  alphabetical('Alfabetycznie'),
  creator('Twórca');

  const LibrarySort(this.label);

  final String label;
}

/// A folder in Biblioteka holding playlists and moods.
class LibraryFolder {
  const LibraryFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    DateTime? updatedAt,
    this.items = const [],
    this.account,
    this.revision = 0,
    this.dirty = false,
    this.deletedAt,
    this.refs = const {},
    this.pending = const [],
  }) : updatedAt = updatedAt ?? createdAt;

  factory LibraryFolder.fromJson(Map<String, Object?> json) {
    DateTime? time(String key) => json[key] is int
        ? DateTime.fromMillisecondsSinceEpoch(json[key]! as int)
        : null;
    return LibraryFolder(
      id: json['id']! as String,
      name: json['name'] as String? ?? '',
      createdAt: time('createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: time('updatedAt'),
      items: [...?(json['items'] as List?)?.cast<String>()],
      account: json['account'] as String?,
      revision: json['revision'] as int? ?? 0,
      dirty: json['dirty'] == true,
      deletedAt: time('deletedAt'),
      refs: {...?(json['refs'] as Map?)?.cast<String, String>()},
      pending: [...?(json['pending'] as List?)?.cast<String>()],
    );
  }

  /// Also the folder's `uid` shared with MusicDatabase (any string up to 64 characters:
  /// folders made before syncing keep their short id).
  final String id;
  final String name;
  final DateTime createdAt;

  /// When it was last renamed or got other items, here or on another phone of the account.
  final DateTime updatedAt;

  /// [LibraryFolders.playlistKey]s and [Mood.key]s, in the order they were put in.
  final List<String> items;

  /// The MusicDatabase user whose folders it's synced with; `null` = only on this phone.
  final String? account;

  /// MusicDatabase's revision of it, last seen.
  final int revision;

  /// Changed here, waiting to be sent.
  final bool dirty;

  /// Deleted here, waiting to be sent; it stays (empty) until MusicDatabase hears of it.
  final DateTime? deletedAt;

  /// The last known [FolderRefs] ref of each of [items], so an item whose playlist or mood
  /// isn't loaded (yet) is still sent.
  final Map<String, String> refs;

  /// Refs from MusicDatabase of playlists or moods the phone hasn't got (yet): kept and sent
  /// back, shown once they turn up.
  final List<String> pending;

  /// Its key among Biblioteka's items (for "Ostatnie").
  String get key => 'f$id';

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'items': items,
    'account': account,
    'revision': revision,
    'dirty': dirty,
    'deletedAt': deletedAt?.millisecondsSinceEpoch,
    'refs': refs,
    'pending': pending,
  };

  LibraryFolder copyWith({
    String? name,
    List<String>? items,
    DateTime? updatedAt,
    String? account,
    int? revision,
    bool? dirty,
    DateTime? deletedAt,
    Map<String, String>? refs,
    List<String>? pending,
  }) => LibraryFolder(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    items: items ?? this.items,
    account: account ?? this.account,
    revision: revision ?? this.revision,
    dirty: dirty ?? this.dirty,
    deletedAt: deletedAt ?? this.deletedAt,
    refs: refs ?? this.refs,
    pending: pending ?? this.pending,
  );
}

/// How a folder names its items to MusicDatabase, as strings on the phone: `playlist:<uid>`,
/// `mood:<uid>` (the user's own) and `global_mood:<tag.db id>`; on the wire each is an object,
/// see [toWire].
abstract final class FolderRefs {
  static String? of(LibraryEntry entry) => switch (entry) {
    PlaylistEntry(:final playlist) =>
      playlist.uid == null ? null : 'playlist:${playlist.uid}',
    MoodEntry(:final mood) =>
      mood.global
          ? 'global_mood:${mood.globalId}'
          : (mood.uid == null ? null : 'mood:${mood.uid}'),
    FolderEntry() => null,
  };

  static Map<String, Object?>? toWire(String ref) {
    final colon = ref.indexOf(':');
    if (colon < 0) return null;
    final value = ref.substring(colon + 1);
    return switch (ref.substring(0, colon)) {
      'playlist' => {'type': 'playlist', 'uid': value},
      'mood' => {'type': 'mood', 'uid': value},
      'global_mood' => {'type': 'global_mood', 'id': int.tryParse(value)},
      _ => null,
    };
  }

  static String? fromWire(Object? item) => switch (item) {
    {'type': 'playlist', 'uid': final String uid} => 'playlist:$uid',
    {'type': 'mood', 'uid': final String uid} => 'mood:$uid',
    {'type': 'global_mood', 'id': final int id} => 'global_mood:$id',
    _ => null,
  };
}

/// One row of Biblioteka: a folder, a playlist or a mood.
sealed class LibraryEntry {
  const LibraryEntry();

  String get key;
  String get name;

  /// Who made it, for [LibrarySort.creator]; `null` for a folder (listed first).
  String? get creator;
  DateTime? get createdAt;

  /// When it was last changed, for [LibrarySort.recent] when it was never opened.
  DateTime? get changedAt;
}

class FolderEntry extends LibraryEntry {
  const FolderEntry(this.folder, this.contents);

  final LibraryFolder folder;

  /// What's in it that's still on the phone (and shown for the account logged in).
  final List<LibraryEntry> contents;

  @override
  String get key => folder.key;
  @override
  String get name => folder.name;
  @override
  String? get creator => null;
  @override
  DateTime get createdAt => folder.createdAt;
  @override
  DateTime? get changedAt => null;
}

class PlaylistEntry extends LibraryEntry {
  const PlaylistEntry(this.playlist);

  final PlaylistSummary playlist;

  @override
  String get key => LibraryFolders.playlistKey(playlist.id);
  @override
  String get name => playlist.name;
  @override
  String get creator => playlist.owner ?? playlist.account ?? 'Ty';
  @override
  DateTime? get createdAt => playlist.createdAt;
  @override
  DateTime get changedAt => playlist.updatedAt;
}

class MoodEntry extends LibraryEntry {
  const MoodEntry(this.mood);

  final Mood mood;

  @override
  String get key => mood.key;
  @override
  String get name => mood.name;
  @override
  String get creator => mood.global ? 'MusicDatabase' : 'Ty';
  @override
  DateTime? get createdAt => mood.createdAt;
  @override
  DateTime? get changedAt => mood.createdAt;
}

/// Biblioteka's folders, its sort order and when each playlist, mood and folder was last opened
/// (for "Ostatnie"), in `shared_preferences`. The logged-in account's folders are exchanged with
/// MusicDatabase by [sync] (`/users/<name>/folders`: whole folders, newer change wins, deleting
/// deletes everywhere — like playlists, ADR 0011); ones made while logged out stay on the phone
/// until [addPhoneOnlyToAccount], another account's are hidden. The sort order and "Ostatnie"
/// stay on each phone (user's decision).
///
/// An item is in at most one folder; folders don't nest.
class LibraryFolders extends ChangeNotifier {
  LibraryFolders({
    DateTime Function()? now,
    String? Function()? userName,
    String? Function()? authToken,
  }) : _now = now ?? DateTime.now,
       _userName = userName ?? (() => null),
       _authToken = authToken ?? (() => null);

  static const _foldersKey = 'library.folders';
  static const _sortKey = 'library.sort';
  static const _openedKey = 'library.opened';

  final DateTime Function() _now;

  /// The logged-in MusicDatabase user ([Account]); `null` while logged out.
  final String? Function() _userName;
  final String? Function() _authToken;

  /// A folder was changed here, e.g. to send it to MusicDatabase soon.
  VoidCallback? onChanged;

  /// The server didn't accept [_authToken] (HTTP 401): the user has to log in again.
  VoidCallback? onUnauthorized;

  /// Every account's folders and the deletions not sent yet.
  List<LibraryFolder> _all = const [];
  LibrarySort _sort = LibrarySort.recent;
  Map<String, int> _opened = const {};

  /// Item keys of the playlists and moods loaded now, by their ref and the other way round
  /// ([updateItems]).
  Map<String, String> _keyOfRef = const {};
  Map<String, String> _refOfKey = const {};

  /// The folders shown: phone-only ones and the logged-in account's.
  List<LibraryFolder> get folders => [
    for (final f in _all)
      if (_visible(f)) f,
  ];

  bool _visible(LibraryFolder f) =>
      f.deletedAt == null && (f.account == null || f.account == _userName());

  LibrarySort get sort => _sort;

  static String playlistKey(int playlistId) => 'p$playlistId';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final folders = jsonDecode(prefs.getString(_foldersKey) ?? '[]') as List;
      _all = [
        for (final json in folders)
          LibraryFolder.fromJson((json as Map).cast<String, Object?>()),
      ];
      final opened = jsonDecode(prefs.getString(_openedKey) ?? '{}') as Map;
      _opened = opened.cast<String, int>();
    } on FormatException catch (e) {
      debugPrint('Biblioteka folders unreadable, starting empty: $e');
    }
    _sort = LibrarySort.values.asNameMap()[prefs.getString(_sortKey)] ?? _sort;
    notifyListeners();
  }

  Future<void> _saveFolders() async => (await SharedPreferences.getInstance())
      .setString(_foldersKey, jsonEncode([for (final f in _all) f.toJson()]));

  Future<void> setSort(LibrarySort sort) async {
    _sort = sort;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _sortKey,
      sort.name,
    );
  }

  /// [key] (a playlist, mood or folder) was opened now.
  Future<void> opened(String key) async {
    _opened = {..._opened, key: _now().millisecondsSinceEpoch};
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _openedKey,
      jsonEncode(_opened),
    );
  }

  DateTime? openedAt(String key) {
    final ms = _opened[key];
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  LibraryFolder? byId(String id) =>
      folders.where((f) => f.id == id).firstOrNull;

  /// The folder [itemKey] is in, if any.
  LibraryFolder? folderOf(String itemKey) =>
      folders.where((f) => f.items.contains(itemKey)).firstOrNull;

  Future<LibraryFolder> create(String name) async {
    final now = _now();
    final folder = LibraryFolder(
      id: newPlaylistUid(),
      name: name.trim(),
      createdAt: now,
      account: _userName(),
      dirty: true,
    );
    _all = [..._all, folder];
    await _changed();
    return folder;
  }

  Future<void> rename(String folderId, String name) =>
      _update((f) => f.id == folderId ? f.copyWith(name: name.trim()) : f);

  /// Removes the folder; what was in it goes back to Biblioteka's top level. An account's
  /// folder stays as an empty marker until MusicDatabase hears of the deletion ([sync]).
  Future<void> delete(String folderId) async {
    _all = [
      for (final f in _all)
        if (f.id != folderId || !_visible(f))
          f
        else if (f.account != null)
          f.copyWith(
            items: const [],
            refs: const {},
            pending: const [],
            deletedAt: _now(),
            dirty: false,
          ),
    ];
    await _changed();
  }

  /// Puts [itemKey] into [folderId] (out of any other folder), or back to the top level for
  /// `null`.
  Future<void> move(String itemKey, String? folderId) => _update(
    (f) => f.id == folderId
        ? (f.items.contains(itemKey)
              ? f
              : f.copyWith(items: [...f.items, itemKey]))
        : f.copyWith(items: [...f.items.where((k) => k != itemKey)]),
  );

  /// Applies [change] to the folders shown; the ones it changed get a new `updated_at` and
  /// wait to be sent.
  Future<void> _update(LibraryFolder Function(LibraryFolder) change) async {
    final now = _now();
    final before = _all;
    _all = [
      for (final f in _all) _visible(f) ? _touched(f, change(f), now) : f,
    ];
    if (!listEquals(before, _all)) await _changed();
  }

  /// [changed] marked as changed at [now], or [f] itself when it's the same.
  LibraryFolder _touched(
    LibraryFolder f,
    LibraryFolder changed,
    DateTime now,
  ) => changed.name == f.name && listEquals(changed.items, f.items)
      ? f
      : _withRefs(changed).copyWith(updatedAt: now, dirty: true);

  Future<void> _changed() async {
    notifyListeners();
    await _saveFolders();
    onChanged?.call();
  }

  /// [f] remembering the refs of its items known now.
  LibraryFolder _withRefs(LibraryFolder f) => f.copyWith(
    refs: {for (final key in f.items) key: ?(_refOfKey[key] ?? f.refs[key])},
  );

  /// Tells the folders which playlists and moods the phone has now (after either changed):
  /// refs from MusicDatabase that turned up become items, and a folder whose item got another
  /// uid (MusicDatabase merged two playlists or moods) is sent again.
  Future<void> updateItems({
    required List<PlaylistSummary> playlists,
    required List<Mood> moods,
  }) async {
    final refOfKey = <String, String>{};
    for (final entry in <LibraryEntry>[
      for (final p in playlists) PlaylistEntry(p),
      for (final m in moods) MoodEntry(m),
    ]) {
      if (FolderRefs.of(entry) case final ref?) refOfKey[entry.key] = ref;
    }
    _refOfKey = refOfKey;
    _keyOfRef = {
      for (final MapEntry(:key, :value) in refOfKey.entries) value: key,
    };
    final before = _all;
    _all = [for (final f in _all) f.deletedAt != null ? f : _resolved(f)];
    if (listEquals(before, _all)) return;
    notifyListeners();
    await _saveFolders();
    if (_all.where((f) => f.dirty).length >
        before.where((f) => f.dirty).length) {
      onChanged?.call();
    }
  }

  /// [f] with its pending refs that turned up as items; marked to be sent again when an
  /// item's ref changed.
  LibraryFolder _resolved(LibraryFolder f) {
    final found = [for (final ref in f.pending) ?_keyOfRef[ref]]
        .where((k) => !f.items.contains(k))
        .toList();
    final updated = _withRefs(
      found.isEmpty && f.pending.every((ref) => !_keyOfRef.containsKey(ref))
          ? f
          : f.copyWith(
              items: [...f.items, ...found],
              pending: [
                for (final ref in f.pending)
                  if (!_keyOfRef.containsKey(ref)) ref,
              ],
            ),
    );
    final refChanged =
        f.account != null &&
        f.items.any((k) => f.refs[k] != null && updated.refs[k] != f.refs[k]);
    if (found.isEmpty &&
        updated.pending.length == f.pending.length &&
        !refChanged) {
      return f;
    }
    return refChanged ? updated.copyWith(dirty: true) : updated;
  }

  /// Folders that live only on this phone (made while logged out).
  int get phoneOnlyCount =>
      _all.where((f) => f.account == null && f.deletedAt == null).length;

  /// The phone-only folders become the logged-in account's, sent to MusicDatabase by [sync].
  Future<void> addPhoneOnlyToAccount() async {
    final user = _userName();
    if (user == null) return;
    _all = [
      for (final f in _all)
        f.account == null && f.deletedAt == null
            ? _withRefs(f).copyWith(account: user, dirty: true, revision: 0)
            : f,
    ];
    await _changed();
  }

  bool _syncing = false;
  bool _syncAgain = false;
  PlaylistSyncResult? _lastSync;

  bool get syncing => _syncing;

  /// How the last [sync] went; `null` before the first one.
  PlaylistSyncResult? get lastSync => _lastSync;

  static String _revisionKey(String user) => 'folders.sync_revision.$user';

  /// Exchanges the logged-in account's folders with MusicDatabase on the first of [servers]
  /// that answers, like `PlaylistLibrary.sync`: what changed there first (a folder changed here
  /// too waits — sending it settles which version stays), then deletions and changes made
  /// here. Best after the playlists and moods, so the folders' items are on the phone.
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
      await _saveFolders();
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
        collection: 'folders',
      );
      try {
        return await _syncOn(client, user);
      } on _SyncStopped catch (e) {
        return e.problem;
      } catch (e) {
        debugPrint('Folder sync on $server failed: $e');
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
    for (final folder in changes['folders']! as List) {
      final remote = folder as Map<String, Object?>;
      final local = _all.where((f) => f.id == remote['uid']).firstOrNull;
      if (local != null && (local.dirty || local.deletedAt != null)) continue;
      _applyRemote(remote, user);
    }
    await _saveFolders();
    notifyListeners();
    await prefs.setInt(_revisionKey(user), changes['revision']! as int);

    String? problem;
    for (final folder in [
      for (final f in _all)
        if (f.account == user && f.deletedAt != null) f,
    ]) {
      final answer = await client.delete(
        folder.id,
        folder.revision,
        folder.deletedAt!.millisecondsSinceEpoch,
      );
      problem ??= _check(answer, keepGoing: true);
      if (answer.body is! Map) continue;
      final remote = answer.body! as Map<String, Object?>;
      if (remote['deleted'] == true) {
        _all = [
          for (final f in _all)
            if (f.id != folder.id || f.account != user) f,
        ];
      } else {
        _applyRemote(remote, user);
      }
    }
    for (final folder in [
      for (final f in _all)
        if (f.account == user && f.dirty && f.deletedAt == null) f,
    ]) {
      final answer = await client.put(folder.id, _toJson(folder));
      problem ??= _check(answer, keepGoing: true);
      if (answer.body is! Map) continue;
      final remote = answer.body! as Map<String, Object?>;
      final now = _all.where((f) => f.id == folder.id).firstOrNull;
      if (now == null) continue;
      // Changed again here while this was being sent: the answer's revision is the base the
      // newer change goes with next time; its items would undo that change.
      if (remote['deleted'] != true &&
          (now.updatedAt != folder.updatedAt ||
              now.deletedAt != null ||
              !listEquals(now.items, folder.items))) {
        _replace(folder.id, now.copyWith(revision: remote['revision']! as int));
        continue;
      }
      _applyRemote(remote, user);
    }
    return problem;
  }

  void _replace(String id, LibraryFolder? folder) => _all = [
    for (final f in _all)
      if (f.id != id) f else ?folder,
  ];

  /// Stores MusicDatabase's [remote] folder as [user]'s, in place of the one with its uid.
  /// Its items take the playlists and moods out of any other folder here.
  void _applyRemote(Map<String, Object?> remote, String user) {
    final uid = remote['uid']! as String;
    if (remote['deleted'] == true) {
      _replace(uid, null);
      return;
    }
    final items = <String>[];
    final refs = <String, String>{};
    final pending = <String>[];
    for (final item in remote['items'] as List? ?? const []) {
      final ref = FolderRefs.fromWire(item);
      if (ref == null) continue;
      final key = _keyOfRef[ref];
      if (key == null) {
        pending.add(ref);
      } else if (!items.contains(key)) {
        items.add(key);
        refs[key] = ref;
      }
    }
    final folder = LibraryFolder(
      id: uid,
      name: remote['name'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        remote['created_at'] as int? ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        remote['updated_at'] as int? ?? 0,
      ),
      items: items,
      account: user,
      revision: remote['revision'] as int? ?? 0,
      refs: refs,
      pending: pending,
    );
    final existed = _all.any((f) => f.id == uid);
    _all = [
      for (final f in _all)
        if (f.id == uid)
          folder
        else if (_visibleTo(f, user) && f.items.any(items.contains))
          f.copyWith(items: [...f.items.where((k) => !items.contains(k))])
        else
          f,
      if (!existed) folder,
    ];
  }

  bool _visibleTo(LibraryFolder f, String user) =>
      f.deletedAt == null && (f.account == null || f.account == user);

  /// [folder] as MusicDatabase's PUT body: the whole folder and the revision it's based on.
  Map<String, Object?> _toJson(LibraryFolder folder) {
    final withRefs = _withRefs(folder);
    return {
      'uid': folder.id,
      'base_revision': folder.revision,
      'name': folder.name,
      'created_at': folder.createdAt.millisecondsSinceEpoch,
      'updated_at': folder.updatedAt.millisecondsSinceEpoch,
      'items': [
        for (final key in folder.items)
          if (withRefs.refs[key] case final ref?) ?FolderRefs.toWire(ref),
        for (final ref in folder.pending) ?FolderRefs.toWire(ref),
      ],
    };
  }

  /// Throws [_SyncStopped] for answers that end this sync and returns the problem of one
  /// folder's answer otherwise; `null` when it went.
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
          'Serwer MusicDatabase nie może teraz zapisać folderów (dysk niepodłączony lub '
          'baza użytkownika jeszcze nieprzygotowana)',
        );
      case HttpStatus.notFound when !keepGoing:
        throw const _SyncStopped(
          'Serwer MusicDatabase nie obsługuje jeszcze folderów',
        );
    }
    final problem = 'Serwer odrzucił folder (HTTP ${answer.status})';
    if (keepGoing) return problem;
    throw _SyncStopped(problem);
  }

  /// Biblioteka's rows: [playlists] and [moods] not in a folder, plus the folders with what's in
  /// them of these. A folder with none of them is left out unless [keepEmptyFolders] (a filter
  /// passes [playlists] or [moods] only, and shows just the folders holding those). Sorted by
  /// [sort].
  List<LibraryEntry> entries({
    required List<PlaylistSummary> playlists,
    required List<Mood> moods,
    bool keepEmptyFolders = true,
  }) {
    final items = <LibraryEntry>[
      for (final p in playlists) PlaylistEntry(p),
      for (final m in moods) MoodEntry(m),
    ];
    final byKey = {for (final item in items) item.key: item};
    final inFolders = <String>{};
    final folders = <LibraryEntry>[];
    for (final folder in this.folders) {
      final contents = [for (final key in folder.items) ?byKey[key]];
      inFolders.addAll(folder.items);
      if (contents.isEmpty && !keepEmptyFolders) continue;
      folders.add(FolderEntry(folder, sorted(contents)));
    }
    return sorted([
      ...folders,
      ...items.where((item) => !inFolders.contains(item.key)),
    ]);
  }

  /// [entries] in the order [sort] gives.
  List<LibraryEntry> sorted(List<LibraryEntry> entries) {
    int byName(LibraryEntry a, LibraryEntry b) =>
        normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name));
    // Newest first; entries without a time go last.
    int newest(DateTime? a, DateTime? b) => a == null
        ? (b == null ? 0 : 1)
        : b == null
        ? -1
        : b.compareTo(a);
    final compare = switch (_sort) {
      LibrarySort.recent => (LibraryEntry a, LibraryEntry b) => newest(
        _recency(a),
        _recency(b),
      ),
      LibrarySort.added => (LibraryEntry a, LibraryEntry b) => newest(
        a.createdAt,
        b.createdAt,
      ),
      LibrarySort.alphabetical => byName,
      LibrarySort.creator => (LibraryEntry a, LibraryEntry b) {
        final (ca, cb) = (a.creator, b.creator);
        if (ca == null || cb == null) {
          return ca == cb ? 0 : (ca == null ? -1 : 1);
        }
        return normalizeForSearch(ca).compareTo(normalizeForSearch(cb));
      },
    };
    // Ties keep the name order (List.sort isn't stable).
    final indexed = ([...entries]..sort(byName)).indexed.toList()
      ..sort((a, b) {
        final c = compare(a.$2, b.$2);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return [for (final (_, entry) in indexed) entry];
  }

  /// When [entry] was last opened, else changed; a folder: the latest of itself and its items.
  DateTime? _recency(LibraryEntry entry) {
    final times = [
      openedAt(entry.key) ?? entry.changedAt,
      if (entry is FolderEntry) ...entry.contents.map(_recency),
    ].nonNulls;
    return times.isEmpty ? null : times.reduce((a, b) => a.isAfter(b) ? a : b);
  }
}

/// An answer that ends a [LibraryFolders.sync] early, with why (Polish, for display).
class _SyncStopped implements Exception {
  const _SyncStopped(this.problem);

  final String problem;
}

class LibraryFoldersScope extends InheritedNotifier<LibraryFolders> {
  const LibraryFoldersScope({
    super.key,
    required LibraryFolders super.notifier,
    required super.child,
  });

  static LibraryFolders of(BuildContext context) => maybeOf(context)!;

  /// `null` in widget tests that don't set it up.
  static LibraryFolders? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LibraryFoldersScope>()
      ?.notifier;

  /// Like [maybeOf] without rebuilding on changes, e.g. from `initState`.
  static LibraryFolders? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LibraryFoldersScope>()?.notifier;
}
