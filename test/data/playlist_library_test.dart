import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/playlist_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_playlist.dart';
import 'package:music_database_app/src/data/youtube_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary local;
  late YouTubeLibrary youTube;
  late PlaylistLibrary playlists;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('playlist_library_test');
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
  });

  tearDown(() async {
    playlists.dispose();
    youTube.dispose();
    local.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  YouTubeVideo v(
    String id,
    String title,
    String channel, [
    int seconds = 200,
  ]) => YouTubeVideo(
    id: id,
    title: title,
    channel: channel,
    duration: Duration(seconds: seconds),
  );

  YouTubePlaylistData data(List<YouTubeVideo> videos, {String name = 'Moja'}) =>
      YouTubePlaylistData(
        id: 'PL1',
        name: name,
        owner: 'Shian',
        videos: videos,
      );

  test('imports in order, recognising songs by video first, then by name', () async {
    // Phone-matched earlier: "Going to California" (songs.id 2) is video "gtc".
    await youTube.saveMatch(
      2,
      const YouTubeVideo(id: 'gtc', title: 't', channel: 'c'),
    );
    final result = await playlists.importYouTube(
      data([
        // music.db links song 1 to X2XWBcd5jn0, whatever the title says.
        v('X2XWBcd5jn0', 'Jakiś zupełnie inny tytuł', 'Kanał'),
        v('gtc', 'Led Zeppelin - Going To California (Remaster)', 'x'),
        v('p1', 'Pusty', 'Artur Rojek - Topic'),
        v('zz', 'Nieznany - Utwór (Official Video)', 'Nieznany', 100),
      ]),
    );

    expect(result.updated, isFalse);
    expect(result.recognised, 3);
    expect(result.playlist.trackCount, 4);
    expect(result.playlist.duration, const Duration(seconds: 700));
    expect(playlists.playlists.single.name, 'Moja');

    final tracks = await playlists.tracks(result.playlist.id);
    expect([for (final t in tracks) t.position], [0, 1, 2, 3]);
    expect([for (final t in tracks) t.mainDbId], [1, 2, 4, null]);
    expect(
      [for (final t in tracks) t.youtubeVideoId],
      ['X2XWBcd5jn0', 'gtc', 'p1', 'zz'],
    );
    // Recognised songs keep MusicDatabase's spelling; the rest what the title gave.
    expect(tracks[0].title, 'Małomiasteczkowy');
    expect((tracks[3].artist, tracks[3].title), ('Nieznany', 'Utwór'));
  });

  test('importing the same playlist again replaces it', () async {
    await playlists.importYouTube(
      data([v('a', 'A - 1', 'x'), v('b', 'B - 2', 'x')]),
    );
    final again = await playlists.importYouTube(
      data([v('c', 'C - 3', 'x')], name: 'Nowa nazwa'),
    );
    expect(again.updated, isTrue);
    expect(playlists.playlists, hasLength(1));
    expect(playlists.playlists.single.name, 'Nowa nazwa');
    expect((await playlists.tracks(again.playlist.id)).single.title, '3');

    await playlists.delete(again.playlist.id);
    expect(playlists.playlists, isEmpty);
  });
}
