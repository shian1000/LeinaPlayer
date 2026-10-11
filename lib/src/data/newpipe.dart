import 'package:flutter/services.dart';

import 'youtube_audio.dart';
import 'youtube_playlist.dart';
import 'youtube_video.dart';

/// NewPipeExtractor on Android, via `android/app/src/main/kotlin/.../NewPipeBridge.kt`.
const _channel = MethodChannel('music_database_app/newpipe');

/// Audio-only streams of a video; only plain HTTP files (DASH/HLS manifests would need another
/// kind of player source).
Future<List<YouTubeAudioStream>> newPipeAudioStreams(String videoId) async {
  final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
    'audioStreams',
    {'videoId': videoId},
  );
  return [
    for (final s in raw ?? const <Map<Object?, Object?>>[])
      if (s['delivery'] == 'PROGRESSIVE_HTTP')
        YouTubeAudioStream(
          url: s['url']! as String,
          itag: s['itag']! as int,
          format: s['format'] as String?,
          bitrate: s['bitrate'] as int?,
        ),
  ];
}

/// Videos (not channels or playlists) on the first page of YouTube's search for [query].
Future<List<YouTubeVideo>> newPipeSearch(String query) async {
  final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('search', {
    'query': query,
  });
  return [for (final v in raw ?? const <Map<Object?, Object?>>[]) _video(v)];
}

/// Name, owner and every video of a YouTube playlist.
Future<YouTubePlaylistData> newPipePlaylist(String playlistId) async {
  final raw = (await _channel.invokeMapMethod<String, Object?>('playlist', {
    'playlistId': playlistId,
  }))!;
  return YouTubePlaylistData(
    id: playlistId,
    name: raw['name'] as String? ?? 'Playlista z YouTube',
    owner: raw['owner'] as String?,
    videos: [
      for (final v
          in (raw['videos'] as List? ?? const []).cast<Map<Object?, Object?>>())
        _video(v),
    ],
  );
}

YouTubeVideo _video(Map<Object?, Object?> v) => YouTubeVideo(
  id: v['id']! as String,
  title: v['title']! as String,
  channel: v['channel'] as String? ?? '',
  duration: (v['duration'] as int? ?? -1) < 0
      ? null
      : Duration(seconds: v['duration']! as int),
  viewCount: (v['views'] as int? ?? -1) < 0 ? null : v['views'] as int,
);
