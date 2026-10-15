import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'combined_search.dart';
import 'local_library.dart';
import 'song_catalog.dart';
import 'youtube_library.dart';

/// A dynamic playlist: a saved filter ("Wykonawca: Kino", "Rok: 1987") whose songs are looked up
/// in music.db and on the phone each time it opens, so it follows new downloads by itself
/// (Juxtopposed's Spotify redesign). Only on this phone, not synced.
class SmartPlaylist {
  const SmartPlaylist({
    required this.id,
    required this.name,
    required this.field,
    required this.value,
  });

  factory SmartPlaylist.fromJson(Map<String, Object?> json) => SmartPlaylist(
    id: json['id']! as String,
    name: json['name'] as String? ?? '',
    field: SearchField.values.firstWhere(
      (f) => f.name == json['field'],
      orElse: () => SearchField.artist,
    ),
    value: json['value'] as String? ?? '',
  );

  final String id;
  final String name;
  final SearchField field;
  final String value;

  /// "Wykonawca: Kino".
  String get rule => '${field.label}: $value';

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'field': field.name,
    'value': value,
  };

  List<SearchHit> songs(
    SongCatalog catalog,
    LocalLibrary library,
    YouTubeLibrary youTube,
  ) => searchEverywhere(
    value,
    catalog,
    library,
    youTube: youTube,
    fields: {field},
  );
}

/// The phone's [SmartPlaylist]s (Biblioteka › Dynamiczne playlisty), in the order made.
class SmartPlaylists extends ChangeNotifier {
  static const _key = 'smart_playlists';

  List<SmartPlaylist> _playlists = const [];

  List<SmartPlaylist> get playlists => _playlists;

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    _playlists = [
      for (final json in jsonDecode(raw) as List)
        SmartPlaylist.fromJson((json as Map).cast<String, Object?>()),
    ];
    notifyListeners();
  }

  SmartPlaylist? byId(String id) =>
      _playlists.where((p) => p.id == id).firstOrNull;

  Future<SmartPlaylist> add({
    required String name,
    required SearchField field,
    required String value,
  }) async {
    final playlist = SmartPlaylist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      field: field,
      value: value.trim(),
    );
    _playlists = [..._playlists, playlist];
    await _save();
    return playlist;
  }

  Future<void> delete(String id) async {
    _playlists = [
      for (final p in _playlists)
        if (p.id != id) p,
    ];
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode([for (final p in _playlists) p.toJson()]),
    );
  }
}

class SmartPlaylistsScope extends InheritedNotifier<SmartPlaylists> {
  const SmartPlaylistsScope({
    super.key,
    required SmartPlaylists super.notifier,
    required super.child,
  });

  /// `null` in widget tests that don't set it up.
  static SmartPlaylists? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SmartPlaylistsScope>()
      ?.notifier;
}
