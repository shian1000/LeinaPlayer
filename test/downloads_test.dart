import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/server_downloads.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/track_ref.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/download_notification.dart';
import 'package:music_database_app/src/playback/downloads.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'playback_test.dart' show FakeBackend;

class _Notification extends DownloadNotification {
  final shown = <String>[];
  var hidden = 0;

  @override
  Future<void> show({
    required int done,
    required int total,
    required String title,
  }) async => shown.add('$done/$total $title');

  @override
  Future<void> hide() async => hidden++;
}

/// A music.db song whose file is on the server as files.id [fileId], not on YouTube.
SearchHit _song(int fileId) => SearchHit.main(
  CatalogSong(
    id: fileId,
    title: 'Song $fileId',
    artistLabel: 'Artist',
    youtubeVideoId: 'N/A',
    serverFile: ServerFile(id: fileId, path: 'Artist/Song $fileId.mp3'),
  ),
  const [],
);

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary local;
  late HttpServer server;
  late SourceSettings settings;
  late PlayerController player;
  late _Notification notification;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('downloads_test');
    sync = DatabaseSync(storageRoot: () async => root);
    catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    local = LocalLibrary(
      catalog,
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      // Files 1 and 2 are on the server, others not.
      if (const {'/library/1', '/library/2'}.contains(request.uri.path)) {
        request.response.add(List.filled(50, 1));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    settings = SourceSettings();
    await settings.load();
    player = PlayerController(backend: FakeBackend.new);
    notification = _Notification();
  });

  tearDown(() async {
    player.dispose();
    await server.close(force: true);
    local.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  /// A fresh start of the app: its own objects over the same local.db and files.
  Future<Downloads> start() async {
    final serverDownloads = ServerDownloads(
      local.database,
      storageRoot: () async => root,
    );
    await serverDownloads.load();
    final youTube = YouTubeLibrary(
      local.database,
      storageRoot: () async => root,
    );
    await youTube.load();
    final tracks = TrackPlayer(
      player: player,
      settings: settings,
      youTubeLibrary: youTube,
      youTubeAudio: YouTubeAudio(newPipeAvailable: false),
      youTubeSearch: YouTubeSearch(),
      serverDownloads: serverDownloads,
      serverAddresses: () async => [
        Uri.parse('http://127.0.0.1:${server.port}/'),
      ],
    );
    return Downloads(
      tracks,
      serverDownloads,
      youTube,
      database: local.database,
      resolve: (ref) => _song(ref.mainDbId!),
      notification: notification,
    );
  }

  test('songs download one at a time under the notification', () async {
    final downloads = await start();
    expect(await downloads.download([_song(1), _song(2)]), 0);
    // The run ends just after: the notification goes, the queue is read again.
    await downloads.resume();
    expect(downloads.isDownloaded(_song(1)), isTrue);
    expect(downloads.isDownloaded(_song(2)), isTrue);
    expect(downloads.isDownloading(_song(1)), isFalse);
    expect(notification.shown, ['0/2 Song 1', '1/2 Song 2']);
    expect(notification.hidden, 1);
    expect(await (await local.database()).query('download_queue'), isEmpty);
  });

  test(
    'a queue Android stopped carries on when the app starts again',
    () async {
      // What a killed app left behind: a song still waiting.
      await (await local.database()).insert('download_queue', {
        'track_key': TrackRef.of(_song(2)).key,
        'track': jsonEncode(TrackRef.of(_song(2)).toJson()),
        'added_at': 0,
      });
      final downloads = await start();
      await downloads.resume();
      expect(downloads.isDownloaded(_song(2)), isTrue);
      expect(await (await local.database()).query('download_queue'), isEmpty);
    },
  );

  test(
    'a song that fails stays queued for the next runs, then is given up',
    () async {
      final downloads = await start();
      expect(await downloads.download([_song(3)]), 1);
      await downloads.resume();
      expect(downloads.isDownloading(_song(3)), isTrue, reason: 'still queued');

      for (var run = 2; run <= Downloads.maxAttempts; run++) {
        await downloads.resume();
      }
      expect(downloads.isDownloading(_song(3)), isFalse);
      expect(await (await local.database()).query('download_queue'), isEmpty);
    },
  );

  test('taking a song off also takes it out of the queue', () async {
    final downloads = await start();
    await downloads.download([_song(3)]);
    await downloads.remove([_song(3)]);
    expect(downloads.isDownloading(_song(3)), isFalse);
  });
}
