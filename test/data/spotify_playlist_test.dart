import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/spotify_playlist.dart';

/// The embed page as Spotify serves it, cut down to what is read.
String embedPage(List<Map<String, Object?>> tracks, {String? owner}) {
  final data = {
    'props': {
      'pageProps': {
        'state': {
          'data': {
            'entity': {
              'type': 'playlist',
              'name': 'All Out 80s',
              'subtitle': ?owner,
              'trackList': tracks,
            },
          },
        },
      },
    },
  };
  return '<html><script id="__NEXT_DATA__" type="application/json">'
      '${jsonEncode(data)}</script></html>';
}

Map<String, Object?> track(String id, String title, String artists) => {
  'uri': 'spotify:track:$id',
  'title': title,
  'subtitle': artists,
  'duration': 198840,
  'entityType': 'track',
};

void main() {
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
