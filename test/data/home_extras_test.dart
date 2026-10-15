import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/home_layout.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/saved_songs.dart';
import 'package:music_database_app/src/data/smart_playlists.dart';
import 'package:music_database_app/src/data/song_catalog.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Home layout: pinned first, hidden left out, order and additions '
      'remembered', () async {
    final layout = HomeLayout(defaults: ['a', 'b', 'sample:c']);
    expect(layout.visible, ['a', 'b', 'sample:c']);

    await layout.setPinned('b', true);
    expect(layout.visible, ['b', 'a', 'sample:c']);
    await layout.move('a', 1);
    expect(layout.visible, ['b', 'sample:c', 'a']);
    await layout.setHidden('a', true);
    await layout.setRecommendations(false);
    expect(layout.visible, ['b']);
    await layout.add('playlist:7');
    expect(layout.visible, ['b', 'playlist:7']);

    final reloaded = HomeLayout(defaults: ['a', 'b', 'sample:c']);
    await reloaded.load();
    expect(reloaded.visible, ['b', 'playlist:7']);
    expect(reloaded.all, ['b', 'playlist:7', 'sample:c', 'a']);
    await reloaded.remove('playlist:7');
    await reloaded.setHidden('a', false);
    expect(reloaded.visible, ['b', 'a']);
  });

  test('saved songs toggle and survive a restart', () async {
    final hit = SearchHit.phoneOnly(
      LocalSong(id: 1, filePath: '/m/a.mp3', title: 'a', pending: true),
    );
    final saved = SavedSongs();
    expect(saved.contains(hit), isFalse);
    expect(await saved.toggle(hit), isTrue);
    final reloaded = SavedSongs();
    await reloaded.load();
    expect(reloaded.contains(hit), isTrue);
    expect(await reloaded.toggle(hit), isFalse);
    expect(reloaded.songs, isEmpty);
  });

  test('dynamic playlists are saved with their rule', () async {
    final playlists = SmartPlaylists();
    final made = await playlists.add(
      name: ' Kino ',
      field: SearchField.artist,
      value: 'Kino',
    );
    expect(made.rule, 'Wykonawca: Kino');
    final reloaded = SmartPlaylists();
    await reloaded.load();
    expect(reloaded.byId(made.id)?.name, 'Kino');
    expect(reloaded.byId(made.id)?.field, SearchField.artist);
    await reloaded.delete(made.id);
    expect(reloaded.playlists, isEmpty);
  });
}
