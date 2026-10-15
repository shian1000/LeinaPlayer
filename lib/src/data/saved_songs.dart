import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'combined_search.dart';
import 'track_ref.dart';

/// Songs saved to listen to later — kept apart from playlists and liked songs, so trying
/// something out doesn't mix it into the user's favourites (Juxtopposed's Spotify redesign).
/// Only on this phone, newest first (Biblioteka › Na później).
class SavedSongs extends ChangeNotifier {
  static const _key = 'saved_songs';

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

  /// Saves [hit], or takes it out when already saved; returns whether it's saved now.
  Future<bool> toggle(SearchHit hit) async {
    final ref = TrackRef.of(hit);
    final saved = !contains(hit);
    _songs = saved
        ? [ref, ..._songs]
        : [
            for (final s in _songs)
              if (s.key != ref.key) s,
          ];
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode([for (final s in _songs) s.toJson()]),
    );
    return saved;
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
