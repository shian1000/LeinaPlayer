import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'combined_search.dart';
import 'track_ref.dart';

/// The song last played from a playlist: [index] is its row as listed when it was queued, which
/// "Sortuj" or an edit may since have moved — [track] says which song it was.
typedef PlaylistBookmark = ({int index, TrackRef track});

/// For each Biblioteka playlist, the song that last started playing from it — the playlist marks
/// it with a bookmark, so the user sees where they stopped. Only on this phone, not synced.
class PlaylistBookmarks extends ChangeNotifier {
  static const _key = 'playlist_bookmarks';

  Map<int, PlaylistBookmark> _bookmarks = const {};

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    _bookmarks = {
      for (final MapEntry(:key, :value)
          in (jsonDecode(raw) as Map).cast<String, Object?>().entries)
        int.parse(key): (
          index: (value as Map)['index'] as int,
          track: TrackRef.fromJson((value['track'] as Map).cast()),
        ),
    };
    notifyListeners();
  }

  PlaylistBookmark? of(int playlistId) => _bookmarks[playlistId];

  Future<void> record(int playlistId, int index, SearchHit hit) async {
    _bookmarks = {
      ..._bookmarks,
      playlistId: (index: index, track: TrackRef.of(hit)),
    };
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode({
        for (final MapEntry(:key, :value) in _bookmarks.entries)
          '$key': {'index': value.index, 'track': value.track.toJson()},
      }),
    );
  }
}

class PlaylistBookmarksScope extends InheritedNotifier<PlaylistBookmarks> {
  const PlaylistBookmarksScope({
    super.key,
    required PlaylistBookmarks super.notifier,
    required super.child,
  });

  /// `null` in widget tests that don't set it up.
  static PlaylistBookmarks? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PlaylistBookmarksScope>()
      ?.notifier;
}
