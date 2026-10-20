import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'combined_search.dart';
import 'item_sync.dart';
import 'track_ref.dart';

/// One song of a [StoredSongList].
class StoredSong {
  const StoredSong({
    required this.uid,
    required this.ref,
    required this.addedAt,
    required this.sync,
  });

  /// [json] as saved by [toJson], or a bare [TrackRef] from before the lists synced.
  factory StoredSong.fromJson(
    Map<String, Object?> json, {
    required String list,
    required DateTime fallbackTime,
  }) {
    if (json['uid'] is! String) {
      final ref = TrackRef.fromJson(json);
      return StoredSong(
        uid: songUid(list, ref),
        ref: ref,
        addedAt: fallbackTime,
        // As old as can be: a song removed on another phone since stays removed.
        sync: SyncFields(updatedAt: DateTime.fromMillisecondsSinceEpoch(1)),
      );
    }
    final addedAt = DateTime.fromMillisecondsSinceEpoch(
      json['addedAt'] as int? ?? 0,
    );
    return StoredSong(
      uid: json['uid']! as String,
      ref: TrackRef.fromJson((json['song']! as Map).cast<String, Object?>()),
      addedAt: addedAt,
      sync: SyncFields.fromJson(json, fallbackTime: addedAt),
    );
  }

  /// Shared with MusicDatabase; the same song on the same list gets the same one on every
  /// phone, so liking it on two phones is one item there.
  final String uid;
  final TrackRef ref;

  /// When it was put on the list (newest on top).
  final DateTime addedAt;
  final SyncFields sync;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'song': ref.toJson(),
    'addedAt': addedAt.millisecondsSinceEpoch,
    ...sync.toJson(),
  };

  StoredSong copyWith({TrackRef? ref, DateTime? addedAt, SyncFields? sync}) =>
      StoredSong(
        uid: uid,
        ref: ref ?? this.ref,
        addedAt: addedAt ?? this.addedAt,
        sync: sync ?? this.sync,
      );
}

/// [StoredSong.uid] of [ref] on [list].
String songUid(String list, TrackRef ref) =>
    sha1.convert(utf8.encode('$list|${ref.key}')).toString();

/// A list of songs, newest first, kept in `shared_preferences` — [SavedSongs] and
/// [LikedSongs]. The logged-in account's songs sync with MusicDatabase through
/// [SavedSongsSync]; songs added while logged out stay on the phone until the next login.
class StoredSongList extends ChangeNotifier {
  StoredSongList(
    this._key,
    this.list, {
    DateTime Function()? now,
    String? Function()? userName,
  }) : _now = now ?? DateTime.now,
       _userName = userName ?? (() => null);

  final String _key;

  /// Its name on the wire: `liked` or `later`.
  final String list;
  final DateTime Function() _now;
  final String? Function() _userName;

  /// A song was added or removed here.
  VoidCallback? onChanged;

  /// Every account's songs, phone-only ones and deletions not sent yet.
  List<StoredSong> _all = const [];
  List<TrackRef>? _songs;

  /// The songs shown: phone-only ones and the logged-in account's, newest first.
  List<TrackRef> get songs => _songs ??= _visibleSongs();

  List<TrackRef> _visibleSongs() {
    final user = _userName();
    final seen = <String>{};
    return [
      for (final s in [
        ..._all.where((s) => s.sync.visibleTo(user)),
      ]..sort((a, b) => b.addedAt.compareTo(a.addedAt)))
        if (seen.add(s.ref.key)) s.ref,
    ];
  }

  /// Every stored song, for [SavedSongsSync].
  List<StoredSong> get all => _all;

  set all(List<StoredSong> songs) {
    _all = songs;
    _songs = null;
    notifyListeners();
  }

  /// Logging in or out shows other songs.
  void accountChanged() {
    _songs = null;
    notifyListeners();
  }

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    final now = _now().millisecondsSinceEpoch;
    _all = [
      // Stored before syncing: newest first, without times.
      for (final (i, json) in (jsonDecode(raw) as List).indexed)
        StoredSong.fromJson(
          (json as Map).cast<String, Object?>(),
          list: list,
          fallbackTime: DateTime.fromMillisecondsSinceEpoch(now - i),
        ),
    ];
    _songs = null;
    notifyListeners();
  }

  Future<void> save() async => (await SharedPreferences.getInstance())
      .setString(_key, jsonEncode([for (final s in _all) s.toJson()]));

  bool contains(SearchHit hit) {
    final key = TrackRef.of(hit).key;
    return songs.any((s) => s.key == key);
  }

  /// Whether every one of [hits] is in the list (`false` for none).
  bool containsAll(List<SearchHit> hits) =>
      hits.isNotEmpty && hits.every(contains);

  /// Saves [hit], or takes it out when already saved; returns whether it's saved now.
  Future<bool> toggle(SearchHit hit) async {
    final saved = !contains(hit);
    await setAll([hit], saved);
    return saved;
  }

  /// Puts [hits] on top of the list ([saved]), in their order, or takes them out.
  Future<void> setAll(List<SearchHit> hits, bool saved) async {
    final user = _userName();
    final now = _now().millisecondsSinceEpoch;
    final refs = <String, TrackRef>{};
    for (final hit in hits) {
      final ref = TrackRef.of(hit);
      refs.putIfAbsent(ref.key, () => ref);
    }
    final changedAt = DateTime.fromMillisecondsSinceEpoch(now);
    var all = <StoredSong>[];
    for (final s in _all) {
      if (!s.sync.visibleTo(user) || !refs.containsKey(s.ref.key)) {
        all.add(s);
      } else if (!saved) {
        if (s.sync.deleted(changedAt) case final sync?) {
          all.add(s.copyWith(sync: sync));
        }
      }
    }
    if (saved) {
      for (final (i, ref) in refs.values.indexed) {
        final uid = songUid(list, ref);
        final marker = all
            .where((s) => s.uid == uid && s.sync.account == user)
            .firstOrNull;
        all = [
          for (final s in all)
            if (s != marker) s,
          StoredSong(
            uid: uid,
            ref: ref,
            addedAt: DateTime.fromMillisecondsSinceEpoch(now - i),
            sync: SyncFields(
              updatedAt: changedAt,
              account: user,
              revision: marker?.sync.revision ?? 0,
              dirty: user != null,
            ),
          ),
        ];
      }
    }
    _all = all;
    _songs = null;
    notifyListeners();
    await save();
    onChanged?.call();
  }
}

/// Songs saved to listen to later — kept apart from playlists and liked songs, so trying
/// something out doesn't mix it into the user's favourites (Juxtopposed's Spotify redesign).
/// Newest first (Biblioteka › Na później).
class SavedSongs extends StoredSongList {
  SavedSongs({super.now, super.userName}) : super('saved_songs', 'later');
}

/// Liked songs, like Spotify's "Polubione utwory": liked from the "Dodaj do playlisty" sheet.
/// Newest first (Biblioteka › Polubione utwory).
class LikedSongs extends StoredSongList {
  LikedSongs({super.now, super.userName}) : super('liked_songs', 'liked');
}

/// Exchanges [SavedSongs] and [LikedSongs] with the logged-in account
/// (`/users/<name>/saved-songs`, both lists together, one song per item —
/// [ADR 0013](../../../docs/decisions/0013-saved-songs-sync.md)).
class SavedSongsSync extends ItemSync {
  SavedSongsSync(
    this.lists, {
    super.now,
    super.userName,
    super.authToken,
    int Function(int songId)? currentSongId,
  }) : _currentSongId = currentSongId ?? ((id) => id),
       super(
         collection: 'saved-songs',
         field: 'songs',
         problemNoun: 'polubionych i zapisanych utworów',
       ) {
    for (final list in lists) {
      list.onChanged = () => onChanged?.call();
    }
  }

  final List<StoredSongList> lists;

  /// The music.db id a kept one has now ([SongCatalog.current]): MusicDatabase may have merged
  /// the song since.
  final int Function(int songId) _currentSongId;

  int? _songId(TrackRef ref) =>
      ref.mainDbId == null ? null : _currentSongId(ref.mainDbId!);

  StoredSongList? _list(String? name) =>
      lists.where((l) => l.list == name).firstOrNull;

  ({StoredSongList list, StoredSong song})? _find(String uid, String user) {
    for (final list in lists) {
      for (final song in list.all) {
        if (song.uid == uid && song.sync.account == user) {
          return (list: list, song: song);
        }
      }
    }
    return null;
  }

  @override
  Future<void> adoptPhoneOnly(String user) async {
    for (final list in lists) {
      if (list.all.every((s) => s.sync.account != null)) continue;
      final mine = {
        for (final s in list.all)
          if (s.sync.account == user) s.uid: s,
      };
      final adopted = <String, StoredSong>{};
      for (final s in list.all) {
        if (s.sync.account != null) continue;
        final there = mine[s.uid];
        // On the account already, changed later there: the phone-only copy goes.
        if (there != null && !s.sync.updatedAt.isAfter(there.sync.updatedAt)) {
          continue;
        }
        adopted[s.uid] = s.copyWith(
          sync: SyncFields(
            updatedAt: s.sync.updatedAt,
            account: user,
            revision: there?.sync.revision ?? 0,
            dirty: true,
          ),
        );
      }
      list.all = [
        for (final s in list.all)
          if (s.sync.account != null &&
              !(s.sync.account == user && adopted.containsKey(s.uid)))
            s,
        ...adopted.values,
      ];
      await list.save();
    }
  }

  @override
  bool changedHere(String uid, String user) =>
      _find(uid, user)?.song.sync.unsent ?? false;

  @override
  List<ItemDeletion> deletionsOf(String user) => [
    for (final list in lists)
      for (final s in list.all)
        if (s.sync.account == user && s.sync.deletedAt != null)
          (uid: s.uid, revision: s.sync.revision, deletedAt: s.sync.deletedAt!),
  ];

  @override
  List<Map<String, Object?>> changesOf(String user) => [
    for (final list in lists)
      for (final s in list.all)
        if (s.sync.account == user && s.sync.dirty && s.sync.deletedAt == null)
          {
            'uid': s.uid,
            'base_revision': s.sync.revision,
            'list': list.list,
            'added_at': s.addedAt.millisecondsSinceEpoch,
            'updated_at': s.sync.updatedAt.millisecondsSinceEpoch,
            'song': {
              'song_id': ?_songId(s.ref),
              'title': s.ref.title,
              'artist': ?s.ref.artist,
              'video_id': ?s.ref.videoId,
              'playlist_video_id': ?s.ref.playlistVideoId,
              'spotify_track_id': ?s.ref.spotifyTrackId,
            },
          },
  ];

  @override
  Future<void> applyRemote(
    Map<String, Object?> remote,
    String user, {
    DateTime? sentUpdatedAt,
    DateTime? sentDeletedAt,
  }) async {
    final uid = remote['uid']! as String;
    final local = _find(uid, user);
    final revision = remote['revision'] as int? ?? 0;
    final answer = answerFor(
      remote,
      local?.song.sync,
      sentUpdatedAt: sentUpdatedAt,
      sentDeletedAt: sentDeletedAt,
    );
    if (local != null && answer == RemoteAnswer.rebase) {
      local.list.all = [
        for (final s in local.list.all)
          s == local.song
              ? s.copyWith(sync: s.sync.copyWith(revision: revision))
              : s,
      ];
      return;
    }
    final song = remote['song'];
    final list = remote['deleted'] != true && song is Map
        ? _list(remote['list'] as String?)
        : null;
    if (local != null) {
      local.list.all = [
        for (final s in local.list.all)
          if (s != local.song) s,
      ];
    }
    if (list == null || song is! Map) return;
    final addedAt = DateTime.fromMillisecondsSinceEpoch(
      remote['added_at'] as int? ?? 0,
    );
    final json = song.cast<String, Object?>();
    list.all = [
      ...list.all,
      StoredSong(
        uid: uid,
        ref: TrackRef(
          title: json['title'] as String? ?? '',
          artist: json['artist'] as String?,
          mainDbId: json['song_id'] as int?,
          videoId: json['video_id'] as String?,
          playlistVideoId: json['playlist_video_id'] as String?,
          spotifyTrackId: json['spotify_track_id'] as String?,
        ),
        addedAt: addedAt,
        sync: SyncFields(
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            remote['updated_at'] as int? ?? addedAt.millisecondsSinceEpoch,
          ),
          account: user,
          revision: revision,
        ),
      ),
    ];
  }

  @override
  Future<void> saveItems() async {
    for (final list in lists) {
      await list.save();
    }
  }
}

class SavedSongsScope extends InheritedNotifier<SavedSongs> {
  const SavedSongsScope({
    super.key,
    required SavedSongs super.notifier,
    required super.child,
  });

  /// `null` in widget tests that don't set it up.
  static SavedSongs? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SavedSongsScope>()?.notifier;
}

class LikedSongsScope extends InheritedNotifier<LikedSongs> {
  const LikedSongsScope({
    super.key,
    required LikedSongs super.notifier,
    required super.child,
  });

  /// `null` in widget tests that don't set it up.
  static LikedSongs? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LikedSongsScope>()?.notifier;
}

class SavedSongsSyncScope extends InheritedNotifier<SavedSongsSync> {
  const SavedSongsSyncScope({
    super.key,
    required SavedSongsSync super.notifier,
    required super.child,
  });

  /// `null` in widget tests that don't set it up.
  static SavedSongsSync? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SavedSongsSyncScope>()
      ?.notifier;
}
