import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _video = YouTubeVideo(id: 'abc', title: 'Video', channel: 'Channel');

SearchHit _hit({String? youtubeVideoId, bool onPhone = false}) =>
    SearchHit.main(
      CatalogSong(
        id: 1,
        title: 'Song',
        artistLabel: 'Artist',
        youtubeVideoId: youtubeVideoId,
      ),
      [
        if (onPhone)
          LocalSong(
            id: 1,
            filePath: '/music/song.mp3',
            title: 'Song',
            pending: false,
          ),
      ],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('availability follows the phone file and the stored YouTube link', () {
    expect(
      _hit(youtubeVideoId: 'abc').availability,
      SongAvailability.available,
    );
    expect(_hit(onPhone: true).availability, SongAvailability.available);
    expect(_hit().availability, SongAvailability.potentiallyAvailable);
    expect(
      _hit(youtubeVideoId: 'N/A').availability,
      SongAvailability.unavailable,
    );
    expect(
      _hit(youtubeVideoId: 'N/A', onPhone: true).availability,
      SongAvailability.available,
    );

    final both = _hit(youtubeVideoId: 'abc', onPhone: true);
    expect(both.playableFrom(PlaybackSource.phone), isTrue);
    expect(both.playableFrom(PlaybackSource.youtube), isTrue);
    expect(_hit().playableFrom(PlaybackSource.youtube), isFalse);
  });

  test('source settings: defaults, saved values and playback order', () async {
    final settings = SourceSettings();
    await settings.load();
    // On by default, like Spotify's playlist search (owner's choice).
    expect(settings.youTubeSearchEnabled, isTrue);
    expect(settings.methods, {YouTubeMethod.newPipe, YouTubeMethod.explode});
    expect(settings.playbackOrder, [
      PlaybackSource.phone,
      PlaybackSource.server,
      PlaybackSource.youtube,
    ]);

    await settings.setYouTubeSearchEnabled(false);
    await settings.setMethod(YouTubeMethod.newPipe, false);
    await settings.setMethod(YouTubeMethod.explode, false);
    await settings.setMethod(YouTubeMethod.api, true);
    await settings.setApiKey('  key123 ');
    await settings.setPlaybackOrder([
      PlaybackSource.youtube,
      PlaybackSource.server,
      PlaybackSource.phone,
    ]);

    final again = SourceSettings();
    await again.load();
    expect(again.youTubeSearchEnabled, isFalse);
    expect(again.methods, {YouTubeMethod.api});
    expect(again.apiKey, 'key123');
    expect(again.playbackOrder, [
      PlaybackSource.youtube,
      PlaybackSource.server,
      PlaybackSource.phone,
    ]);

    await again.setApiKey('   ');
    expect(again.apiKey, isNull);

    expect(again.activePlaybackMethods, [
      YouTubePlaybackMethod.cache,
      YouTubePlaybackMethod.newPipe,
      YouTubePlaybackMethod.youtubeApp,
    ]);
    await again.setPlaybackMethodOrder([
      YouTubePlaybackMethod.youtubeApp,
      ...YouTubePlaybackMethod.values.where(
        (m) => m != YouTubePlaybackMethod.youtubeApp,
      ),
    ]);
    await again.setPlaybackMethod(YouTubePlaybackMethod.cache, false);
    final third = SourceSettings();
    await third.load();
    expect(third.activePlaybackMethods, [
      YouTubePlaybackMethod.youtubeApp,
      YouTubePlaybackMethod.newPipe,
    ]);
  });

  test('sources can be switched off, and stay so', () async {
    final settings = SourceSettings();
    await settings.load();
    expect(settings.enabledSources, PlaybackSource.values.toSet());
    await settings.setSourceEnabled(PlaybackSource.server, false);

    final again = SourceSettings();
    await again.load();
    expect(again.activePlaybackOrder, [
      PlaybackSource.phone,
      PlaybackSource.youtube,
    ]);
    expect(again.playbackOrder, contains(PlaybackSource.server));
  });

  test(
    'a source added later goes after the one it follows by default',
    () async {
      // Saved before "Serwer" existed.
      SharedPreferences.setMockInitialValues({
        'sources.playback_order': ['youtube', 'phone'],
      });
      final settings = SourceSettings();
      await settings.load();
      expect(settings.playbackOrder, [
        PlaybackSource.youtube,
        PlaybackSource.phone,
        PlaybackSource.server,
      ]);
    },
  );

  test('a song with a file on the server plays from it', () {
    final hit = SearchHit.main(
      CatalogSong(
        id: 1,
        title: 'Song',
        artistLabel: 'Artist',
        youtubeVideoId: 'N/A',
        serverFile: const ServerFile(id: 7, path: 'A/Song.mp3'),
      ),
      const [],
    );
    expect(hit.playableFrom(PlaybackSource.server), isTrue);
    expect(hit.availability, SongAvailability.available);
    expect(_hit().playableFrom(PlaybackSource.server), isFalse);
  });

  group('YouTubeSearch', () {
    late SourceSettings settings;
    late List<String> calls;

    setUp(() async {
      settings = SourceSettings();
      await settings.load();
      calls = [];
    });

    YouTubeSearch search({bool explodeFails = false}) => YouTubeSearch(
      explode: (q) async {
        calls.add('explode:$q');
        if (explodeFails) throw Exception('blocked');
        return [_video];
      },
      api: (q, key) async {
        calls.add('api:$q:$key');
        return [_video];
      },
    );

    test(
      'NewPipe searches first on Android, and is skipped elsewhere',
      () async {
        YouTubeSearch withNewPipe({required bool android}) => YouTubeSearch(
          newPipeAvailable: android,
          newPipe: (q) async {
            calls.add('newPipe:$q');
            return [_video];
          },
          explode: (q) async {
            calls.add('explode:$q');
            return [_video];
          },
        );
        await withNewPipe(android: true).search('q', settings);
        expect(calls, ['newPipe:q']);
        calls.clear();
        await withNewPipe(android: false).search('q', settings);
        expect(calls, ['explode:q']);
      },
    );

    test('uses the first method that is switched on', () async {
      await settings.setMethod(YouTubeMethod.api, true);
      await settings.setApiKey('k');
      expect(await search().search('q', settings), [_video]);
      expect(calls, ['explode:q']);
    });

    test('falls back to the next method when one fails', () async {
      await settings.setMethod(YouTubeMethod.ytDlpServer, true);
      await settings.setMethod(YouTubeMethod.api, true);
      await settings.setApiKey('k');
      expect(await search(explodeFails: true).search('q', settings), [_video]);
      expect(calls, ['explode:q', 'api:q:k']);
    });

    test('explains why nothing could be searched', () async {
      await settings.setMethod(YouTubeMethod.newPipe, false);
      await settings.setMethod(YouTubeMethod.explode, false);
      await expectLater(
        search().search('q', settings),
        throwsA(isA<YouTubeSearchException>()),
      );

      await settings.setMethod(YouTubeMethod.ytDlpServer, true);
      await settings.setMethod(YouTubeMethod.api, true);
      await expectLater(
        search().search('q', settings),
        throwsA(
          isA<YouTubeSearchException>().having(
            (e) => e.message,
            'message',
            allOf(contains('yt-dlp'), contains('brak kodu YouTube API')),
          ),
        ),
      );
      expect(calls, isEmpty);
    });
  });

  group('YouTubeAudio', () {
    YouTubeAudioStream stream(int itag, int bitrate) =>
        YouTubeAudioStream(url: 'u$itag', itag: itag, bitrate: bitrate);

    test(
      'prefers Opus 160k, then AAC 128k, then the highest bitrate',
      () async {
        Future<int> pick(List<YouTubeAudioStream> streams) async =>
            (await YouTubeAudio(
              newPipeAvailable: true,
              newPipe: (_) async => streams,
            ).bestStream('v', YouTubePlaybackMethod.defaults)).itag;

        expect(await pick([stream(140, 128), stream(251, 160)]), 251);
        expect(await pick([stream(249, 50), stream(140, 128)]), 140);
        expect(await pick([stream(249, 50), stream(250, 70)]), 250);
      },
    );

    test(
      'tries the switched-on methods in order; NewPipe only on Android',
      () async {
        final calls = <String>[];
        YouTubeAudio audio({
          required bool android,
          bool newPipeFails = false,
        }) => YouTubeAudio(
          newPipeAvailable: android,
          newPipe: (id) async {
            calls.add('newPipe');
            if (newPipeFails) throw Exception('403');
            return [stream(251, 160)];
          },
          explode: (id) async {
            calls.add('explode');
            return [stream(140, 128)];
          },
        );
        const all = {
          YouTubePlaybackMethod.cache,
          YouTubePlaybackMethod.newPipe,
          YouTubePlaybackMethod.explode,
        };

        expect((await audio(android: true).bestStream('v', all)).itag, 251);
        expect(calls, ['newPipe']);

        calls.clear();
        expect(
          (await audio(
            android: true,
            newPipeFails: true,
          ).bestStream('v', all)).itag,
          140,
        );
        expect(calls, ['newPipe', 'explode']);

        calls.clear();
        expect((await audio(android: false).bestStream('v', all)).itag, 140);
        expect(calls, ['explode']);
      },
    );

    test('explains when no method can play (e.g. iOS with defaults)', () async {
      await expectLater(
        YouTubeAudio(newPipeAvailable: false)
            .bestStream('v', YouTubePlaybackMethod.defaults),
        throwsA(isA<YouTubeAudioException>()),
      );
    });

    test('cached files get the stream\'s container as extension', () {
      expect(stream(251, 160).extension, 'webm');
      expect(stream(140, 128).extension, 'm4a');
    });
  });
}
