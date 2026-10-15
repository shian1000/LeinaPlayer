import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'moods.dart';
import 'playlist_library.dart';
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
    this.items = const [],
  });

  factory LibraryFolder.fromJson(Map<String, Object?> json) => LibraryFolder(
    id: json['id']! as String,
    name: json['name'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      json['createdAt'] as int? ?? 0,
    ),
    items: [...?(json['items'] as List?)?.cast<String>()],
  );

  final String id;
  final String name;
  final DateTime createdAt;

  /// [LibraryFolders.playlistKey]s and [Mood.key]s, in the order they were put in.
  final List<String> items;

  /// Its key among Biblioteka's items (for "Ostatnie").
  String get key => 'f$id';

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'items': items,
  };

  LibraryFolder copyWith({String? name, List<String>? items}) => LibraryFolder(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    items: items ?? this.items,
  );
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
/// (for "Ostatnie"). Kept only on this phone, in `shared_preferences` — MusicDatabase knows
/// nothing of folders (not synced, unlike the playlists and moods in them).
///
/// An item is in at most one folder; folders don't nest.
class LibraryFolders extends ChangeNotifier {
  LibraryFolders({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const _foldersKey = 'library.folders';
  static const _sortKey = 'library.sort';
  static const _openedKey = 'library.opened';

  final DateTime Function() _now;

  List<LibraryFolder> _folders = const [];
  LibrarySort _sort = LibrarySort.recent;
  Map<String, int> _opened = const {};

  List<LibraryFolder> get folders => _folders;
  LibrarySort get sort => _sort;

  static String playlistKey(int playlistId) => 'p$playlistId';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final folders = jsonDecode(prefs.getString(_foldersKey) ?? '[]') as List;
      _folders = [
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

  Future<void> _saveFolders() async =>
      (await SharedPreferences.getInstance()).setString(
        _foldersKey,
        jsonEncode([for (final f in _folders) f.toJson()]),
      );

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
      _folders.where((f) => f.id == id).firstOrNull;

  /// The folder [itemKey] is in, if any.
  LibraryFolder? folderOf(String itemKey) =>
      _folders.where((f) => f.items.contains(itemKey)).firstOrNull;

  Future<LibraryFolder> create(String name) async {
    final now = _now();
    final folder = LibraryFolder(
      id: now.microsecondsSinceEpoch.toRadixString(36),
      name: name.trim(),
      createdAt: now,
    );
    _folders = [..._folders, folder];
    notifyListeners();
    await _saveFolders();
    return folder;
  }

  Future<void> rename(String folderId, String name) =>
      _update((f) => f.id == folderId ? f.copyWith(name: name.trim()) : f);

  /// Removes the folder; what was in it goes back to Biblioteka's top level.
  Future<void> delete(String folderId) async {
    _folders = [
      for (final f in _folders)
        if (f.id != folderId) f,
    ];
    notifyListeners();
    await _saveFolders();
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

  Future<void> _update(LibraryFolder Function(LibraryFolder) change) async {
    _folders = [for (final f in _folders) change(f)];
    notifyListeners();
    await _saveFolders();
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
    for (final folder in _folders) {
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
