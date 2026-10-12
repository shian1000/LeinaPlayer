import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/playlist_library.dart';
import 'package:music_database_app/src/data/playlist_search.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SourceSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SourceSettings();
    await settings.load();
  });

  YouTubeSearch searchWith(Object? Function() answer) => YouTubeSearch(
    newPipeAvailable: true,
    newPipeVideo: (id) async {
      final result = answer();
      if (result is Exception) throw result;
      return YouTubeVideo(id: id, title: 'T', channel: 'C');
    },
    explodeVideo: (id) async {
      final result = answer();
      if (result is Exception) throw result;
      return YouTubeVideo(id: id, title: 'T', channel: 'C');
    },
  );

  test('a video is there, gone, or unknown without a connection', () async {
    expect(await searchWith(() => null).videoExists('v', settings), isTrue);
    expect(
      await searchWith(
        () => PlatformException(code: 'ContentNotAvailableException'),
      ).videoExists('v', settings),
      isFalse,
    );
    expect(
      await searchWith(() => const SocketException('no route'))
          .videoExists('v', settings),
      isNull,
    );
  });

  test('playlists are searched with the first method that works', () async {
    FoundPlaylist found(String name) =>
        FoundPlaylist(source: PlaylistSource.youtube, id: 'PL1', name: name);
    final search = YouTubeSearch(
      newPipeAvailable: true,
      newPipePlaylists: (q) async => throw const SocketException('offline'),
      explodePlaylists: (q) async => [found('$q z explode')],
    );
    final result = await search.searchPlaylists('rock', settings);
    expect([for (final p in result) p.name], ['rock z explode']);

    final failing = YouTubeSearch(
      newPipeAvailable: false,
      explodePlaylists: (q) async => throw const SocketException('offline'),
    );
    await expectLater(
      failing.searchPlaylists('rock', settings),
      throwsA(
        isA<YouTubeSearchException>().having((e) => e.offline, 'offline', true),
      ),
    );
  });
}
