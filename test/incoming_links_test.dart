import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/incoming_links.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/video_link.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/fixtures.dart';

void main() {
  group('YouTube links shared to / opened with the app', () {
    String? video(String text) => switch (parseYouTubeLink(text)) {
      YouTubeVideoLink(:final videoId, :final listId) =>
        listId == null ? videoId : '$videoId+$listId',
      _ => null,
    };
    String? playlist(String text) => switch (parseYouTubeLink(text)) {
      YouTubePlaylistLink(:final listId) => listId,
      _ => null,
    };

    test('videos, in every form YouTube shares them', () {
      expect(video('https://youtu.be/X2XWBcd5jn0?si=abc'), 'X2XWBcd5jn0');
      expect(
        video('https://www.youtube.com/watch?v=X2XWBcd5jn0&t=42'),
        'X2XWBcd5jn0',
      );
      expect(video('https://m.youtube.com/watch?v=X2XWBcd5jn0'), 'X2XWBcd5jn0');
      expect(
        video('https://music.youtube.com/watch?v=X2XWBcd5jn0&si=x'),
        'X2XWBcd5jn0',
      );
      expect(video('https://youtube.com/shorts/X2XWBcd5jn0'), 'X2XWBcd5jn0');
      // Shared text with words around the link.
      expect(
        video('Zobacz to: https://youtu.be/X2XWBcd5jn0 super'),
        'X2XWBcd5jn0',
      );
      // A video opened inside a playlist stays a video.
      expect(
        video('https://www.youtube.com/watch?v=X2XWBcd5jn0&list=PL1'),
        'X2XWBcd5jn0+PL1',
      );
    });

    test('playlists, and what isn\'t a YouTube link', () {
      expect(
        playlist('https://youtube.com/playlist?list=PLabc-1_x&si=y'),
        'PLabc-1_x',
      );
      expect(parseYouTubeLink('https://example.com/watch?v=X2XWBcd5jn0'), null);
      expect(parseYouTubeLink('https://www.youtube.com/@kanal'), null);
      expect(parseYouTubeLink('bez linku'), null);
    });
  });

  group('a video link becomes a song', () {
    sqfliteFfiInit();
    late Directory root;
    late SongCatalog catalog;
    late LocalLibrary library;
    late YouTubeLibrary youTube;
    late SourceSettings settings;
    late List<String> fetched;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('video_link_test');
      final sync = DatabaseSync(storageRoot: () async => root);
      await writeMusicDb((await sync.localFile('music.db')).path);
      catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      library = LocalLibrary(
        catalog,
        storageRoot: () async => root,
        factoryOverride: databaseFactoryFfi,
      );
      youTube = YouTubeLibrary(library.database, storageRoot: () async => root);
      await library.load();
      await youTube.load();
      settings = SourceSettings();
      await settings.load();
      fetched = [];
    });

    tearDown(() async {
      youTube.dispose();
      library.dispose();
      catalog.dispose();
      await root.delete(recursive: true);
    });

    YouTubeSearch search(Map<String, YouTubeVideo> videos) => YouTubeSearch(
      newPipeAvailable: false,
      explodeVideo: (id) async {
        fetched.add(id);
        final video = videos[id];
        if (video == null) throw const YouTubeSearchException('brak');
        return video;
      },
    );

    Future<SearchHit> hit(String link, Map<String, YouTubeVideo> videos) =>
        hitForVideoLink(
          parseYouTubeLink(link)! as YouTubeVideoLink,
          catalog: catalog,
          library: library,
          youTube: youTube,
          search: search(videos),
          settings: settings,
        );

    test('music.db\'s own link: no request to YouTube', () async {
      final h = await hit('https://youtu.be/X2XWBcd5jn0', {});
      expect(h.mainSong?.title, 'Małomiasteczkowy');
      expect(fetched, isEmpty);
    });

    test('by the video\'s title, remembered for next time', () async {
      final h = await hit('https://youtu.be/aaaaaaaaaaa', {
        'aaaaaaaaaaa': const YouTubeVideo(
          id: 'aaaaaaaaaaa',
          title: 'Led Zeppelin - Going to California (Official Audio)',
          channel: 'Led Zeppelin',
        ),
      });
      expect(h.mainSong?.title, 'Going to California');
      expect(h.youtubeVideoId, 'aaaaaaaaaaa');
      expect(youTube.matchFor(h.mainSong!.id), 'aaaaaaaaaaa');
    });

    test('not in the database: the video, titled from YouTube', () async {
      final h = await hit('https://youtu.be/bbbbbbbbbbb?list=PL9', {
        'bbbbbbbbbbb': const YouTubeVideo(
          id: 'bbbbbbbbbbb',
          title: 'Nieznany Zespół - Piosenka (Official Video)',
          channel: 'Nieznany Zespół',
        ),
      });
      expect(h.mainSong, isNull);
      expect((h.title, h.artistLabel), ('Piosenka', 'Nieznany Zespół'));
      expect(h.playlistVideoId, 'bbbbbbbbbbb');
    });
  });
}
