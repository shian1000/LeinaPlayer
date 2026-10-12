import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/playlist_library.dart';
import 'package:music_database_app/src/data/spotify_playlist.dart';
import 'package:music_database_app/src/screens/playlist_import.dart';

import '../support/spotify_fakes.dart';

void main() {
  _searchTests();

  test('finds the playlist id in Spotify links', () {
    const id = '37i9dQZF1DX4UtSsGT1Sbe';
    for (final text in [
      'https://open.spotify.com/playlist/$id?si=abc123',
      'https://open.spotify.com/intl-pl/playlist/$id',
      'Posłuchaj: https://open.spotify.com/embed/playlist/$id',
      'spotify:playlist:$id',
    ]) {
      expect(extractSpotifyPlaylistId(text), id, reason: text);
    }
    expect(
      extractSpotifyPlaylistId('https://open.spotify.com/track/$id'),
      null,
    );
    expect(
      findSpotifyShortLink('Zobacz https://spotify.link/AbCdEf12 teraz'),
      Uri.parse('https://spotify.link/AbCdEf12'),
    );
  });

  test('tells tracks, albums and playlists apart', () {
    const id = '4uLU6hMCjMI75M1A2tKUQC';
    String? kind(String text) => switch (parseSpotifyLink(text)) {
      (:final kind, id: final found) => '${kind.name} $found',
      null => null,
    };
    expect(kind('https://open.spotify.com/track/$id?si=x'), 'track $id');
    expect(kind('https://open.spotify.com/intl-pl/album/$id'), 'album $id');
    expect(kind('spotify:playlist:$id'), 'playlist $id');
    expect(kind('https://open.spotify.com/artist/$id'), null);
    // A followed short link: the address it led to comes before the page's own links.
    expect(
      kind(
        'https://open.spotify.com/track/$id\n'
        '<a href="https://open.spotify.com/playlist/37i9dQZF1DX4UtSsGT1Sbe">',
      ),
      'track $id',
    );
    expect(parsePlaylistLink('https://open.spotify.com/album/$id'), (
      source: PlaylistSource.spotifyAlbum,
      id: id,
    ));
    expect(parsePlaylistLink('https://open.spotify.com/track/$id'), null);
  });

  test('reads a track and an album from their embed pages', () async {
    final asked = <String>[];
    final spotify = SpotifyPlaylists(
      get: (uri) async {
        asked.add(uri.path);
        return uri.path.contains('/track/')
            ? embedEntity({
                'type': 'track',
                'name': 'Heroes - 2017 Remaster',
                'artists': [
                  {'name': 'David Bowie'},
                  {'name': 'Brian Eno'},
                ],
                'duration': 371000,
              })
            : embedPage([track('a', 'Run Away With Me', 'Carly Rae Jepsen')]);
      },
    );
    final heroes = await spotify.fetchTrack('T1');
    expect(heroes.id, 'T1');
    expect(heroes.title, 'Heroes - 2017 Remaster');
    expect(heroes.artists, ['David Bowie', 'Brian Eno']);
    expect(heroes.duration, const Duration(seconds: 371));
    final album = await spotify.fetchAlbum('AL');
    expect(album.album, isTrue);
    expect(album.tracks.single.title, 'Run Away With Me');
    expect(asked, ['/embed/track/T1', '/embed/album/AL']);
  });

  test('reads the playlist from the embed page', () {
    final data = parseSpotifyEmbed(
      embedPage(owner: 'Spotify', [
        track('a', 'Stop The Wedding!', 'Ashe'),
        track('b', 'Under Pressure', 'Queen, David Bowie'),
        {'uri': 'spotify:episode:x', 'title': 'Podcast', 'subtitle': 'Ktoś'},
      ]),
      'PL',
    );
    expect(data.name, 'All Out 80s');
    expect(data.owner, 'Spotify');
    expect([for (final t in data.tracks) t.id], ['a', 'b']);
    expect(data.tracks[1].artists, ['Queen', 'David Bowie']);
    expect(data.tracks[0].duration, const Duration(milliseconds: 198840));
  });

  test('drops version suffixes that are not another recording', () {
    expect(cleanSpotifyTitle('Heroes - 2017 Remaster'), 'Heroes');
    expect(cleanSpotifyTitle('Heroes - Remastered 2009'), 'Heroes');
    expect(cleanSpotifyTitle('Song - Radio Edit'), 'Song');
    expect(cleanSpotifyTitle('Song - From "Film"'), 'Song');
    expect(cleanSpotifyTitle('Song - Mono - Remastered'), 'Song');
    expect(cleanSpotifyTitle('Song - Live'), 'Song - Live');
    expect(
      cleanSpotifyTitle('Song - Acoustic Version'),
      'Song - Acoustic Version',
    );
  });

  test('a full embed page asks the playlist page for the real count', () async {
    final asked = <Uri>[];
    final spotify = SpotifyPlaylists(
      get: (uri) async {
        asked.add(uri);
        return uri.path.startsWith('/embed/')
            ? embedPage([
                for (var i = 0; i < SpotifyPlaylists.embedLimit; i++)
                  track('$i', 'T$i', 'A'),
              ])
            : '<meta name="music:song_count" content="150"/>';
      },
    );
    final data = await spotify.fetch('PL');
    expect(data.tracks, hasLength(100));
    expect(data.totalTracks, 150);
    expect(asked, hasLength(2));
  });

  test('an empty or unreadable page is reported', () async {
    expect(
      SpotifyPlaylists(get: (_) async => embedPage(const [])).fetch('PL'),
      throwsA(isA<SpotifyException>()),
    );
    expect(
      SpotifyPlaylists(get: (_) async => '<html></html>').fetch('PL'),
      throwsA(isA<SpotifyException>()),
    );
  });
}

void _searchTests() {
  test(
    'searches playlists without a key the way the web player does',
    () async {
      final fake = FakeSpotify();
      final spotify = SpotifyPlaylists(get: fake.get, call: fake.call);
      final found = await spotify.search('rock');
      expect([for (final p in found) p.name], ['Rock Classics', 'Polski rock']);
      expect(found.first.id, 'a' * 22);
      expect(found.first.owner, 'Spotify');
      expect(
        found.first.thumbnail,
        Uri.parse('https://image.test/${'a' * 22}'),
      );

      // The token is read once.
      await spotify.search('pop');
      expect(fake.calls.where((c) => c.startsWith('GET /embed')), hasLength(1));
    },
  );

  test('a key searches through the Web API, falling back without it', () async {
    final fake = FakeSpotify();
    final spotify = SpotifyPlaylists(get: fake.get, call: fake.call);
    const key = (clientId: 'id', clientSecret: 'secret');
    final found = await spotify.search('rock', apiKey: key);
    expect([for (final p in found) p.name], ['Z API']);
    expect(found.single.trackCount, 42);
    expect(fake.calls, isNot(contains(startsWith('POST api-partner'))));

    fake.apiStatus = 400;
    final fresh = SpotifyPlaylists(get: fake.get, call: fake.call);
    expect(
      [for (final p in await fresh.search('rock', apiKey: key)) p.name],
      ['Rock Classics', 'Polski rock'],
    );
  });

  test('a changed search hash is read from the web player again', () async {
    final fake = FakeSpotify()..acceptedHashes = {'f' * 64};
    final spotify = SpotifyPlaylists(get: fake.get, call: fake.call);
    expect(await spotify.search('rock'), hasLength(2));
    expect(
      fake.calls,
      contains(
        'GET open.spotifycdn.com/cdn/build/web-player/xpui-routes-search.26bd4c1e.js',
      ),
    );
  });

  test('failures are reported with every way tried', () async {
    final fake = FakeSpotify()
      ..searchStatus = 429
      ..apiStatus = 401;
    final spotify = SpotifyPlaylists(get: fake.get, call: fake.call);
    await expectLater(
      spotify.search('rock', apiKey: (clientId: 'id', clientSecret: 'x')),
      throwsA(
        isA<SpotifyException>().having(
          (e) => e.message,
          'message',
          allOf(contains('odrzucony klucz'), contains('ogranicza')),
        ),
      ),
    );
  });
}
