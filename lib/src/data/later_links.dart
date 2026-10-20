import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'incoming_links.dart';
import 'item_sync.dart';
import 'local_library.dart';
import 'playlist_library.dart';
import 'song_catalog.dart';
import 'source_settings.dart';
import 'spotify_playlist.dart';
import 'video_link.dart';
import 'youtube_library.dart';
import 'youtube_search.dart';

/// Someone who sends links ("Od kogo?" in the link sheet).
class LaterPerson {
  const LaterPerson({required this.id, required this.name, this.usedAt});

  factory LaterPerson.fromJson(Map<String, Object?> json) => LaterPerson(
    id: json['id']! as String,
    name: json['name'] as String? ?? '',
    usedAt: _time(json['usedAt']),
  );

  final String id;
  final String name;

  /// When a link was last saved from them.
  final DateTime? usedAt;
}

/// A link saved for later from the link sheet ("Zapisz na później").
class LaterLink {
  LaterLink({
    required this.id,
    required this.url,
    required this.service,
    required this.kind,
    required this.personId,
    required this.savedAt,
    this.title,
    this.artist,
    this.openedAt,
    SyncFields? sync,
  }) : sync = sync ?? SyncFields(updatedAt: savedAt);

  factory LaterLink.fromJson(Map<String, Object?> json) {
    final savedAt =
        _time(json['savedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return LaterLink(
      id: json['id']! as String,
      url: json['url']! as String,
      service: json['service'] == 'spotify'
          ? LinkService.spotify
          : LinkService.youtube,
      kind: json['kind'] as String? ?? 'Link',
      personId: json['personId'] as String? ?? '',
      savedAt: savedAt,
      title: json['title'] as String?,
      artist: json['artist'] as String?,
      openedAt: _time(json['openedAt']),
      sync: SyncFields.fromJson(json, fallbackTime: savedAt),
    );
  }

  final String id;
  final String url;
  final LinkService service;

  /// What the address says it is, from the sheet: "Film z YouTube", "Album ze Spotify"…
  final String kind;
  final String personId;
  final DateTime savedAt;

  /// Found by the app later ([describeLaterLink]); `null` until then.
  final String? title;
  final String? artist;

  /// When it was last opened from "Na później"; `null`: not listened to yet.
  final DateTime? openedAt;

  bool get opened => openedAt != null;

  /// Its sync with the logged-in account ([LaterLinks.sync]); a link the sheet saved has none
  /// yet (a phone-only one, given to the account by the next sync).
  final SyncFields sync;
}

DateTime? _time(Object? millis) => millis is num && millis > 0
    ? DateTime.fromMillisecondsSinceEpoch(millis.toInt())
    : null;

/// Where the saved links are kept: natively on Android ([ChannelLaterStore] — the sheet saves
/// without Flutter), in memory elsewhere and in tests.
abstract class LaterStore {
  Future<({List<LaterPerson> people, List<LaterLink> links})> load();
  Future<String> addPerson(String name);
  Future<void> renamePerson(String id, String name);

  /// The person and every link from them.
  Future<void> removePerson(String id);

  /// [fields] as JSON values; `null` clears one.
  Future<void> updateLink(String id, Map<String, Object?> fields);
  Future<void> removeLink(String id);

  /// Stores [link] (JSON values, with its `id`) in place of the one with its id, or as a new one.
  Future<void> putLink(Map<String, Object?> link);
}

/// `LaterLinks.kt` behind the links channel.
class ChannelLaterStore implements LaterStore {
  static const _channel = MethodChannel('music_database_app/links');

  @override
  Future<({List<LaterPerson> people, List<LaterLink> links})> load() async {
    final raw = await _channel.invokeMethod<String>('laterLinks');
    final json = raw == null
        ? const <String, Object?>{}
        : jsonDecode(raw) as Map<String, Object?>;
    List<Map<String, Object?>> list(String key) =>
        ((json[key] as List<Object?>?) ?? const [])
            .cast<Map<String, Object?>>();
    return (
      people: list('people').map(LaterPerson.fromJson).toList(),
      links: list('links').map(LaterLink.fromJson).toList(),
    );
  }

  @override
  Future<String> addPerson(String name) async =>
      (await _channel.invokeMethod<String>('addLaterPerson', {'name': name}))!;

  @override
  Future<void> renamePerson(String id, String name) => _channel
      .invokeMethod<void>('renameLaterPerson', {'id': id, 'name': name});

  @override
  Future<void> removePerson(String id) =>
      _channel.invokeMethod<void>('removeLaterPerson', {'id': id});

  @override
  Future<void> updateLink(String id, Map<String, Object?> fields) => _channel
      .invokeMethod<void>('updateLaterLink', {'id': id, 'fields': fields});

  @override
  Future<void> removeLink(String id) =>
      _channel.invokeMethod<void>('removeLaterLink', {'id': id});

  @override
  Future<void> putLink(Map<String, Object?> link) =>
      _channel.invokeMethod<void>('putLaterLink', {'link': link});
}

/// Kept in memory only: off Android (nothing saves there) and in tests ([save] stands in for
/// the sheet).
class MemoryLaterStore implements LaterStore {
  final _people = <Map<String, Object?>>[];
  final _links = <Map<String, Object?>>[];
  var _next = 0;

  /// What the link sheet does with "Zapisz na później".
  void save({
    required String url,
    required LinkService service,
    required String kind,
    required String personId,
    DateTime? at,
  }) {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final same = _links
        .where(
          (l) =>
              l['url'] == url &&
              l['personId'] == personId &&
              l['deletedAt'] == null,
        )
        .firstOrNull;
    if (same != null) {
      same
        ..['savedAt'] = now
        ..['updatedAt'] = now
        ..remove('openedAt');
      if (same['account'] != null) same['dirty'] = true;
    } else {
      _links.add({
        'id': 'l${_next++}',
        'url': url,
        'service': service.name,
        'kind': kind,
        'personId': personId,
        'savedAt': now,
      });
    }
    _people.firstWhere((p) => p['id'] == personId)['usedAt'] = now;
  }

  @override
  Future<({List<LaterPerson> people, List<LaterLink> links})> load() async => (
    people: _people.map((p) => LaterPerson.fromJson({...p})).toList(),
    links: _links.map((l) => LaterLink.fromJson({...l})).toList(),
  );

  @override
  Future<String> addPerson(String name) async {
    final existing = _people
        .where(
          (p) => (p['name']! as String).toLowerCase() == name.toLowerCase(),
        )
        .firstOrNull;
    if (existing != null) return existing['id']! as String;
    final id = 'p${_next++}';
    _people.add({'id': id, 'name': name});
    return id;
  }

  @override
  Future<void> renamePerson(String id, String name) async {
    _people.firstWhere((p) => p['id'] == id)['name'] = name;
  }

  @override
  Future<void> removePerson(String id) async {
    _people.removeWhere((p) => p['id'] == id);
    _links.removeWhere((l) => l['personId'] == id);
  }

  @override
  Future<void> updateLink(String id, Map<String, Object?> fields) async {
    final link = _links.firstWhere((l) => l['id'] == id);
    for (final MapEntry(:key, :value) in fields.entries) {
      if (value == null) {
        link.remove(key);
      } else {
        link[key] = value;
      }
    }
  }

  @override
  Future<void> removeLink(String id) async =>
      _links.removeWhere((l) => l['id'] == id);

  @override
  Future<void> putLink(Map<String, Object?> link) async {
    _links
      ..removeWhere((l) => l['id'] == link['id'])
      ..add({for (final MapEntry(:key, :value) in link.entries) key: ?value});
  }
}

/// "Na później" (Ja › Na później): links people sent, saved from the link sheet. Re-read
/// whenever the app comes back to the front, since the sheet saves while the app is in the
/// background. The logged-in account's links sync with MusicDatabase
/// (`/users/<name>/later-links`, one link per item, the sender by name —
/// [ADR 0013](../../../docs/decisions/0013-saved-songs-sync.md)); the people themselves stay on
/// each phone.
class LaterLinks extends ItemSync {
  LaterLinks([LaterStore? store]) : this.synced(store: store);

  LaterLinks.synced({
    LaterStore? store,
    super.now,
    super.userName,
    super.authToken,
  }) : _store =
           store ??
           (!kIsWeb && Platform.isAndroid
               ? ChannelLaterStore()
               : MemoryLaterStore()),
       super(
         collection: 'later-links',
         field: 'links',
         problemNoun: 'linków na później',
       );

  final LaterStore _store;
  List<LaterPerson> _people = const [];

  /// Every account's links, phone-only ones and deletions not sent yet.
  List<LaterLink> _all = const [];
  List<LaterLink> _links = const [];

  /// Alphabetical.
  List<LaterPerson> get people => _people;

  /// The links shown (phone-only ones and the logged-in account's), newest first.
  List<LaterLink> get links => _links;

  int get unopenedCount => _links.where((l) => !l.opened).length;

  LaterPerson? personOf(LaterLink link) =>
      _people.where((p) => p.id == link.personId).firstOrNull;

  Future<void> load() async {
    try {
      final data = await _store.load();
      _people = [...data.people]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _all = data.links;
      _showLinks();
    } on PlatformException catch (e) {
      debugPrint('Reading links saved for later failed: $e');
    }
  }

  void _showLinks() {
    final user = userName();
    _links = [
      for (final l in _all)
        if (l.sync.visibleTo(user)) l,
    ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    notifyListeners();
  }

  /// Logging in or out shows other links.
  void accountChanged() => _showLinks();

  /// What [link]'s change at [at] does to its sync fields.
  Map<String, Object?> _changedFields(LaterLink link, DateTime at) => {
    'updatedAt': at.millisecondsSinceEpoch,
    if (link.sync.account != null) 'dirty': true,
  };

  DateTime _now() =>
      DateTime.fromMillisecondsSinceEpoch(now().millisecondsSinceEpoch);

  Future<void> _change(LaterLink link, Map<String, Object?> fields) async {
    await _store.updateLink(link.id, {
      ...fields,
      ..._changedFields(link, _now()),
    });
    await load();
    onChanged?.call();
  }

  Future<String> addPerson(String name) async {
    final id = await _store.addPerson(name.trim());
    await load();
    return id;
  }

  /// Renamed here only, but the account's links from them go again under the new name.
  Future<void> renamePerson(LaterPerson person, String name) async {
    await _store.renamePerson(person.id, name.trim());
    final at = _now();
    var changed = false;
    for (final link in _all) {
      if (link.personId != person.id || link.sync.account == null) continue;
      await _store.updateLink(link.id, _changedFields(link, at));
      changed = true;
    }
    await load();
    if (changed) onChanged?.call();
  }

  /// The person and every link from them (everywhere, for the account's links).
  Future<void> removePerson(LaterPerson person) async {
    final at = _now();
    var changed = false;
    for (final link in _all) {
      if (link.personId != person.id) continue;
      changed |= await _delete(link, at);
    }
    await _store.removePerson(person.id);
    await load();
    if (changed) onChanged?.call();
  }

  Future<void> setPerson(LaterLink link, String personId) =>
      _change(link, {'personId': personId});

  Future<void> setOpened(LaterLink link, bool opened) => _change(link, {
    'openedAt': opened ? _now().millisecondsSinceEpoch : null,
  });

  Future<void> setDescription(LaterLink link, String title, String? artist) =>
      _change(link, {'title': title, 'artist': artist});

  Future<void> remove(LaterLink link) async {
    final synced = await _delete(link, _now());
    await load();
    if (synced) onChanged?.call();
  }

  /// Removes [link], leaving a marker (without its person, so removing them keeps it) when
  /// it's an account's; returns whether it did.
  Future<bool> _delete(LaterLink link, DateTime at) async {
    if (link.sync.account == null) {
      await _store.removeLink(link.id);
      return false;
    }
    await _store.updateLink(link.id, {
      'personId': '',
      'deletedAt': at.millisecondsSinceEpoch,
      'updatedAt': at.millisecondsSinceEpoch,
      'dirty': false,
    });
    return true;
  }

  LaterLink? _find(String uid, String user) =>
      _all.where((l) => l.id == uid && l.sync.account == user).firstOrNull;

  /// The store's copy changed during a sync: [saveItems] reads it again.
  var _stale = false;

  @override
  Future<void> adoptPhoneOnly(String user) async {
    await load();
    for (final link in _all) {
      if (link.sync.account != null) continue;
      await _store.updateLink(link.id, {
        'account': user,
        'revision': 0,
        'dirty': true,
        'updatedAt': link.sync.updatedAt.millisecondsSinceEpoch,
      });
      _stale = true;
    }
    await saveItems();
  }

  @override
  bool changedHere(String uid, String user) =>
      _find(uid, user)?.sync.unsent ?? false;

  @override
  List<ItemDeletion> deletionsOf(String user) => [
    for (final l in _all)
      if (l.sync.account == user && l.sync.deletedAt != null)
        (uid: l.id, revision: l.sync.revision, deletedAt: l.sync.deletedAt!),
  ];

  @override
  List<Map<String, Object?>> changesOf(String user) => [
    for (final l in _all)
      if (l.sync.account == user && l.sync.dirty && l.sync.deletedAt == null)
        {
          'uid': l.id,
          'base_revision': l.sync.revision,
          'url': l.url,
          'service': l.service.name,
          'kind': l.kind,
          'person': personOf(l)?.name ?? '',
          'saved_at': l.savedAt.millisecondsSinceEpoch,
          'opened_at': l.openedAt?.millisecondsSinceEpoch,
          'title': l.title,
          'artist': l.artist,
          'updated_at': l.sync.updatedAt.millisecondsSinceEpoch,
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
      local?.sync,
      sentUpdatedAt: sentUpdatedAt,
      sentDeletedAt: sentDeletedAt,
    );
    _stale = true;
    if (local != null && answer == RemoteAnswer.rebase) {
      await _store.updateLink(uid, {'revision': revision});
      return;
    }
    final url = remote['url'];
    if (remote['deleted'] == true || url is! String) {
      if (local != null) await _store.removeLink(uid);
      return;
    }
    final name = (remote['person'] as String? ?? '').trim();
    final savedAt = remote['saved_at'] as int? ?? 0;
    await _store.putLink({
      'id': uid,
      'url': url,
      'service': remote['service'] == 'spotify' ? 'spotify' : 'youtube',
      'kind': remote['kind'] as String? ?? 'Link',
      'personId': await _store.addPerson(name.isEmpty ? '?' : name),
      'savedAt': savedAt,
      'openedAt': remote['opened_at'] as int?,
      'title': remote['title'] as String?,
      'artist': remote['artist'] as String?,
      'updatedAt': remote['updated_at'] as int? ?? savedAt,
      'account': user,
      'revision': revision,
      'dirty': false,
    });
  }

  @override
  Future<void> saveItems() async {
    if (!_stale) return;
    _stale = false;
    await load();
  }
}

class LaterLinksScope extends InheritedNotifier<LaterLinks> {
  const LaterLinksScope({
    super.key,
    required LaterLinks super.notifier,
    required super.child,
  });

  static LaterLinks of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LaterLinksScope>()!.notifier!;

  static LaterLinks? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LaterLinksScope>()?.notifier;
}

/// What a saved link is, for its row: the song (title and artist) for a video or track, the
/// name for a Spotify playlist or album; `null` when it can't be told (a YouTube playlist —
/// reading it would fetch the whole of it — or no connection). Recognised the way opening it
/// does ([hitForVideoLink], [hitForSpotifyTrack]).
Future<({String title, String? artist})?> describeLaterLink(
  LaterLink link, {
  required SongCatalog catalog,
  required LocalLibrary library,
  required YouTubeLibrary youTube,
  required PlaylistLibrary playlists,
  required YouTubeSearch search,
  required SpotifyPlaylists spotify,
  required SourceSettings settings,
}) async {
  try {
    if (link.service == LinkService.youtube) {
      final target = parseYouTubeLink(link.url);
      if (target is! YouTubeVideoLink) return null;
      final hit = await hitForVideoLink(
        target,
        catalog: catalog,
        library: library,
        youTube: youTube,
        search: search,
        settings: settings,
      );
      // Reading the video failed: no title worth keeping.
      if (hit.mainSong == null && hit.artistLabel == 'YouTube') return null;
      return (title: hit.title, artist: hit.artistLabel);
    }
    var target = parseSpotifyLink(link.url);
    if (target == null) {
      final short = findSpotifyShortLink(link.url);
      if (short != null) target = await spotify.resolveShortLink(short);
    }
    if (target == null) return null;
    switch (target.kind) {
      case SpotifyLinkKind.track:
        final hit = await hitForSpotifyTrack(
          await spotify.fetchTrack(target.id),
          catalog: catalog,
          playlists: playlists,
          library: library,
          youTube: youTube,
        );
        return (title: hit.title, artist: hit.artistLabel);
      case SpotifyLinkKind.album:
        final album = await spotify.fetchAlbum(target.id);
        return (title: album.name, artist: album.owner);
      case SpotifyLinkKind.playlist:
        final playlist = await spotify.fetch(target.id);
        return (title: playlist.name, artist: playlist.owner);
    }
  } catch (e) {
    debugPrint('Describing ${link.url} failed: $e');
    return null;
  }
}
