import 'dart:convert';

import 'package:music_database_app/src/data/spotify_playlist.dart';

/// The embed page as Spotify serves it, cut down to what is read.
String embedPage(List<Map<String, Object?>> tracks, {String? owner}) =>
    embedEntity({
      'type': 'playlist',
      'name': 'All Out 80s',
      'subtitle': ?owner,
      'trackList': tracks,
    });

/// An embed page (playlist, album or track) carrying [entity].
String embedEntity(Map<String, Object?> entity) {
  final data = {
    'props': {
      'pageProps': {
        'state': {
          'data': {'entity': entity},
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

/// The web player's `searchPlaylists` answer, cut down to what is read.
String webSearchReply(List<(String id, String name, String owner)> found) =>
    jsonEncode({
      'data': {
        'searchV2': {
          'playlists': {
            'items': [
              for (final (id, name, owner) in found)
                {
                  'data': {
                    '__typename': 'Playlist',
                    'uri': 'spotify:playlist:$id',
                    'name': name,
                    'ownerV2': {
                      'data': {'name': owner},
                    },
                    'images': {
                      'items': [
                        {
                          'sources': [
                            {'url': 'https://image.test/$id'},
                          ],
                        },
                      ],
                    },
                  },
                },
            ],
          },
        },
      },
    });

/// A fake Spotify: the embed page with a token, the web player's search, the Web API.
class FakeSpotify {
  final calls = <String>[];
  int searchStatus = 200;
  int apiStatus = 200;

  /// Hashes the web player's search accepts.
  Set<String> acceptedHashes = {SpotifyPlaylists.knownSearchHash};

  /// Embed pages of playlists, by id; any other page carries just the token.
  final playlists = <String, String>{};

  Future<String> get(Uri uri) async {
    calls.add('GET ${uri.path}');
    final playlist = playlists[uri.pathSegments.last];
    if (playlist != null) return playlist;
    return '<script>{"accessToken":"anon","accessTokenExpirationTimestampMs":'
        '${DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch}}'
        '</script>';
  }

  Future<HttpReply> call(
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    calls.add('${body == null ? 'GET' : 'POST'} ${uri.host}${uri.path}');
    switch (uri.path) {
      case '/pathfinder/v2/query':
        final hash = (jsonDecode(
          body!,
        ) as Map)['extensions']['persistedQuery']['sha256Hash'];
        if (!acceptedHashes.contains(hash)) {
          return (status: 412, body: '"Invalid query hash"');
        }
        if (searchStatus != 200) return (status: searchStatus, body: '');
        return (
          status: 200,
          body: webSearchReply([
            ('a' * 22, 'Rock Classics', 'Spotify'),
            ('b' * 22, 'Polski rock', 'Ktoś'),
          ]),
        );
      case '/api/token':
        return apiStatus == 200
            ? (status: 200, body: '{"access_token":"key","expires_in":3600}')
            : (status: apiStatus, body: '');
      case '/v1/search':
        if (headers['Authorization'] != 'Bearer key') {
          return (status: 401, body: '');
        }
        return (
          status: 200,
          body: jsonEncode({
            'playlists': {
              'items': [
                null,
                {
                  'id': 'c' * 22,
                  'name': 'Z API',
                  'owner': {'display_name': 'Ja'},
                  'tracks': {'total': 42},
                  'images': [
                    {'url': 'https://image.test/c'},
                  ],
                },
              ],
            },
          }),
        );
      case '/search':
        return (
          status: 200,
          body: '<script src="https://open.spotifycdn.com/cdn/build/web-player/web-player.abc123.js">',
        );
      case '/cdn/build/web-player/web-player.abc123.js':
        return (
          status: 200,
          body: '{1:"a",4406:"xpui-routes-search"},{4406:"0badf00d"},{4406:"26bd4c1e"}',
        );
      case '/cdn/build/web-player/xpui-routes-search.26bd4c1e.js':
        return (
          status: 200,
          body: 'new x("searchPlaylists","query","${'f' * 64}",null)',
        );
    }
    return (status: 404, body: '');
  }
}
