import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/playlist_bookmarks.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  SearchHit song(String title) =>
      SearchHit.youTubeOnly(title: title, artistLabel: 'A', videoId: title);

  test('each playlist keeps its last song, across restarts', () async {
    final bookmarks = PlaylistBookmarks();
    await bookmarks.record(1, 3, song('a'));
    await bookmarks.record(2, 0, song('b'));
    await bookmarks.record(1, 4, song('c'));
    bookmarks.dispose();

    final again = PlaylistBookmarks();
    await again.load();
    expect(again.of(1)?.index, 4);
    expect(again.of(1)?.track.title, 'c');
    expect(again.of(2)?.track.videoId, 'b');
    expect(again.of(3), isNull);
    again.dispose();
  });
}
