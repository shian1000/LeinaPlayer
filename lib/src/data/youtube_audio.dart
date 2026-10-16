import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'network_errors.dart';
import 'newpipe.dart';
import 'source_settings.dart';

/// One audio-only stream of a YouTube video.
class YouTubeAudioStream {
  const YouTubeAudioStream({
    required this.url,
    required this.itag,
    this.format,
    this.bitrate,
  });

  /// Direct, time-limited address of the audio (valid for a few hours, for this phone only).
  final String url;

  /// YouTube's format id: 251 = Opus ~160 kb/s, 140 = AAC 128 kb/s, ...
  final int itag;
  final String? format;

  /// Average bitrate in kb/s, when known.
  final int? bitrate;

  /// File extension for the cached copy.
  String get extension => switch (itag) {
    249 || 250 || 251 => 'webm',
    139 || 140 || 141 => 'm4a',
    _ when (format ?? '').toLowerCase().contains('webm') => 'webm',
    _ => 'm4a',
  };
}

/// Why a YouTube video can't be played; [message] is shown to the user as is.
class YouTubeAudioException implements Exception {
  const YouTubeAudioException(
    this.message, {
    this.offline = false,
    this.gone = false,
  });

  final String message;

  /// The network couldn't be reached ([isNetworkError]) — worth trying again later.
  final bool offline;

  /// YouTube says the video isn't there any more ([isVideoGone]).
  final bool gone;

  @override
  String toString() => message;
}

/// Whether [error] means YouTube no longer has the video — removed, made private, or its
/// channel closed — rather than refusing it here (age, region, payment) or a failure.
/// NewPipe errors arrive by Java class name (`NewPipeBridge.kt`).
bool isVideoGone(Object error) => switch (error) {
  PlatformException(:final code) => const {
    'ContentNotAvailableException',
    'PrivateContentException',
    'AccountTerminatedException',
  }.contains(code),
  _ => '$error'.contains('VideoUnavailableException'),
};

typedef AudioStreamsFn = Future<List<YouTubeAudioStream>> Function(
  String videoId,
);

/// Finds a playable audio stream for a YouTube video with the [YouTubePlaybackMethod]s switched
/// on, in their order, moving to the next one when a method fails. NewPipeExtractor runs on
/// Android only (`android/app/src/main/kotlin/.../NewPipeBridge.kt`). The cache is handled by the
/// caller, before any of these.
class YouTubeAudio {
  YouTubeAudio({
    AudioStreamsFn? newPipe,
    AudioStreamsFn? explode,
    bool? newPipeAvailable,
  }) : _newPipe = newPipe ?? newPipeAudioStreams,
       _explode = explode ?? _explodeStreams,
       newPipeAvailable = newPipeAvailable ?? (!kIsWeb && Platform.isAndroid);

  final AudioStreamsFn _newPipe;
  final AudioStreamsFn _explode;

  /// NewPipeExtractor is a Java library, so only the Android build has it.
  final bool newPipeAvailable;

  /// Preferred formats, best first: Opus 160 kb/s, then AAC 128 kb/s (iOS can't play Opus/WebM).
  static const _preferredItags = [251, 140];

  /// The audio of [videoId] from the first of [methods] (in that order) that gives one. Methods
  /// that don't give a stream (cache, YouTube app) are skipped — the caller handles them.
  Future<YouTubeAudioStream> bestStream(
    String videoId,
    Iterable<YouTubePlaybackMethod> methods,
  ) async {
    final errors = <String>[];
    for (final method in methods) {
      if (!method.streams) continue;
      try {
        return await streamFrom(method, videoId);
      } on YouTubeAudioException catch (e) {
        errors.add(e.message);
      }
    }
    throw YouTubeAudioException(
      errors.isEmpty
          ? 'Brak włączonego sposobu odtwarzania z YouTube na tym urządzeniu '
                '(Ustawienia › Odtwarzanie › Sposoby odtwarzania YouTube).'
          : 'Nie udało się pobrać dźwięku z YouTube (${errors.join('; ')}).',
    );
  }

  /// The audio of [videoId] from one [method]; the exception's message is short
  /// ("NewPipe: 403"), meant to be listed with the other methods' failures.
  Future<YouTubeAudioStream> streamFrom(
    YouTubePlaybackMethod method,
    String videoId,
  ) async {
    final name = _shortName(method);
    final AudioStreamsFn fetch;
    switch (method) {
      case YouTubePlaybackMethod.newPipe:
        if (!newPipeAvailable) {
          throw YouTubeAudioException('$name: tylko Android');
        }
        fetch = _newPipe;
      case YouTubePlaybackMethod.explode:
        fetch = _explode;
      case YouTubePlaybackMethod.ytDlpServer:
        // Needs an endpoint on MusicDatabase's server, which doesn't exist yet.
        throw YouTubeAudioException('$name: jeszcze niedostępne');
      case YouTubePlaybackMethod.cache || YouTubePlaybackMethod.youtubeApp:
        throw ArgumentError.value(method, 'method', 'gives no stream');
    }
    try {
      final streams = await fetch(videoId);
      if (streams.isNotEmpty) return _best(streams);
      throw YouTubeAudioException('$name: brak ścieżki dźwiękowej');
    } on YouTubeAudioException {
      rethrow;
    } catch (e) {
      debugPrint('YouTube audio (${method.name}) failed for $videoId: $e');
      throw YouTubeAudioException(
        isVideoGone(e)
            ? '$name: filmu nie ma już na YouTube'
            : '$name: ${e is PlatformException ? e.code : 'błąd'}',
        offline: isNetworkError(e),
        gone: isVideoGone(e),
      );
    }
  }

  static String _shortName(YouTubePlaybackMethod m) => switch (m) {
    YouTubePlaybackMethod.cache => 'pamięć podręczna',
    YouTubePlaybackMethod.newPipe => 'NewPipe',
    YouTubePlaybackMethod.explode => 'youtube_explode',
    YouTubePlaybackMethod.ytDlpServer => 'yt-dlp',
    YouTubePlaybackMethod.youtubeApp => 'aplikacja YouTube',
  };

  static YouTubeAudioStream _best(List<YouTubeAudioStream> streams) {
    for (final itag in _preferredItags) {
      final match = streams.where((s) => s.itag == itag).firstOrNull;
      if (match != null) return match;
    }
    return streams.reduce(
      (a, b) => (b.bitrate ?? 0) > (a.bitrate ?? 0) ? b : a,
    );
  }

  /// YouTube currently answers youtube_explode's stream URLs with 403 (no PO tokens), which is
  /// why this method is off by default; kept for when that changes.
  static Future<List<YouTubeAudioStream>> _explodeStreams(
    String videoId,
  ) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streams.getManifest(videoId);
      return [
        for (final s in manifest.audioOnly)
          YouTubeAudioStream(
            url: s.url.toString(),
            itag: s.tag,
            format: s.container.name,
            bitrate: s.bitrate.kiloBitsPerSecond.round(),
          ),
      ];
    } finally {
      yt.close();
    }
  }
}
