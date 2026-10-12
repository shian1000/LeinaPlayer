import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'network_errors.dart';
import 'playlist_library.dart';
import 'playlist_search.dart';

/// One track of a Spotify playlist, as the public embed page lists it.
class SpotifyTrack {
  const SpotifyTrack({
    required this.id,
    required this.title,
    required this.artists,
    this.duration,
  });

  /// Spotify's track id (`spotify:track:<id>`).
  final String id;
  final String title;
  final List<String> artists;
  final Duration? duration;
}

/// A Spotify playlist (or album, imported like one) as fetched for import.
class SpotifyPlaylistData {
  const SpotifyPlaylistData({
    required this.id,
    required this.name,
    required this.owner,
    required this.tracks,
    this.totalTracks,
    this.album = false,
  });

  final String id;
  final String name;

  /// The playlist's owner; an album's artist.
  final String? owner;
  final List<SpotifyTrack> tracks;

  /// How many tracks the playlist really has, when known — the embed page lists at most
  /// [SpotifyPlaylists.embedLimit].
  final int? totalTracks;

  /// An album, not a playlist.
  final bool album;
}

/// Why a Spotify playlist couldn't be read; [message] is shown to the user as is.
class SpotifyException implements Exception {
  const SpotifyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a Spotify link points at.
enum SpotifyLinkKind { playlist, album, track }

typedef SpotifyLink = ({SpotifyLinkKind kind, String id});

final _playlistPath = RegExp(
  r'open\.spotify\.com/(?:intl-[\w-]+/)?(?:embed/)?playlist/([A-Za-z0-9]{22})',
);
final _playlistUri = RegExp(r'spotify:playlist:([A-Za-z0-9]{22})');
final _linkPath = RegExp(
  r'open\.spotify\.com/(?:intl-[\w-]+/)?(?:embed/)?(playlist|album|track)/([A-Za-z0-9]{22})',
);
final _linkUri = RegExp(r'spotify:(playlist|album|track):([A-Za-z0-9]{22})');
final _shortLink = RegExp(r'https?://(?:spotify\.link|spotify\.app\.link)/\S+');

/// The playlist id from a pasted or shared Spotify link (`open.spotify.com/playlist/<id>`, also
/// with `intl-pl/` or `embed/`, or `spotify:playlist:<id>`); `null` when there's none.
String? extractSpotifyPlaylistId(String text) =>
    (_playlistPath.firstMatch(text) ?? _playlistUri.firstMatch(text))?.group(1);

/// The playlist, album or track the first Spotify link in [text] points at (the forms of
/// [extractSpotifyPlaylistId]); `null` when there's none. The first one, because a followed
/// short link's text starts with the address it led to, before the page's own links.
SpotifyLink? parseSpotifyLink(String text) {
  final matches = [
    _linkPath.firstMatch(text),
    _linkUri.firstMatch(text),
  ].nonNulls.toList()..sort((a, b) => a.start.compareTo(b.start));
  final match = matches.firstOrNull;
  if (match == null) return null;
  return (
    kind: SpotifyLinkKind.values.byName(match.group(1)!),
    id: match.group(2)!,
  );
}

/// A `spotify.link/…` short link in [text] (the Spotify app shares these too); it has to be
/// followed ([SpotifyPlaylists.resolveShortLink]) to learn what it points at.
Uri? findSpotifyShortLink(String text) {
  final match = _shortLink.firstMatch(text);
  return match == null ? null : Uri.tryParse(match.group(0)!);
}

/// The playlist's own page, for sharing it and opening it in Spotify.
Uri spotifyPlaylistUri(String playlistId) =>
    Uri.https('open.spotify.com', '/playlist/$playlistId');

/// The album's own page.
Uri spotifyAlbumUri(String albumId) =>
    Uri.https('open.spotify.com', '/album/$albumId');

/// The `entity` in an embed page's `__NEXT_DATA__` JSON.
Map<String, Object?> _embedEntity(String html) {
  final json = RegExp(
    r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
    dotAll: true,
  ).firstMatch(html)?.group(1);
  if (json == null) {
    throw const SpotifyException(
      'Spotify zmienił swoją stronę — aplikacja nie umie jej już odczytać.',
    );
  }
  return switch (jsonDecode(json)) {
    {
      'props': {
        'pageProps': {
          'state': {'data': {'entity': final Map<String, Object?> entity}},
        },
      },
    } =>
      entity,
    _ => throw const SpotifyException(
      'Nie ma tego na Spotify albo nie jest publiczne.',
    ),
  };
}

/// Reads a playlist from the embed page at `open.spotify.com/embed/playlist/<id>` — public, no
/// account or app registration, the same choice MusicDatabase made for `spotify_fetcher.py`
/// (it scrapes the public web player rather than the Web API). The page carries the playlist in
/// its `__NEXT_DATA__` JSON, which is unofficial and may change. An album's page
/// (`embed/album/<id>`, [album]) is the same, with the artist as the owner.
SpotifyPlaylistData parseSpotifyEmbed(
  String html,
  String playlistId, {
  bool album = false,
}) {
  final entity = _embedEntity(html);
  final owner = entity['subtitle'] as String?;
  return SpotifyPlaylistData(
    id: playlistId,
    album: album,
    name:
        (entity['name'] ?? entity['title']) as String? ??
        (album ? 'Album ze Spotify' : 'Playlista ze Spotify'),
    owner: owner == null || owner.isEmpty ? null : owner,
    tracks: [
      for (final item in (entity['trackList'] as List?) ?? const [])
        if (item
            case {
              'uri': final String uri,
              'title': final String title,
              'subtitle': final String artists,
            }
            when uri.startsWith('spotify:track:'))
          SpotifyTrack(
            id: uri.substring('spotify:track:'.length),
            title: title,
            artists: splitSpotifyArtists(artists),
            duration: switch (item['duration']) {
              final int ms when ms > 0 => Duration(milliseconds: ms),
              _ => null,
            },
          ),
    ],
  );
}

/// The embed page joins a track's artists with ", " (`\s` also covers its non-breaking space).
List<String> splitSpotifyArtists(String subtitle) => [
  for (final part in subtitle.split(RegExp(r',\s+')))
    if (part.trim().isNotEmpty) part.trim(),
];

/// A track from its embed page, `open.spotify.com/embed/track/<id>` (like
/// [parseSpotifyEmbed]; artists come as a list there).
SpotifyTrack parseSpotifyTrackEmbed(String html, String trackId) {
  final entity = _embedEntity(html);
  final title = (entity['name'] ?? entity['title']) as String?;
  if (title == null || title.isEmpty) {
    throw const SpotifyException('Nie ma takiego utworu na Spotify.');
  }
  return SpotifyTrack(
    id: trackId,
    title: title,
    artists: [
      for (final artist in (entity['artists'] as List?) ?? const [])
        if (artist case {'name': final String name} when name.isNotEmpty) name,
    ],
    duration: switch (entity['duration']) {
      final int ms when ms > 0 => Duration(milliseconds: ms),
      _ => null,
    },
  );
}

/// `<meta name="music:song_count" content="150"/>` on the playlist's own page.
int? parseSpotifySongCount(String html) => int.tryParse(
  RegExp(r'<meta name="music:song_count" content="(\d+)"')
          .firstMatch(html)
          ?.group(1) ??
      '',
);

/// Spotify's version suffixes that aren't a different recording: "Song - Remastered 2011",
/// "Song - 2011 Remaster", "Song - Radio Edit", "Song - Mono", "Song - From \"Film\"". Dropped
/// before matching, like the junk brackets of YouTube titles (`parseYouTubeTrack()`; ADR 0003 —
/// MusicDatabase has no Spotify title rules of its own). Real versions (Live, Remix, Acoustic)
/// stay.
String cleanSpotifyTitle(String title) {
  final at = title.lastIndexOf(' - ');
  if (at <= 0) return title.trim();
  final suffix = title.substring(at + 3).trim();
  return _junkSuffix.hasMatch(suffix)
      ? cleanSpotifyTitle(title.substring(0, at))
      : title.trim();
}

final _junkSuffix = RegExp(
  r'^(?:'
  r'(?:\d{4} )?(?:digital )?remaster(?:ed)?(?: \d{4})?(?: version| edition)?'
  r'|(?:single|album|radio|mono|stereo|original)(?: version| edit| mix)'
  r'|radio edit|mono|stereo|explicit|clean'
  r'|from .*'
  r')$',
  caseSensitive: false,
);

typedef HttpGetText = Future<String> Function(Uri uri);

/// A response to [HttpCall], whatever its status.
typedef HttpReply = ({int status, String body});

/// One HTTP request; `null` [body] is a GET.
typedef HttpCall = Future<HttpReply> Function(
  Uri uri, {
  Map<String, String> headers,
  String? body,
});

/// The user's own Spotify app (Ustawienia › Źródła muzyki › Spotify › Spotify API), from
/// developer.spotify.com: the Web API with its client-credentials token, no user login.
typedef SpotifyApiKey = ({String clientId, String clientSecret});

/// Fetches and searches Spotify playlists; [get] and [call] can be replaced in tests.
class SpotifyPlaylists {
  SpotifyPlaylists({HttpGetText? get, HttpCall? call})
    : _get = get ?? _httpGetText,
      _call = call ?? _httpCall;

  /// The embed page lists only the first 100 tracks.
  static const embedLimit = 100;

  static const searchLimit = 20;

  final HttpGetText _get;
  final HttpCall _call;

  /// Throws [SpotifyException] when the playlist couldn't be read.
  Future<SpotifyPlaylistData> fetch(String playlistId) async {
    final data = parseSpotifyEmbed(
      await _embed('playlist', playlistId, 'playlisty'),
      playlistId,
    );
    if (data.tracks.isEmpty) {
      throw const SpotifyException('Ta playlista na Spotify jest pusta.');
    }
    if (data.tracks.length < embedLimit) return data;
    // Only a full embed page may hide more tracks; the real count is on the playlist's page.
    int? total;
    try {
      total = parseSpotifySongCount(await _get(spotifyPlaylistUri(playlistId)));
    } catch (e) {
      debugPrint('Spotify playlist $playlistId: no song count ($e)');
    }
    return SpotifyPlaylistData(
      id: data.id,
      name: data.name,
      owner: data.owner,
      tracks: data.tracks,
      totalTracks: total,
    );
  }

  /// An album, read like a playlist ([fetch]). Throws [SpotifyException].
  Future<SpotifyPlaylistData> fetchAlbum(String albumId) async {
    final data = parseSpotifyEmbed(
      await _embed('album', albumId, 'albumu'),
      albumId,
      album: true,
    );
    if (data.tracks.isEmpty) {
      throw const SpotifyException('Ten album na Spotify nie ma utworów.');
    }
    return data;
  }

  /// One track: its title, artists and length. Throws [SpotifyException].
  Future<SpotifyTrack> fetchTrack(String trackId) async =>
      parseSpotifyTrackEmbed(await _embed('track', trackId, 'utworu'), trackId);

  /// The embed page of [kind] [id]; [what] names it in an error ("playlisty").
  Future<String> _embed(String kind, String id, String what) async {
    try {
      return await _get(Uri.https('open.spotify.com', '/embed/$kind/$id'));
    } on SpotifyException {
      rethrow;
    } catch (e) {
      debugPrint('Spotify $kind $id failed: $e');
      throw SpotifyException(
        isNetworkError(e)
            ? 'Brak połączenia ze Spotify.'
            : 'Nie udało się odczytać $what ze Spotify.',
      );
    }
  }

  /// What a `spotify.link/…` short link leads to, `null` when it isn't a playlist, album or
  /// track (or couldn't be followed).
  Future<SpotifyLink?> resolveShortLink(Uri link) async {
    try {
      return parseSpotifyLink(await _get(link));
    } catch (e) {
      debugPrint('Resolving $link failed: $e');
      return null;
    }
  }

  /// Playlists for [query]: through the Web API with the user's [apiKey] when there is one,
  /// else (or when it fails) the way the web player searches without logging in (user's
  /// decision: the key first, the anonymous way as the fallback). Throws [SpotifyException].
  Future<List<FoundPlaylist>> search(
    String query, {
    SpotifyApiKey? apiKey,
  }) async {
    final errors = <String>[];
    var offline = true;
    if (apiKey != null) {
      try {
        return await _searchWithApi(query, apiKey);
      } catch (e) {
        debugPrint('Spotify API search failed: $e');
        errors.add('API: ${_describe(e)}');
        offline &= isNetworkError(e);
      }
    }
    try {
      return await _searchAnonymously(query);
    } catch (e) {
      debugPrint('Spotify search without a key failed: $e');
      errors.add('${apiKey == null ? '' : 'bez klucza: '}${_describe(e)}');
      offline &= isNetworkError(e);
    }
    throw SpotifyException(
      offline
          ? 'Brak połączenia ze Spotify.'
          : 'Nie udało się wyszukać na Spotify (${errors.join('; ')}).',
    );
  }

  static String _describe(Object e) => switch (e) {
    SpotifyException(:final message) => message,
    _ when isNetworkError(e) => 'brak połączenia',
    _ => 'błąd',
  };

  ({String key, String token, DateTime expires})? _apiToken;

  Future<List<FoundPlaylist>> _searchWithApi(
    String query,
    SpotifyApiKey apiKey,
  ) async {
    final token = await _apiAccessToken(apiKey);
    final reply = await _call(
      Uri.https('api.spotify.com', '/v1/search', {
        'q': query,
        'type': 'playlist',
        'limit': '$searchLimit',
      }),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (reply.status == HttpStatus.unauthorized) _apiToken = null;
    if (reply.status != HttpStatus.ok) {
      throw SpotifyException('odpowiedź HTTP ${reply.status}');
    }
    return parseSpotifyApiSearch(reply.body);
  }

  Future<String> _apiAccessToken(SpotifyApiKey apiKey) async {
    final key = '${apiKey.clientId}:${apiKey.clientSecret}';
    final cached = _apiToken;
    if (cached != null &&
        cached.key == key &&
        DateTime.now().isBefore(cached.expires)) {
      return cached.token;
    }
    final reply = await _call(
      Uri.https('accounts.spotify.com', '/api/token'),
      headers: {
        'Authorization': 'Basic ${base64Encode(utf8.encode(key))}',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'grant_type=client_credentials',
    );
    if (reply.status != HttpStatus.ok) {
      throw SpotifyException(
        reply.status == HttpStatus.badRequest ||
                reply.status == HttpStatus.unauthorized
            ? 'odrzucony klucz Spotify API'
            : 'odpowiedź HTTP ${reply.status}',
      );
    }
    final json = jsonDecode(reply.body) as Map<String, Object?>;
    final token = json['access_token']! as String;
    final seconds = json['expires_in'] as int? ?? 3600;
    _apiToken = (
      key: key,
      token: token,
      expires: DateTime.now().add(Duration(seconds: seconds - 60)),
    );
    return token;
  }

  ({String token, DateTime expires})? _anonymousToken;

  /// Last known hash of the web player's `searchPlaylists` query (seen 2026-10). Spotify
  /// changes it with new web player versions; [findSpotifySearchHash] then reads the current one.
  static const knownSearchHash =
      'd520014e748f9ea44f7707d8df1819867ac1205e8b7f3e28f22fe5fc858921b1';
  String _searchHash = knownSearchHash;

  /// The web player's own search (`pathfinder` GraphQL with a persisted query) with the
  /// anonymous token the public embed page carries. The Web API itself refuses that token
  /// ("Too many requests"), the web player's search doesn't. Unofficial: it may break.
  Future<List<FoundPlaylist>> _searchAnonymously(String query) async {
    var renewedToken = false;
    var renewedHash = false;
    while (true) {
      final reply = await _call(
        Uri.https('api-partner.spotify.com', '/pathfinder/v2/query'),
        headers: {
          'Authorization': 'Bearer ${await _anonymousAccessToken()}',
          'Content-Type': 'application/json;charset=UTF-8',
          'app-platform': 'WebPlayer',
        },
        body: jsonEncode({
          'variables': {
            'searchTerm': query,
            'offset': 0,
            'limit': searchLimit,
            'numberOfTopResults': 5,
            'includeAudiobooks': false,
            'includePreReleases': false,
          },
          'operationName': 'searchPlaylists',
          'extensions': {
            'persistedQuery': {'version': 1, 'sha256Hash': _searchHash},
          },
        }),
      );
      if (reply.status == HttpStatus.ok) {
        return parseSpotifyWebSearch(reply.body);
      }
      if (reply.status == HttpStatus.unauthorized && !renewedToken) {
        renewedToken = true;
        _anonymousToken = null;
        continue;
      }
      // 412 "Invalid query hash": a new web player version.
      if ((reply.status == HttpStatus.preconditionFailed ||
              reply.status == HttpStatus.badRequest) &&
          !renewedHash) {
        renewedHash = true;
        final hash = await findSpotifySearchHash(_call);
        if (hash != null && hash != _searchHash) {
          _searchHash = hash;
          continue;
        }
      }
      throw SpotifyException(
        reply.status == HttpStatus.tooManyRequests
            ? 'Spotify chwilowo ogranicza wyszukiwanie bez klucza'
            : 'odpowiedź HTTP ${reply.status}',
      );
    }
  }

  /// "Today's Top Hits": any public embed page carries an anonymous token, this one should
  /// always exist.
  static const _tokenPlaylist = '37i9dQZF1DXcBWIGoYBM5M';

  Future<String> _anonymousAccessToken() async {
    final cached = _anonymousToken;
    if (cached != null && DateTime.now().isBefore(cached.expires)) {
      return cached.token;
    }
    final html = await _get(
      Uri.https('open.spotify.com', '/embed/playlist/$_tokenPlaylist'),
    );
    final token = RegExp(r'"accessToken":"([^"]+)"').firstMatch(html)?.group(1);
    if (token == null) {
      throw const SpotifyException('brak tokenu na stronie Spotify');
    }
    final expiresMs = int.tryParse(
      RegExp(r'"accessTokenExpirationTimestampMs":(\d+)')
              .firstMatch(html)
              ?.group(1) ??
          '',
    );
    final expires = expiresMs == null
        ? DateTime.now().add(const Duration(minutes: 30))
        : DateTime.fromMillisecondsSinceEpoch(expiresMs)
              .subtract(const Duration(minutes: 1));
    _anonymousToken = (token: token, expires: expires);
    return token;
  }
}

/// The current `searchPlaylists` hash from the web player's scripts: the main script, else its
/// lazily loaded search-page chunk. Only a desktop browser is served the web player.
Future<String?> findSpotifySearchHash(HttpCall call) async {
  const desktop = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0',
  };
  try {
    final page = await call(
      Uri.https('open.spotify.com', '/search'),
      headers: desktop,
    );
    final script = RegExp(
      r'https://open\.spotifycdn\.com/cdn/build/web-player/web-player\.[0-9a-f]+\.js',
    ).firstMatch(page.body)?.group(0);
    if (script == null) return null;
    final main = (await call(Uri.parse(script), headers: desktop)).body;
    final inMain = findPersistedQueryHash(main, 'searchPlaylists');
    if (inMain != null) return inMain;
    for (final chunk in searchChunkUrls(main, Uri.parse(script))) {
      final reply = await call(chunk, headers: desktop);
      if (reply.status != HttpStatus.ok) continue;
      final hash = findPersistedQueryHash(reply.body, 'searchPlaylists');
      if (hash != null) return hash;
    }
  } catch (e) {
    debugPrint('Looking for Spotify search hash failed: $e');
  }
  return null;
}

/// `"searchPlaylists","query","<sha256>"` in a web player script.
String? findPersistedQueryHash(String script, String operation) =>
    RegExp('"$operation","query","([0-9a-f]{64})"')
        .firstMatch(script)
        ?.group(1);

/// Where the web player's search-page chunk may be: its chunk number maps to the name
/// `xpui-routes-search` and to a content hash (one map for scripts, one for styles — both are
/// tried).
List<Uri> searchChunkUrls(String mainScript, Uri mainUri) {
  final number = RegExp(r'(\d+):"xpui-routes-search"')
      .firstMatch(mainScript)
      ?.group(1);
  if (number == null) return const [];
  return [
    for (final hash in {
      for (final m in RegExp(
        '[{,]$number:"([0-9a-f]{8})"',
      ).allMatches(mainScript))
        m.group(1)!,
    })
      mainUri.resolve('xpui-routes-search.$hash.js'),
  ];
}

/// Playlists in the Web API's `/v1/search?type=playlist` answer (its list may hold `null`s).
List<FoundPlaylist> parseSpotifyApiSearch(String body) {
  final items = switch (jsonDecode(body)) {
    {'playlists': {'items': final List items}} => items,
    _ => const [],
  };
  return [
    for (final item in items)
      if (item case {'id': final String id, 'name': final String name})
        FoundPlaylist(
          source: PlaylistSource.spotify,
          id: id,
          name: name,
          owner: switch (item['owner']) {
            {'display_name': final String owner} => owner,
            _ => null,
          },
          trackCount: switch (item) {
            {'tracks': {'total': final int n}} => n,
            {'items': {'total': final int n}} => n,
            _ => null,
          },
          thumbnail: switch (item['images']) {
            [{'url': final String url}, ...] => Uri.tryParse(url),
            _ => null,
          },
        ),
  ];
}

/// Playlists in the web player's `searchPlaylists` answer (`data.searchV2.playlists.items`).
List<FoundPlaylist> parseSpotifyWebSearch(String body) {
  final items = switch (jsonDecode(body)) {
    {'data': {'searchV2': {'playlists': {'items': final List items}}}} => items,
    _ => throw const SpotifyException('Spotify zmienił odpowiedź wyszukiwania'),
  };
  return [
    for (final item in items)
      if (item
          case {'data': {'uri': final String uri, 'name': final String name}}
          when uri.startsWith('spotify:playlist:'))
        FoundPlaylist(
          source: PlaylistSource.spotify,
          id: uri.substring('spotify:playlist:'.length),
          name: name,
          owner: switch (item) {
            {'data': {'ownerV2': {'data': {'name': final String owner}}}} =>
              owner,
            _ => null,
          },
          thumbnail: switch (item) {
            {
              'data': {
                'images': {
                  'items': [{'sources': [{'url': final String url}, ...]}, ...],
                },
              },
            } =>
              Uri.tryParse(url),
            _ => null,
          },
        ),
  ];
}

/// The body of [uri]'s page; after redirects (short links), the final address comes first, so
/// [parseSpotifyLink] can find what it points at in it as well as in the page.
Future<String> _httpGetText(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    // Asks as a phone's browser would: the pages were only checked that way.
    ..userAgent =
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/130.0 Mobile Safari/537.36';
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode == HttpStatus.notFound) {
      throw const SpotifyException(
        'Nie ma tego na Spotify albo nie jest publiczne.',
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      throw SpotifyException(
        'Spotify odpowiedział błędem (HTTP ${response.statusCode}).',
      );
    }
    final finalUri = response.redirects.isEmpty
        ? uri
        : uri.resolveUri(response.redirects.last.location);
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 15));
    return '$finalUri\n$body';
  } finally {
    client.close(force: true);
  }
}

Future<HttpReply> _httpCall(
  Uri uri, {
  Map<String, String> headers = const {},
  String? body,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..userAgent =
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/130.0 Mobile Safari/537.36';
  try {
    final request = body == null
        ? await client.getUrl(uri)
        : await client.postUrl(uri);
    headers.forEach(request.headers.set);
    if (body != null) request.add(utf8.encode(body));
    final response = await request.close().timeout(const Duration(seconds: 15));
    return (
      status: response.statusCode,
      body: await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20)),
    );
  } finally {
    client.close(force: true);
  }
}
