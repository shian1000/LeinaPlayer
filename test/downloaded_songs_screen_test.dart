import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/server_downloads.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/downloads.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:music_database_app/src/screens/cache_settings_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/fixtures.dart';
import 'playback_test.dart' show FakeBackend;
import 'support/waiting.dart';

const _video = 'abcdefghijk';

void main() {
  sqfliteFfiInit();

  late Directory storage;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary local;
  late YouTubeLibrary youTube;
  late ServerDownloads server;
  late SourceSettings settings;
  late PlayerController player;
  late PlaybackQueue queue;
  late Downloads downloads;
  late FakeBackend backend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await Directory.systemTemp.createTemp('downloaded_songs_test');
  });

  tearDown(() async {
    downloads.dispose();
    queue.dispose();
    player.dispose();
    server.dispose();
    youTube.dispose();
    local.dispose();
    catalog.dispose();
    sync.dispose();
    settings.dispose();
    await storage.delete(recursive: true);
  });

  /// Kept with "Pobierz": files 10 and 13 are songs 1 and 2 of music.db, file 99 no song's, and
  /// a YouTube video music.db doesn't know.
  Future<void> seed() async {
    sync = DatabaseSync(storageRoot: () async => storage);
    await writeMusicDb((await sync.localFile('music.db')).path);
    await writeFilesDb((await sync.localFile('files.db')).path, [
      (10, 'Dawid Podsiadło/Małomiasteczkowy.mp3', 5000, 1),
      (13, 'Led Zeppelin/Going to California.mp3', 6000, 2),
    ]);
    catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    local = LocalLibrary(
      catalog,
      storageRoot: () async => storage,
      factoryOverride: databaseFactoryFfi,
    );
    await catalog.ensureLoaded();
    await local.load();

    final db = await local.database();
    final filesDir = await Directory(
      '${storage.path}/downloads',
    ).create(recursive: true);
    for (final id in [10, 13, 99]) {
      await File('${filesDir.path}/$id.mp3').writeAsBytes(List.filled(50, 1));
      await db.insert('server_downloads', {
        'file_id': id,
        'file_name': '$id.mp3',
        'size_bytes': 1024 * 1024,
        'downloaded_at': 1,
      });
    }
    final videoDir = await Directory(
      '${storage.path}/youtube_cache',
    ).create(recursive: true);
    await File('${videoDir.path}/$_video.m4a').writeAsBytes(List.filled(50, 1));
    await db.insert('youtube_cache', {
      'video_id': _video,
      'file_name': '$_video.m4a',
      'size_bytes': 2 * 1024 * 1024,
      'downloaded_at': 1,
      'last_played_at': 1,
      'pinned': 1,
    });
    await db.insert('youtube_track_matches', {
      'track_key': 'zespol|arka',
      'artist': 'Zespół',
      'title': 'Arka',
      'video_id': _video,
      'matched_at': 1,
    });

    youTube = YouTubeLibrary(local.database, storageRoot: () async => storage);
    await youTube.load();
    server = ServerDownloads(local.database, storageRoot: () async => storage);
    await server.load();
    settings = SourceSettings();
    await settings.load();
    backend = FakeBackend();
    player = PlayerController(backend: () => backend);
  }

  Future<void> pumpList(WidgetTester tester) async {
    await tester.runAsync(seed);
    final tracks = TrackPlayer(
      player: player,
      settings: settings,
      youTubeLibrary: youTube,
      youTubeAudio: YouTubeAudio(newPipeAvailable: false),
      youTubeSearch: YouTubeSearch(),
      serverDownloads: server,
    );
    queue = PlaybackQueue(prefetchDelay: Duration.zero, tracks);
    downloads = Downloads(
      tracks,
      server,
      youTube,
      database: local.database,
      resolve: (_) => throw UnimplementedError(),
    );
    await tester.pumpWidget(
      DatabaseSyncScope(
        notifier: sync,
        child: SongCatalogScope(
          notifier: catalog,
          child: LocalLibraryScope(
            notifier: local,
            child: YouTubeLibraryScope(
              notifier: youTube,
              child: PlayerScope(
                notifier: player,
                child: PlaybackQueueScope(
                  notifier: queue,
                  child: SourceSettingsScope(
                    notifier: settings,
                    child: DownloadsScope(
                      notifier: downloads,
                      child: MaterialApp(
                        theme: buildAppTheme(dummifyTheme),
                        home: const CacheSettingsScreen(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pobrane utwory'));
    await pumpUntil(tester, () => find.text('Arka').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
  }

  testWidgets('the tile opens the songs kept with "Pobierz", by title', (
    tester,
  ) async {
    await pumpList(tester);

    expect(find.text('Utwory: 4, 5.0 MB'), findsOneWidget);
    final top = <String, double>{
      for (final title in [
        'Arka',
        'Going to California',
        'Małomiasteczkowy',
        '99.mp3',
      ])
        title: tester.getTopLeft(find.text(title)).dy,
    };
    expect(top['Arka']!, lessThan(top['Going to California']!));
    expect(top['Going to California']!, lessThan(top['Małomiasteczkowy']!));
    // No song for it: last, and only to be removed.
    expect(top['Małomiasteczkowy']!, lessThan(top['99.mp3']!));
    expect(find.textContaining('Nie ma go już w bazie'), findsOneWidget);

    await tester.tap(find.text('Going to California'));
    await pumpUntil(tester, () => queue.current != null);
    expect(queue.current!.title, 'Going to California');
    expect(queue.upcoming.single.hit.title, 'Małomiasteczkowy');
  });

  testWidgets('⊖ takes one song out of the downloads', (tester) async {
    await pumpList(tester);
    final buttons = find.byTooltip('Usuń z pobranych');
    expect(buttons, findsNWidgets(4));

    // Arka, YouTube audio: back in the cache, not deleted.
    await tester.tap(buttons.first);
    await pumpUntil(tester, () => find.text('Arka').evaluate().isEmpty);
    expect(youTube.isPinned(_video), isFalse);
    expect(youTube.isCached(_video), isTrue);

    // 99.mp3, a server file: gone from the phone.
    await tester.tap(buttons.last);
    await pumpUntil(tester, () => find.text('99.mp3').evaluate().isEmpty);
    expect(server.isDownloaded(99), isFalse);
    expect(find.text('Utwory: 2, 2.0 MB'), findsOneWidget);
  });
}
