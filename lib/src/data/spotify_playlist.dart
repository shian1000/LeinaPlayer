import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'network_errors.dart';

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

/// A Spotify playlist as fetched for import.
class SpotifyPlaylistData {
  const SpotifyPlaylistData({
    required this.id,
    required this.name,
    required this.owner,
    required this.tracks,
    this.totalTracks,
  });

  final String id;
  final String name;
  final String? owner;
  final List<SpotifyTrack> tracks;

  /// How many tracks the playlist really has, when known — the embed page lists at most
  /// [SpotifyPlaylists.embedLimit].
  final int? totalTracks;
}

/// Why a Spotify playlist couldn't be read; [message] is shown to the user as is.
class SpotifyException implements Exception {
  const SpotifyException(this.message);

  final String message;

  @override
  String toString() => message;
}

final _playlistPath = RegExp(
  r'open\.spotify\.com/(?:intl-[\w-]+/)?(?:embed/)?playlist/([A-Za-z0-9]{22})',
);
final _playlistUri = RegExp(r'spotify:playlist:([A-Za-z0-9]{22})');
final _shortLink = RegExp(r'https?://(?:spotify\.link|spotify\.app\.link)/\S+');

/// The playlist id from a pasted or shared Spotify link (`open.spotify.com/playlist/<id>`, also
/// with `intl-pl/` or `embed/`, or `spotify:playlist:<id>`); `null` when there's none.
String? extractSpotifyPlaylistId(String text) =>
    (_playlistPath.firstMatch(text) ?? _playlistUri.firstMatch(text))?.group(1);

/// A `spotify.link/…` short link in [text] (the Spotify app shares these too); it has to be
/// followed ([SpotifyPlaylists.resolveShortLink]) to learn what it points at.
Uri? findSpotifyShortLink(String text) {
  final match = _shortLink.firstMatch(text);
  return match == null ? null : Uri.tryParse(match.group(0)!);
}

/// The playlist's own page, for sharing it and opening it in Spotify.
Uri spotifyPlaylistUri(String playlistId) =>
    Uri.https('open.spotify.com', '/playlist/$playlistId');

/// Reads a playlist from the embed page at `open.spotify.com/embed/playlist/<id>` — public, no
/// account or app registration, the same choice MusicDatabase made for `spotify_fetcher.py`
/// (it scrapes the public web player rather than the Web API). The page carries the playlist in
/// its `__NEXT_DATA__` JSON, which is unofficial and may change.
SpotifyPlaylistData parseSpotifyEmbed(String html, String playlistId) {
  final json = RegExp(
    r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
    dotAll: true,
  ).firstMatch(html)?.group(1);
  if (json == null) {
    throw const SpotifyException(
      'Spotify zmienił stronę playlisty — aplikacja nie umie jej już odczytać.',
    );
  }
  final entity = switch (jsonDecode(json)) {
    {
      'props': {
        'pageProps': {
          'state': {'data': {'entity': final Map<String, Object?> entity}},
        },
      },
    } =>
      entity,
    _ => throw const SpotifyException(
      'Nie ma takiej playlisty na Spotify albo nie jest publiczna.',
    ),
  };
  final owner = entity['subtitle'] as String?;
  return SpotifyPlaylistData(
    id: playlistId,
    name:
        (entity['name'] ?? entity['title']) as String? ??
        'Playlista ze Spotify',
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

/// Fetches Spotify playlists; [get] can be replaced in tests.
class SpotifyPlaylists {
  SpotifyPlaylists({HttpGetText? get}) : _get = get ?? _httpGetText;

  /// The embed page lists only the first 100 tracks.
  static const embedLimit = 100;

  final HttpGetText _get;

  /// Throws [SpotifyException] when the playlist couldn't be read.
  Future<SpotifyPlaylistData> fetch(String playlistId) async {
    final String html;
    try {
      html = await _get(
        Uri.https('open.spotify.com', '/embed/playlist/$playlistId'),
      );
    } on SpotifyException {
      rethrow;
    } catch (e) {
      debugPrint('Spotify playlist $playlistId failed: $e');
      throw SpotifyException(
        isNetworkError(e)
            ? 'Brak połączenia ze Spotify.'
            : 'Nie udało się odczytać playlisty ze Spotify.',
      );
    }
    final data = parseSpotifyEmbed(html, playlistId);
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

  /// The playlist a `spotify.link/…` short link leads to, `null` when it isn't a playlist.
  Future<String?> resolveShortLink(Uri link) async {
    try {
      return extractSpotifyPlaylistId(await _get(link));
    } catch (e) {
      debugPrint('Resolving $link failed: $e');
      return null;
    }
  }
}

/// The body of [uri]'s page; after redirects (short links), the final address comes first, so
/// [extractSpotifyPlaylistId] can find the playlist in it as well as in the page.
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
        'Nie ma takiej playlisty na Spotify albo nie jest publiczna.',
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
