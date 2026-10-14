import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/playlist_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/youtube_export.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/youtube_api_fakes.dart';
import 'fixtures.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary local;
  late YouTubeLibrary youTube;
  late PlaylistLibrary playlists;
  late FakeYouTubeApi api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('youtube_export_test');
    sync = DatabaseSync(storageRoot: () async => root);
    await writeMusicDb((await sync.localFile('music.db')).path);
    catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    local = LocalLibrary(
      catalog,
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
    );
    youTube = YouTubeLibrary(local.database, storageRoot: () async => root);
    await youTube.load();
    playlists = PlaylistLibrary(local.database, catalog, youTube);
    await playlists.load();
    api = FakeYouTubeApi();
  });

  tearDown(() async {
    playlists.dispose();
    youTube.dispose();
    local.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  /// A phone playlist of songs titled by their video ids; '-' has no video and isn't found.
  Future<PlaylistSummary> phonePlaylist(List<String> videos) =>
      playlists.create('Moja', [
        for (final v in videos)
          SearchHit.youTubeOnly(
            title: v,
            artistLabel: 'Ktoś',
            videoId: v == '-' || v.startsWith('?') ? null : v,
          ),
      ]);

  Future<YouTubeExportResult> run(
    PlaylistSummary playlist, {
    String Function()? token,
    bool Function()? cancelled,
  }) async {
    final rejected = <String>[];
    return exportToYouTube(
      playlist: playlist,
      tracks: await playlists.tracks(playlist.id),
      library: playlists,
      hitOf: (track) => SearchHit.youTubeOnly(
        title: track.title,
        artistLabel: track.artist ?? '',
        videoId: track.youtubeVideoId,
      ),
      // "?x" is found by searching as "x".
      findVideo: (hit) async =>
          hit.title.startsWith('?') ? hit.title.substring(1) : null,
      token: () async => (token ?? () => 't1')(),
      tokenRejected: (t) async => rejected.add(t),
      api: api,
      cancelled: cancelled,
    );
  }

  test('makes the playlist in order, searching and skipping', () async {
    final playlist = await phonePlaylist(['a', '?b', '-', 'gone', 'c']);
    api.missing.add('gone');
    final result = await run(playlist);

    expect(result.stopped, isNull);
    expect(api.playlists[result.playlistId], ['a', 'b', 'c']);
    expect(result.added, 3);
    expect(result.skipped.map((t) => t.title), ['-', 'gone']);
    final saved = playlists.byId(playlist.id)!;
    expect(saved.youTubeCopyId, result.playlistId);
    expect(saved.youTubeCopyUnfinished, isFalse);
    expect(saved.link.toString(), contains('list=${result.playlistId}'));
    expect(saved.linksToYouTube, isTrue);
  });

  test(
    'stops at the daily limit and finishes the same playlist later',
    () async {
      final playlist = await phonePlaylist(['a', 'b', 'c', 'd']);
      api.quotaLeft = 2;
      final first = await run(playlist);
      expect(first.stopped?.quota, isTrue);
      expect(api.playlists[first.playlistId], ['a', 'b']);
      final half = playlists.byId(playlist.id)!;
      expect(half.youTubeCopyUnfinished, isTrue);
      expect(half.youTubeCopyDone, 2);

      api.quotaLeft = null;
      final second = await run(half);
      expect(second.stopped, isNull);
      expect(second.playlistId, first.playlistId);
      expect(api.playlists[first.playlistId], ['a', 'b', 'c', 'd']);
      expect(api.playlists, hasLength(1));
      expect(playlists.byId(playlist.id)!.youTubeCopyUnfinished, isFalse);
    },
  );

  test('cancelling keeps the progress', () async {
    final playlist = await phonePlaylist(['a', 'b', 'c']);
    var calls = 0;
    final result = await run(playlist, cancelled: () => ++calls > 1);
    expect(result.stopped, isNotNull);
    expect(api.playlists[result.playlistId], ['a']);
    expect(playlists.byId(playlist.id)!.youTubeCopyDone, 1);
  });

  test(
    'a stopped playlist deleted on YouTube is made again from the start',
    () async {
      final playlist = await phonePlaylist(['a', 'b']);
      api.quotaLeft = 1;
      final first = await run(playlist);
      api.playlists.remove(first.playlistId);
      api.quotaLeft = null;

      final second = await run(playlists.byId(playlist.id)!);
      expect(second.stopped, isNull);
      expect(second.playlistId, isNot(first.playlistId));
      expect(api.playlists[second.playlistId], ['a', 'b']);
    },
  );

  test('a refused token is replaced once', () async {
    final playlist = await phonePlaylist(['a']);
    final tokens = ['old', 't1'];
    final result = await run(playlist, token: () => tokens.removeAt(0));
    expect(result.stopped, isNull);
    expect(api.playlists[result.playlistId], ['a']);
  });
}
