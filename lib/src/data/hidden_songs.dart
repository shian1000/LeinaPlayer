import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'combined_search.dart';
import 'track_ref.dart';

/// Songs hidden with "Ukryj utwór": the queue passes over them when it moves on by itself,
/// Odkrywaj and a song's radio leave them out, and their rows are dimmed — but a song tapped
/// on purpose still plays. Only on this phone (user's decision; syncing would need a
/// MusicDatabase endpoint), newest first (Ustawienia › Odtwarzanie › Ukryte utwory).
class HiddenSongs extends ChangeNotifier {
  static const _key = 'hidden_songs';

  List<TrackRef> _songs = const [];
  Set<String> _keys = const {};

  List<TrackRef> get songs => _songs;

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    _set([
      for (final json in jsonDecode(raw) as List)
        TrackRef.fromJson((json as Map).cast<String, Object?>()),
    ]);
  }

  bool contains(SearchHit hit) => _keys.contains(TrackRef.of(hit).key);

  /// Hides [hit], or shows it again when hidden; returns whether it's hidden now.
  Future<bool> toggle(SearchHit hit) async {
    final ref = TrackRef.of(hit);
    final hidden = !contains(hit);
    _set(
      hidden
          ? [ref, ..._songs]
          : [
              for (final s in _songs)
                if (s.key != ref.key) s,
            ],
    );
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode([for (final s in _songs) s.toJson()]),
    );
    return hidden;
  }

  void _set(List<TrackRef> songs) {
    _songs = songs;
    _keys = {for (final s in songs) s.key};
    notifyListeners();
  }
}

class HiddenSongsScope extends InheritedNotifier<HiddenSongs> {
  const HiddenSongsScope({
    super.key,
    required HiddenSongs super.notifier,
    required super.child,
  });

  /// `null` in widget tests that don't set it up.
  static HiddenSongs? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HiddenSongsScope>()?.notifier;
}
