import '../l10n.dart';
import 'youtube_audio.dart';

/// "Jakość" in Informacje o utworze for the YouTube audio stream the player chose: YouTube's own
/// format, untouched ("Opus, 135 kb/s (YouTube, itag 251)").
String youTubeStreamQuality(YouTubeAudioStream stream) {
  final kbps = stream.bitrate;
  final format = [
    _formatName(stream.extension, fromYouTube: true),
    if (kbps != null && kbps > 0) '$kbps kb/s',
  ].join(', ');
  return '$format (YouTube, itag ${stream.itag})';
}

/// "Jakość" for a whole file: its format from the extension and, when its length is known, the
/// average bitrate ("FLAC, bezstratny, średnio 912 kb/s"). [fromYouTube]: audio YouTube gave,
/// whose `.m4a` is always AAC (a phone's own `.m4a` may be ALAC).
String fileQuality(
  String path, {
  int? sizeBytes,
  Duration? duration,
  bool fromYouTube = false,
}) {
  final dot = path.lastIndexOf('.');
  final extension = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  final kbps = sizeBytes == null || duration == null || duration.inSeconds < 1
      ? null
      : (sizeBytes * 8 / duration.inMilliseconds).round();
  return [
    _formatName(extension, fromYouTube: fromYouTube),
    if (kbps != null) l10n.audioQualityAverageBitrate(kbps),
  ].join(', ');
}

String _formatName(String extension, {required bool fromYouTube}) =>
    switch (extension) {
      'webm' || 'opus' => 'Opus',
      'm4a' || 'mp4' || 'aac' when fromYouTube => 'AAC',
      'm4a' || 'mp4' => l10n.audioQualityM4a,
      'aac' => 'AAC',
      'mp3' => 'MP3',
      'ogg' || 'oga' => 'Ogg Vorbis',
      'flac' => l10n.audioQualityLossless('FLAC'),
      'wav' => l10n.audioQualityLossless('WAV'),
      'aif' || 'aiff' => l10n.audioQualityLossless('AIFF'),
      'wv' => l10n.audioQualityLossless('WavPack'),
      'ape' => l10n.audioQualityLossless("Monkey's Audio"),
      'wma' => 'WMA',
      '' => l10n.audioQualityUnknownFormat,
      _ => extension.toUpperCase(),
    };
