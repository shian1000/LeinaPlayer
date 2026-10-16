import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'combined_search.dart';
import 'track_ref.dart';

/// A list of songs kept only on this phone (`shared_preferences`), newest first —
/// [SavedSongs] and [LikedSongs].
class StoredSongList extends ChangeNotifier {
  StoredSongList(this._key);

  final String _key;

  List<TrackRef> _songs = const [];

  List<TrackRef> get songs => _songs;

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    _songs = [
      for (final json in jsonDecode(raw) as List)
        TrackRef.fromJson((json as Map).cast<String, Object?>()),
    ];
    notifyListeners();
  }

  bool contains(SearchHit hit) {
    final key = TrackRef.of(hit).key;
    return _songs.any((s) => s.key == key);
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

  /// Puts [hits] on top of the list ([saved]) or takes them out.
  Future<void> setAll(List<SearchHit> hits, bool saved) async {
    final refs = [for (final hit in hits) TrackRef.of(hit)];
    final keys = {for (final ref in refs) ref.key};
    final rest = [
      for (final s in _songs)
        if (!keys.contains(s.key)) s,
    ];
    final seen = <String>{};
    _songs = saved
        ? [
            for (final ref in refs)
              if (seen.add(ref.key)) ref,
            ...rest,
          ]
        : rest;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode([for (final s in _songs) s.toJson()]),
    );
  }
}

/// Songs saved to listen to later — kept apart from playlists and liked songs, so trying
/// something out doesn't mix it into the user's favourites (Juxtopposed's Spotify redesign).
/// Only on this phone, newest first (Biblioteka › Na później).
class SavedSongs extends StoredSongList {
  SavedSongs() : super('saved_songs');
}

/// Liked songs, like Spotify's "Polubione utwory": liked from the "Dodaj do playlisty" sheet.
/// Only on this phone, newest first (Biblioteka › Polubione utwory).
class LikedSongs extends StoredSongList {
  LikedSongs() : super('liked_songs');
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
