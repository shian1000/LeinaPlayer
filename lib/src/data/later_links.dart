import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'incoming_links.dart';
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
  const LaterLink({
    required this.id,
    required this.url,
    required this.service,
    required this.kind,
    required this.personId,
    required this.savedAt,
    this.title,
    this.artist,
    this.openedAt,
  });

  factory LaterLink.fromJson(Map<String, Object?> json) => LaterLink(
    id: json['id']! as String,
    url: json['url']! as String,
    service: json['service'] == 'spotify'
        ? LinkService.spotify
        : LinkService.youtube,
    kind: json['kind'] as String? ?? 'Link',
    personId: json['personId'] as String? ?? '',
    savedAt: _time(json['savedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    title: json['title'] as String?,
    artist: json['artist'] as String?,
    openedAt: _time(json['openedAt']),
  );

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
    _links.add({
      'id': 'l${_next++}',
      'url': url,
      'service': service.name,
      'kind': kind,
      'personId': personId,
      'savedAt': now,
    });
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
}

/// "Na później" (Ja › Na później): links people sent, saved from the link sheet.
/// Phone-only, not synced with MusicDatabase. Re-read whenever the app comes back to the front,
/// since the sheet saves while the app is in the background.
class LaterLinks extends ChangeNotifier {
  LaterLinks([LaterStore? store])
    : _store =
          store ??
          (!kIsWeb && Platform.isAndroid
              ? ChannelLaterStore()
              : MemoryLaterStore());

  final LaterStore _store;
  List<LaterPerson> _people = const [];
  List<LaterLink> _links = const [];

  /// Alphabetical.
  List<LaterPerson> get people => _people;

  /// Newest first.
  List<LaterLink> get links => _links;

  int get unopenedCount => _links.where((l) => !l.opened).length;

  LaterPerson? personOf(LaterLink link) =>
      _people.where((p) => p.id == link.personId).firstOrNull;

  Future<void> load() async {
    try {
      final data = await _store.load();
      _people = [...data.people]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _links = [...data.links]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
      notifyListeners();
    } on PlatformException catch (e) {
      debugPrint('Reading links saved for later failed: $e');
    }
  }

  Future<String> addPerson(String name) async {
    final id = await _store.addPerson(name.trim());
    await load();
    return id;
  }

  Future<void> renamePerson(LaterPerson person, String name) async {
    await _store.renamePerson(person.id, name.trim());
    await load();
  }

  Future<void> removePerson(LaterPerson person) async {
    await _store.removePerson(person.id);
    await load();
  }

  Future<void> setPerson(LaterLink link, String personId) async {
    await _store.updateLink(link.id, {'personId': personId});
    await load();
  }

  Future<void> setOpened(LaterLink link, bool opened) async {
    await _store.updateLink(link.id, {
      'openedAt': opened ? DateTime.now().millisecondsSinceEpoch : null,
    });
    await load();
  }

  Future<void> setDescription(
    LaterLink link,
    String title,
    String? artist,
  ) async {
    await _store.updateLink(link.id, {'title': title, 'artist': artist});
    await load();
  }

  Future<void> remove(LaterLink link) async {
    await _store.removeLink(link.id);
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
