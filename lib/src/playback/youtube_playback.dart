import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import '../data/incoming_links.dart';
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
  const YouTubePlaybackException(
    this.message, {
    this.offline = false,
    this.gone = false,
  });

  final String message;

  /// A streaming method failed for want of a network connection, so trying again later may
  /// work (unlike a video YouTube refuses).
  final bool offline;

  /// YouTube no longer has the video, so no method will play it.
  final bool gone;

  @override
  String toString() => message;
}

typedef OpenExternalFn = Future<bool> Function(Uri uri);

/// The video's page; with [listId], inside that playlist (YouTube then plays on through it).
Uri youTubeWatchUri(String videoId, {String? listId}) =>
    Uri.https('www.youtube.com', '/watch', {'v': videoId, 'list': ?listId});

/// [uri] of a video starting at [position], so YouTube goes on from where this app's player is.
/// Not done for Spotify: its Android app opens a track link as the album's page (on a free
/// account), with no way to say where to start.
Uri youTubeUriAt(Uri uri, Duration position) {
  final seconds = position.inSeconds;
  if (seconds <= 0) return uri;
  return uri.replace(
    queryParameters: {...uri.queryParameters, 't': '${seconds}s'},
  );
}

/// The YouTube app when it's installed, the browser otherwise.
Future<bool> openInYouTube(Uri uri) async {
  // On Android this app may handle YouTube links itself, so it names the YouTube app.
  final opened = await openInYouTubeApp(uri);
  if (opened != null) return opened;
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication)) {
      return true;
    }
  } catch (_) {
    // No app claims the link; fall through to the browser.
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Plays a YouTube video with the user's [YouTubePlaybackMethod]s, in their order, moving to the
/// next one when a method fails.
class YouTubePlayback {
  YouTubePlayback({
    required this.audio,
    required this.library,
    required this.settings,
    required this.player,
    OpenExternalFn? openExternal,
  }) : _openExternal = openExternal ?? openInYouTube;

  final YouTubeAudio audio;
  final YouTubeLibrary library;
  final SourceSettings settings;
  final PlayerController player;
  final OpenExternalFn _openExternal;

  /// [track] builds what the player shows for a given source (file path or stream URL);
  /// [onConnecting] is called before the first attempt that goes over the network. Without
  /// [allowExternal] the YouTube app method is skipped — the queue moving on by itself, maybe
  /// with the screen off, must not open another app. [externalUri] is what the YouTube app
  /// opens (e.g. the song inside its playlist); the video's own page by default.
  Future<YouTubePlayedVia> play(
    String videoId,
    NowPlaying Function(String source) track, {
    void Function()? onConnecting,
    bool allowExternal = true,
    Uri? externalUri,
  }) async {
    final errors = <String>[];
    var offline = false;
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
          if (!allowExternal) continue;
          connect();
          if (await _openExternal(externalUri ?? youTubeWatchUri(videoId))) {
            // The video plays elsewhere now; don't play something else on top of it.
            if (player.playing) await player.togglePlay();
            return YouTubePlayedVia.youtubeApp;
          }
          errors.add('aplikacja YouTube: nie udało się otworzyć');
        case YouTubePlaybackMethod.newPipe ||
            YouTubePlaybackMethod.explode ||
            YouTubePlaybackMethod.ytDlpServer:
          connect();
          // YouTube sometimes refuses one stream address (HTTP 403) and accepts a freshly
          // resolved one moments later, so a failed play gets one more try.
          for (var attempt = 1; attempt <= 2; attempt++) {
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
                      settings.cacheKeep,
                    ),
                  );
                }
                return YouTubePlayedVia.stream;
              }
              if (attempt == 2) {
                errors.add(
                  player.lastError ?? '${method.label}: błąd odtwarzania',
                );
              }
            } on YouTubeAudioException catch (e) {
              // Gone for every method — and not worth opening in the YouTube app either.
              if (e.gone) {
                throw const YouTubePlaybackException(
                  'Tego filmu nie ma już na YouTube.',
                  gone: true,
                );
              }
              errors.add(e.message);
              offline |= e.offline;
              break;
            }
          }
      }
    }
    throw YouTubePlaybackException(
      errors.isEmpty
          ? 'Brak włączonego sposobu odtwarzania z YouTube '
                '(Ustawienia › Odtwarzanie › Sposoby odtwarzania YouTube).'
          : 'Nie udało się odtworzyć z YouTube (${errors.join('; ')}).',
      offline: offline,
    );
  }
}
