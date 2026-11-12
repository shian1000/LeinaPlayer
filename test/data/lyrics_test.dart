import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/lyrics.dart';
import 'package:music_database_app/src/data/song_catalog.dart';

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

  SearchHit catalogHit({int id = 4, String? language}) => SearchHit.main(
    CatalogSong(id: id, title: 'Raz', artistLabel: 'X', language: language),
    const [],
  );
  final home = Uri.parse('https://home:8002/');
  final remote = Uri.parse('https://remote:8002/');

  test('the server is asked first; plain text alone is shown without asking '
      'LRCLIB for synced lines', () async {
    final asked = <Uri>[];
    final finder = LyricsFinder(
      getServerJson: (uri) async {
        asked.add(uri);
        return {
          'song_id': 4,
          'plain': 'Raz\nDwa',
          'synced': null,
          'instrumental': false,
          'source': 'genius_lyrics_fetcher',
        };
      },
      getJson: (uri) async => fail('LRCLIB asked: $uri'),
    );
    final lyrics = await finder.find(
      catalogHit(),
      servers: () async => [home, remote],
    );
    expect(asked, [Uri.parse('https://home:8002/lyrics/4')]);
    expect(lyrics?.plain, 'Raz\nDwa');
    expect(lyrics?.synced, isEmpty);
    expect(lyrics?.source, 'MusicDatabase (Genius)');
  });

  test(
    'synced lines and instrumental come from the server as they are',
    () async {
      final finder = LyricsFinder(
        getServerJson: (uri) async => uri.path.endsWith('/1')
            ? {'plain': 'a', 'synced': '[00:01.00] a', 'source': 'manual'}
            : {'plain': null, 'synced': null, 'instrumental': true},
        getJson: (uri) async => fail('LRCLIB asked: $uri'),
      );
      final synced = await finder.find(
        catalogHit(id: 1),
        servers: () async => [home],
      );
      expect(synced?.synced.single.text, 'a');
      expect(synced?.source, 'MusicDatabase');
      final instrumental = await finder.find(
        catalogHit(id: 2),
        servers: () async => [home],
      );
      expect(instrumental?.instrumental, isTrue);
    },
  );

  test('a 404 goes to LRCLIB at once; a failing address tries the next one '
      'first', () async {
    final asked = <String>[];
    final finder = LyricsFinder(
      getServerJson: (uri) async {
        asked.add('${uri.host}${uri.path}');
        if (uri.host == 'home') throw const SocketException('unreachable');
        return null;
      },
      getJson: (uri) async {
        asked.add(uri.path);
        return {'plainLyrics': 'la la'};
      },
    );
    final lyrics = await finder.find(
      catalogHit(),
      servers: () async => [home, remote, home],
    );
    expect(asked, ['home/lyrics/4', 'remote/lyrics/4', '/api/get']);
    expect(lyrics?.plain, 'la la');
    expect(lyrics?.source, 'LRCLIB');
  });

  test('a song in music.db as Instrumental is not looked up at all', () async {
    final finder = LyricsFinder(
      getServerJson: (uri) async => fail('server asked: $uri'),
      getJson: (uri) async => fail('LRCLIB asked: $uri'),
    );
    final lyrics = await finder.find(
      catalogHit(language: 'Instrumental'),
      servers: () async => [home],
    );
    expect(lyrics?.instrumental, isTrue);
  });
}
