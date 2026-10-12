import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'network_errors.dart';
import 'newpipe.dart';
import 'playlist_library.dart';
import 'playlist_search.dart';
import 'source_settings.dart';
import 'spotify_playlist.dart';
import 'youtube_audio.dart';
import 'youtube_playlist.dart';
import 'youtube_video.dart';

export 'youtube_video.dart';

/// Why no [YouTubeSearch] method returned results; [message] is shown to the user as is.
class YouTubeSearchException implements Exception {
  const YouTubeSearchException(this.message, {this.offline = false});

  final String message;

  /// Every method failed for want of a network connection.
  final bool offline;

  @override
  String toString() => message;
}

typedef YouTubeSearchFn = Future<List<YouTubeVideo>> Function(String query);
typedef YouTubeVideoFn = Future<YouTubeVideo> Function(String videoId);
typedef YouTubeApiSearchFn = Future<List<YouTubeVideo>> Function(
  String query,
  String apiKey,
);
typedef YouTubePlaylistSearchFn = Future<List<FoundPlaylist>> Function(
  String query,
);
typedef YouTubeApiPlaylistSearchFn = Future<List<FoundPlaylist>> Function(
  String query,
  String apiKey,
);

/// Searches YouTube with the methods switched on in [SourceSettings], in [YouTubeMethod] order,
/// moving to the next one when a method fails. The functions can be replaced in tests.
class YouTubeSearch {
  YouTubeSearch({
    YouTubeSearchFn? newPipe,
    YouTubeSearchFn? explode,
    YouTubeApiSearchFn? api,
    YouTubeVideoFn? newPipeVideo,
    YouTubeVideoFn? explodeVideo,
    YouTubePlaylistSearchFn? newPipePlaylists,
    YouTubePlaylistSearchFn? explodePlaylists,
    YouTubeApiPlaylistSearchFn? apiPlaylists,
    bool? newPipeAvailable,
  }) : _newPipe = newPipe ?? newPipeSearch,
       _explode = explode ?? _searchWithExplode,
       _api = api ?? _searchWithApi,
       _newPipePlaylists = newPipePlaylists ?? newPipeSearchPlaylists,
       _explodePlaylists = explodePlaylists ?? _searchPlaylistsWithExplode,
       _apiPlaylists = apiPlaylists ?? _searchPlaylistsWithApi,
       _newPipeVideo = newPipeVideo ?? _newPipeVideoInfo,
       _explodeVideo = explodeVideo ?? _videoWithExplode,
       newPipeAvailable = newPipeAvailable ?? (!kIsWeb && Platform.isAndroid);

  static const maxResults = 15;

  final YouTubeSearchFn _newPipe;
  final YouTubeSearchFn _explode;
  final YouTubeApiSearchFn _api;
  final YouTubeVideoFn _newPipeVideo;
  final YouTubeVideoFn _explodeVideo;
  final YouTubePlaylistSearchFn _newPipePlaylists;
  final YouTubePlaylistSearchFn _explodePlaylists;
  final YouTubeApiPlaylistSearchFn _apiPlaylists;

  /// NewPipeExtractor is a Java library, so only the Android build has it.
  final bool newPipeAvailable;

  /// Videos for [query], best match first. Throws [YouTubeSearchException] when no method
  /// worked; an empty list means YouTube was searched and found nothing.
  Future<List<YouTubeVideo>> search(String query, SourceSettings settings) =>
      _firstWorking(
        settings,
        newPipe: () async => (await _newPipe(query)).take(maxResults).toList(),
        explode: () => _explode(query),
        api: (key) => _api(query, key),
      );

  /// Playlists for [query], like [search] (same methods, same errors).
  Future<List<FoundPlaylist>> searchPlaylists(
    String query,
    SourceSettings settings,
  ) => _firstWorking(
    settings,
    newPipe: () async =>
        (await _newPipePlaylists(query)).take(maxResults).toList(),
    explode: () => _explodePlaylists(query),
    api: (key) => _apiPlaylists(query, key),
  );

  /// The result of the first switched-on method that works, in [YouTubeMethod] order.
  Future<T> _firstWorking<T>(
    SourceSettings settings, {
    required Future<T> Function() newPipe,
    required Future<T> Function() explode,
    required Future<T> Function(String apiKey) api,
  }) async {
    final methods = [
      for (final m in YouTubeMethod.values)
        if (settings.methods.contains(m) &&
            (m != YouTubeMethod.newPipe || newPipeAvailable))
          m,
    ];
    if (methods.isEmpty) {
      throw const YouTubeSearchException(
        'Nie wybrano sposobu wyszukiwania w Ustawienia › Źródła muzyki › YouTube.',
      );
    }
    final errors = <String>[];
    var networkFailures = 0;
    var otherFailures = 0;
    for (final method in methods) {
      try {
        switch (method) {
          case YouTubeMethod.newPipe:
            return await newPipe();
          case YouTubeMethod.explode:
            return await explode();
          case YouTubeMethod.ytDlpServer:
            // Needs a search endpoint on MusicDatabase's server, which doesn't exist yet.
            errors.add('yt-dlp przez serwer: jeszcze niedostępne');
            // Not available isn't "offline": leave that to the methods that tried.
            continue;
          case YouTubeMethod.api:
            final key = settings.apiKey;
            if (key == null) {
              errors.add('API: brak kodu YouTube API');
              continue;
            } else {
              return await api(key);
            }
        }
      } catch (e) {
        debugPrint('YouTube search (${method.name}) failed: $e');
        errors.add('${_methodName(method)}: ${_describe(e)}');
        isNetworkError(e) ? networkFailures++ : otherFailures++;
      }
    }
    throw YouTubeSearchException(
      'Nie udało się wyszukać na YouTube (${errors.join('; ')}).',
      offline: networkFailures > 0 && otherFailures == 0,
    );
  }

  /// Title, channel and length of one video (to recognise a link opened with the app); NewPipe,
  /// then youtube_explode, whichever are switched on. Throws [YouTubeSearchException].
  Future<YouTubeVideo> video(String videoId, SourceSettings settings) async {
    final errors = <String>[];
    for (final method in [YouTubeMethod.newPipe, YouTubeMethod.explode]) {
      if (!settings.methods.contains(method)) continue;
      if (method == YouTubeMethod.newPipe && !newPipeAvailable) continue;
      try {
        return await (method == YouTubeMethod.newPipe
            ? _newPipeVideo
            : _explodeVideo)(videoId);
      } catch (e) {
        debugPrint('YouTube video info (${method.name}) failed: $e');
        errors.add('${_methodName(method)}: ${_describe(e)}');
      }
    }
    throw YouTubeSearchException(
      'Nie udało się odczytać filmu z YouTube'
      '${errors.isEmpty ? '' : ' (${errors.join('; ')})'}.',
    );
  }

  /// Whether [videoId] is still on YouTube: `false` when a method says it's gone
  /// ([isVideoGone]: removed, private), `null` when it couldn't be told (no connection, another
  /// error, no method on).
  Future<bool?> videoExists(String videoId, SourceSettings settings) async {
    var answered = false;
    for (final method in [YouTubeMethod.newPipe, YouTubeMethod.explode]) {
      if (!settings.methods.contains(method)) continue;
      if (method == YouTubeMethod.newPipe && !newPipeAvailable) continue;
      try {
        await (method == YouTubeMethod.newPipe ? _newPipeVideo : _explodeVideo)(
          videoId,
        );
        return true;
      } catch (e) {
        debugPrint('Checking video $videoId (${method.name}): $e');
        if (isVideoGone(e)) answered = true;
      }
    }
    return answered ? false : null;
  }

  // The constructor's `newPipeVideo` parameter hides newpipe.dart's function of that name.
  static Future<YouTubeVideo> _newPipeVideoInfo(String videoId) =>
      newPipeVideo(videoId);

  static Future<YouTubeVideo> _videoWithExplode(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final v = await yt.videos.get(videoId);
      return YouTubeVideo(
        id: videoId,
        title: v.title,
        channel: v.author,
        duration: v.duration,
        viewCount: v.engagement.viewCount,
      );
    } finally {
      yt.close();
    }
  }

  static String _methodName(YouTubeMethod m) => switch (m) {
    YouTubeMethod.newPipe => 'NewPipe',
    YouTubeMethod.explode => 'youtube_explode',
    YouTubeMethod.ytDlpServer => 'yt-dlp przez serwer',
    YouTubeMethod.api => 'API',
  };

  static String _describe(Object e) => switch (e) {
    SocketException() || HttpException() => 'brak połączenia',
    YouTubeSearchException(:final message) => message,
    // youtube_explode wraps network errors in package:http's ClientException.
    _ when '$e'.contains('SocketException') => 'brak połączenia',
    _ => 'błąd',
  };

  static Future<List<YouTubeVideo>> _searchWithExplode(String query) async {
    final yt = YoutubeExplode();
    try {
      final videos = await yt.search.search(query);
      return [
        for (final v in videos.take(maxResults))
          YouTubeVideo(
            id: v.id.value,
            title: v.title,
            channel: v.author,
            duration: v.duration,
            viewCount: v.engagement.viewCount,
          ),
      ];
    } finally {
      yt.close();
    }
  }

  static Future<List<FoundPlaylist>> _searchPlaylistsWithExplode(
    String query,
  ) async {
    final yt = YoutubeExplode();
    try {
      final results = await yt.search.searchContent(
        query,
        filter: TypeFilters.playlist,
      );
      return [
        for (final p in results.whereType<SearchPlaylist>().take(maxResults))
          FoundPlaylist(
            source: PlaylistSource.youtube,
            id: p.id.value,
            name: p.title,
            // youtube_explode doesn't read the channel; it caps the count at 50.
            trackCount: p.videoCount > 0 && p.videoCount < 50
                ? p.videoCount
                : null,
            thumbnail: p.thumbnails.lastOrNull?.url,
          ),
      ];
    } finally {
      yt.close();
    }
  }

  static Future<List<FoundPlaylist>> _searchPlaylistsWithApi(
    String query,
    String apiKey,
  ) async {
    final items = await _apiSearch(query, apiKey, 'playlist');
    return [
      for (final item in items)
        if (item case {
          'id': {'playlistId': final String id},
          'snippet': {
            'title': final String title,
            'channelTitle': final String channel,
          },
        })
          FoundPlaylist(
            source: PlaylistSource.youtube,
            id: id,
            name: _unescapeHtml(title),
            owner: _unescapeHtml(channel),
            thumbnail: switch (item) {
              {
                'snippet': {
                  'thumbnails': {'medium': {'url': final String url}},
                },
              } =>
                Uri.tryParse(url),
              _ => null,
            },
          ),
    ];
  }

  static Future<List<YouTubeVideo>> _searchWithApi(
    String query,
    String apiKey,
  ) async {
    final items = await _apiSearch(query, apiKey, 'video');
    return [
      for (final item in items)
        if (item case {
          'id': {'videoId': final String id},
          'snippet': {
            'title': final String title,
            'channelTitle': final String channel,
          },
        })
          YouTubeVideo(
            id: id,
            title: _unescapeHtml(title),
            channel: _unescapeHtml(channel),
          ),
    ];
  }

  /// The Data API's `search` items of one [type] (`video`, `playlist`).
  static Future<List<Object?>> _apiSearch(
    String query,
    String apiKey,
    String type,
  ) async {
    final uri = Uri.https('www.googleapis.com', '/youtube/v3/search', {
      'part': 'snippet',
      'type': type,
      'maxResults': '$maxResults',
      'q': query,
      'key': apiKey,
    });
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw YouTubeSearchException(
          response.statusCode == HttpStatus.forbidden ||
                  response.statusCode == HttpStatus.badRequest
              ? 'odrzucony kod API albo wyczerpany limit'
              : 'odpowiedź HTTP ${response.statusCode}',
        );
      }
      final items = (jsonDecode(body) as Map<String, Object?>)['items'];
      return (items as List?) ?? const [];
    } finally {
      client.close(force: true);
    }
  }

  /// The Data API returns titles HTML-escaped ("Rock &amp; Roll", "Don&#39;t").
  static String _unescapeHtml(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

typedef YouTubePlaylistFn = Future<YouTubePlaylistData> Function(
  String playlistId,
);

/// Fetches a whole YouTube playlist for import, with the search methods switched on
/// ([YouTubeMethod]): NewPipeExtractor (Android), then youtube_explode.
class YouTubePlaylists {
  YouTubePlaylists({
    YouTubePlaylistFn? newPipe,
    YouTubePlaylistFn? explode,
    bool? newPipeAvailable,
  }) : _newPipe = newPipe ?? newPipePlaylist,
       _explode = explode ?? _fetchWithExplode,
       newPipeAvailable = newPipeAvailable ?? (!kIsWeb && Platform.isAndroid);

  final YouTubePlaylistFn _newPipe;
  final YouTubePlaylistFn _explode;
  final bool newPipeAvailable;

  /// Throws [YouTubeSearchException] when no method could read the playlist.
  Future<YouTubePlaylistData> fetch(
    String playlistId,
    SourceSettings settings,
  ) async {
    final errors = <String>[];
    for (final method in [YouTubeMethod.newPipe, YouTubeMethod.explode]) {
      if (!settings.methods.contains(method)) continue;
      if (method == YouTubeMethod.newPipe && !newPipeAvailable) continue;
      try {
        final data = await (method == YouTubeMethod.newPipe
            ? _newPipe
            : _explode)(playlistId);
        // youtube_explode has been seen to report a playlist's size but return no videos.
        if (data.videos.isNotEmpty) return data;
        errors.add('${YouTubeSearch._methodName(method)}: brak filmów');
      } catch (e) {
        debugPrint('YouTube playlist (${method.name}) failed: $e');
        errors.add(
          '${YouTubeSearch._methodName(method)}: ${YouTubeSearch._describe(e)}',
        );
      }
    }
    throw YouTubeSearchException(
      errors.isEmpty
          ? 'Włącz NewPipeExtractor albo youtube_explode w Ustawienia › Źródła muzyki › '
                'YouTube, żeby importować playlisty.'
          : 'Nie udało się odczytać playlisty (${errors.join('; ')}). Sprawdź, czy jest '
                'publiczna lub niepubliczna (nie prywatna) i czy nie jest pusta.',
    );
  }

  static Future<YouTubePlaylistData> _fetchWithExplode(
    String playlistId,
  ) async {
    final yt = YoutubeExplode();
    try {
      final playlist = await yt.playlists.get(playlistId);
      final videos = await yt.playlists.getVideos(playlistId).toList();
      return YouTubePlaylistData(
        id: playlistId,
        name: playlist.title,
        owner: playlist.author,
        videos: [
          for (final v in videos)
            YouTubeVideo(
              id: v.id.value,
              title: v.title,
              channel: v.author,
              duration: v.duration,
              viewCount: v.engagement.viewCount,
            ),
        ],
      );
    } finally {
      yt.close();
    }
  }
}

/// Makes YouTube search and audio — and fetching Spotify playlists, the other online source
/// for imports — reachable from any screen; tests pass fakes.
class YouTubeScope extends InheritedWidget {
  const YouTubeScope({
    super.key,
    required this.search,
    required this.audio,
    required this.playlists,
    this.spotify,
    required super.child,
  });

  final YouTubeSearch search;
  final YouTubeAudio audio;
  final YouTubePlaylists playlists;

  /// `null`: the real one.
  final SpotifyPlaylists? spotify;

  static final _spotify = SpotifyPlaylists();

  static YouTubeScope _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<YouTubeScope>()!;

  static YouTubeSearch searchOf(BuildContext context) => _of(context).search;

  static YouTubeAudio audioOf(BuildContext context) => _of(context).audio;

  static YouTubePlaylists playlistsOf(BuildContext context) =>
      _of(context).playlists;

  static SpotifyPlaylists spotifyOf(BuildContext context) =>
      _of(context).spotify ?? _spotify;

  @override
  bool updateShouldNotify(YouTubeScope oldWidget) =>
      search != oldWidget.search ||
      audio != oldWidget.audio ||
      playlists != oldWidget.playlists ||
      spotify != oldWidget.spotify;
}
