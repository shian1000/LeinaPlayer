import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_test.dart' show FakeBackend;

SearchHit _song({String? youtubeVideoId = 'N/A'}) => SearchHit.main(
  CatalogSong(
    id: 1,
    title: 'Song',
    artistLabel: 'Artist',
    youtubeVideoId: youtubeVideoId,
    serverFile: const ServerFile(id: 42, path: 'Artist/Song.mp3'),
  ),
  const [],
);

void main() {
  late HttpServer server;
  late Map<String, int> answers;
  late List<String> asked;
  late FakeBackend backend;
  late PlayerController player;
  late SourceSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    answers = {'/library/42': HttpStatus.ok};
    asked = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      asked.add('${request.method} ${request.uri.path}');
      request.response.statusCode =
          answers[request.uri.path] ?? HttpStatus.notFound;
      request.response.close();
    });
    backend = FakeBackend();
    player = PlayerController(backend: () => backend);
    settings = SourceSettings();
    await settings.load();
    // YouTube streams straight to the player, with no cache on disk.
    await settings.setPlaybackMethod(YouTubePlaybackMethod.cache, false);
  });

  tearDown(() async {
    player.dispose();
    await server.close(force: true);
  });

  Uri base() => Uri.parse('http://127.0.0.1:${server.port}/');

  // Nothing listens there: a refused connection, like a server out of reach.
  final unreachable = Uri.parse('http://127.0.0.1:1/');

  TrackPlayer tracks(List<Uri> Function() addresses) => TrackPlayer(
    player: player,
    settings: settings,
    youTubeLibrary: YouTubeLibrary(() => Future.error(StateError('unused'))),
    youTubeAudio: YouTubeAudio(
      newPipeAvailable: true,
      newPipe: (id) async => [
        YouTubeAudioStream(url: 'https://yt/$id', itag: 251),
      ],
    ),
    youTubeSearch: YouTubeSearch(),
    openExternal: (_) async => true,
    serverAddresses: () async => addresses(),
  );

  test('streams the file from the first address that answers', () async {
    final outcome = await tracks(() => [unreachable, base()]).play(_song());
    expect(outcome.played, isTrue);
    expect(backend.opened, ['${base()}library/42']);
    expect(asked, ['HEAD /library/42']);
    expect(
      player.current!.serverFileId,
      42,
      reason: 'its row shows it playing',
    );
  });

  test('a file the server no longer has is not "no connection"', () async {
    answers.clear();
    final outcome = await tracks(() => [base()]).play(_song());
    expect(outcome.played, isFalse);
    expect(outcome.offline, isFalse);
    expect(outcome.message, contains('Song.mp3'));
    expect(backend.opened, isEmpty);
  });

  test('out of reach: offline, unless the next source plays it', () async {
    final noLink = await tracks(() => [unreachable]).play(_song());
    expect(noLink.played, isFalse);
    expect(noLink.offline, isTrue);

    final linked = await tracks(() => [unreachable])
        .play(_song(youtubeVideoId: 'abcdefghijk'));
    expect(linked.played, isTrue);
    expect(backend.opened, ['https://yt/abcdefghijk']);
  });

  test('YouTube first in the order wins over the server', () async {
    await settings.setPlaybackOrder([
      PlaybackSource.youtube,
      PlaybackSource.server,
      PlaybackSource.phone,
    ]);
    await tracks(() => [base()]).play(_song(youtubeVideoId: 'abcdefghijk'));
    expect(backend.opened, ['https://yt/abcdefghijk']);
    expect(asked, isEmpty);
  });

  test('a switched-off source is passed over', () async {
    await settings.setSourceEnabled(PlaybackSource.server, false);
    await tracks(() => [base()]).play(_song(youtubeVideoId: 'abcdefghijk'));
    expect(backend.opened, ['https://yt/abcdefghijk']);
    expect(asked, isEmpty, reason: 'the server is not even asked');

    await settings.setSourceEnabled(PlaybackSource.server, true);
    await settings.setSourceEnabled(PlaybackSource.youtube, false);
    await settings.setYouTubeSearchEnabled(true);
    final noServer = await tracks(() => [unreachable])
        .play(_song(youtubeVideoId: null));
    expect(noServer.played, isFalse);
    expect(
      noServer.message,
      'Nie można połączyć się z serwerem MusicDatabase.',
      reason: 'YouTube switched off is not searched instead',
    );
    expect(backend.opened, ['https://yt/abcdefghijk']);
  });
}
