import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/audio_quality.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';

void main() {
  test('a YouTube stream shows its format, bitrate and itag', () {
    expect(
      youTubeStreamQuality(
        const YouTubeAudioStream(url: 'u', itag: 251, bitrate: 135),
      ),
      'Opus, 135 kb/s (YouTube, itag 251)',
    );
    expect(
      youTubeStreamQuality(
        const YouTubeAudioStream(url: 'u', itag: 140, bitrate: -1),
      ),
      'AAC (YouTube, itag 140)',
    );
  });

  test('a file shows its format and average bitrate', () {
    expect(
      fileQuality(
        '/music/a.flac',
        sizeBytes: 30000000,
        duration: const Duration(minutes: 4),
      ),
      'FLAC, bezstratny, średnio 1000 kb/s',
    );
    expect(fileQuality('/music/a.m4a'), 'M4A (AAC lub ALAC)');
    expect(fileQuality('/cache/v.m4a', fromYouTube: true), 'AAC');
    expect(fileQuality('/music/a.MP3'), 'MP3');
  });
}
