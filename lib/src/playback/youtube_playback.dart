import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import '../data/source_settings.dart';
import '../data/youtube_audio.dart';
import '../data/youtube_library.dart';
import 'player_controller.dart';

/// How a YouTube video ended up being played.
enum YouTubePlayedVia {
  /// From the phone's cache.
  cache,

  /// Streamed in this app's player (and downloaded to the cache meanwhile, if it's on).
  stream,

  /// Handed to the YouTube app (or the browser): playing outside this app.
  youtubeApp,
}

/// Why no switched-on method could play a video; [message] is shown to the user as is.
class YouTubePlaybackException implements Exception {
  const YouTubePlaybackException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef OpenExternalFn = Future<bool> Function(Uri uri);

/// Plays a YouTube video with the user's [YouTubePlaybackMethod]s, in their order, moving to the
/// next one when a method fails.
class YouTubePlayback {
  YouTubePlayback({
    required this.audio,
    required this.library,
    required this.settings,
    required this.player,
    OpenExternalFn? openExternal,
  }) : _openExternal = openExternal ?? _openInYouTube;

  final YouTubeAudio audio;
  final YouTubeLibrary library;
  final SourceSettings settings;
  final PlayerController player;
  final OpenExternalFn _openExternal;

  /// [track] builds what the player shows for a given source (file path or stream URL);
  /// [onConnecting] is called before the first attempt that goes over the network.
  Future<YouTubePlayedVia> play(
    String videoId,
    NowPlaying Function(String source) track, {
    void Function()? onConnecting,
  }) async {
    final errors = <String>[];
    var connecting = false;
    void connect() {
      if (connecting) return;
      connecting = true;
      onConnecting?.call();
    }

    for (final method in settings.activePlaybackMethods) {
      switch (method) {
        case YouTubePlaybackMethod.cache:
          final file = await library.cachedFile(videoId);
          if (file != null && await player.play(track(file.path))) {
            return YouTubePlayedVia.cache;
          }
        case YouTubePlaybackMethod.youtubeApp:
          connect();
          final uri = Uri.https('www.youtube.com', '/watch', {'v': videoId});
          if (await _openExternal(uri)) {
            // The video plays elsewhere now; don't play something else on top of it.
            if (player.playing) await player.togglePlay();
            return YouTubePlayedVia.youtubeApp;
          }
          errors.add('aplikacja YouTube: nie udało się otworzyć');
        case YouTubePlaybackMethod.newPipe ||
            YouTubePlaybackMethod.explode ||
            YouTubePlaybackMethod.ytDlpServer:
          connect();
          try {
            final stream = await audio.streamFrom(method, videoId);
            if (await player.play(track(stream.url))) {
              if (settings.playbackMethods.contains(
                YouTubePlaybackMethod.cache,
              )) {
                unawaited(
                  library.download(
                    videoId,
                    stream.url,
                    stream.extension,
                    settings.cacheLimit,
                  ),
                );
              }
              return YouTubePlayedVia.stream;
            }
            errors.add(player.lastError ?? '${method.label}: błąd odtwarzania');
          } on YouTubeAudioException catch (e) {
            errors.add(e.message);
          }
      }
    }
    throw YouTubePlaybackException(
      errors.isEmpty
          ? 'Brak włączonego sposobu odtwarzania z YouTube '
                '(Ustawienia › Źródła muzyki › YouTube).'
          : 'Nie udało się odtworzyć z YouTube (${errors.join('; ')}).',
    );
  }

  /// The YouTube app when it's installed (it handles youtube.com links), the browser otherwise.
  static Future<bool> _openInYouTube(Uri uri) async {
    try {
      if (await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      )) {
        return true;
      }
    } catch (_) {
      // No app claims the link; fall through to the browser.
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
