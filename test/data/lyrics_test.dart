import 'package:flutter_test/flutter_test.dart';

import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/lyrics.dart';

void main() {
  test('LRC lines are read in time order, repeated stamps included', () {
    final lines = parseLrc(
      '[ar: X]\n[00:12.50]Second\n[00:01.2][00:20.00]Chorus\nno time here\n',
    );
    expect([for (final l in lines) l.text], ['Chorus', 'Second', 'Chorus']);
    expect(lines.first.at, const Duration(seconds: 1, milliseconds: 200));
    expect(lines[1].at, const Duration(seconds: 12, milliseconds: 500));
  });

  test('lyrics: the exact match first, else the first search result; '
      'remembered for the run', () async {
    final asked = <String>[];
    final finder = LyricsFinder(
      getJson: (uri) async {
        asked.add(uri.path);
        if (uri.path == '/api/get') return null;
        return [
          {'plainLyrics': 'la la', 'syncedLyrics': '[00:01.00]la la'},
        ];
      },
    );
    final hit = SearchHit.phoneOnly(
      LocalSong(id: 1, filePath: '/m/a.mp3', title: 'A', pending: true),
    );
    final lyrics = await finder.find(hit);
    expect(lyrics?.synced.single.text, 'la la');
    await finder.find(hit);
    expect(asked, ['/api/get', '/api/search']);
  });
}
