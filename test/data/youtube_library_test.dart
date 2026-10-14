import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary local;
  late DateTime now;

  LocalLibrary newLocal() => LocalLibrary(
    catalog,
    storageRoot: () async => root,
    factoryOverride: databaseFactoryFfi,
  );
  YouTubeLibrary newLibrary() => YouTubeLibrary(
    local.database,
    storageRoot: () async => root,
    now: () => now,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('youtube_library_test');
    sync = DatabaseSync(storageRoot: () async => root);
    catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    local = newLocal();
    now = DateTime(2026, 10, 11, 12);
  });

  tearDown(() async {
    local.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  /// A finished download, as just_audio leaves it.
  Future<File> downloaded(YouTubeLibrary library, String id) async {
    final file = await library.newCacheFile(id, 'webm');
    await file.writeAsBytes(List.filled(1000, 1));
    await File('${file.path}.mime').writeAsString('audio/webm');
    return file;
  }

  test('a phone-found match is remembered across restarts', () async {
    final library = newLibrary();
    await library.load();
    await library.saveMatch(
      7,
      const YouTubeVideo(id: 'abc', title: 'T', channel: 'C'),
    );
    expect(library.matchFor(7), 'abc');

    final again = newLibrary();
    await again.load();
    expect(again.matchFor(7), 'abc');
    expect(again.matchFor(8), isNull);
  });

  test('videos MusicDatabase found bad: matches to them forgotten, kept out until it changes', () async {
    final library = newLibrary();
    await library.load();
    const gone = YouTubeVideo(id: 'gone', title: 'T', channel: 'C');
    const wrong = YouTubeVideo(id: 'wrong', title: 'T', channel: 'C');
    await library.saveMatch(1, gone);
    await library.saveMatch(2, wrong);
    await library.saveMatch(3, wrong);
    await library.saveTrackMatch('A', 'B', gone);

    expect(
      await library.useBadVideos(
        const BadVideos(
          everySong: {'gone'},
          forSong: {
            2: {'wrong'},
          },
        ),
      ),
      3,
    );
    expect(library.matchFor(1), isNull);
    expect(library.matchFor(2), isNull);
    expect(library.matchFor(3), 'wrong'); // only wrong for song 2
    expect(library.matchForTrack('A', 'B'), isNull);
    expect(library.isVideoRemoved('gone'), isTrue);
    expect(library.isWrongFor(2, 'wrong'), isTrue);
    expect(library.isWrongFor(3, 'wrong'), isFalse);
    // Not the phone's own removed videos: never reported as dead links.
    expect(library.removedVideos, isEmpty);

    // A queued row still holding the turned-down video drops it.
    final song = CatalogSong(id: 2, title: 'T', artistLabel: 'A');
    final queued = SearchHit.main(song, const [], phoneMatch: 'wrong');
    expect(withPhoneYouTube(queued, library).youtubeVideoId, isNull);

    // Off MusicDatabase's list (the owner picked it): usable again, and not stored.
    await library.useBadVideos(BadVideos.none);
    expect(library.isVideoRemoved('gone'), isFalse);
    final again = newLibrary();
    await again.load();
    expect(again.isVideoRemoved('gone'), isFalse);
  });

  test('a match for a track known only by name is remembered', () async {
    final library = newLibrary();
    await library.load();
    await library.saveTrackMatch(
      'Queen, David Bowie',
      'Under Pressure',
      const YouTubeVideo(id: 'up', title: 'T', channel: 'C'),
    );
    final again = newLibrary();
    await again.load();
    // Same normalisation as search: case and accents don't matter.
    expect(again.matchForTrack('queen, david bowie', 'UNDER PRESSURE'), 'up');
    expect(again.matchForTrack('Queen', 'Under Pressure'), isNull);
  });

  test(
    '"not found on YouTube" is remembered for a while, until a video is found',
    () async {
      final library = newLibrary();
      await library.load();
      await library.saveNotFound(artist: 'Ktoś', title: 'Rzadki utwór');
      await library.saveNotFound(mainDbId: 3, artist: 'A', title: 'T');

      final again = newLibrary();
      await again.load();
      expect(again.notFoundTrack('ktos', 'Rzadki utwór'), isTrue);
      expect(again.notFoundSong(3), isTrue);
      expect(again.notFoundSong(4), isFalse);

      now = now.add(YouTubeLibrary.notFoundFor);
      expect(again.notFoundSong(3), isFalse);

      now = DateTime(2026, 10, 11, 12);
      await again.saveMatch(
        3,
        const YouTubeVideo(id: 'v3', title: 't', channel: 'c'),
      );
      expect(again.notFoundSong(3), isFalse);
      final third = newLibrary();
      await third.load();
      expect(third.notFoundSong(3), isFalse);
    },
  );

  test(
    'rows show what the phone learned on YouTube since they were made',
    () async {
      final library = newLibrary();
      await library.load();
      // As a queue holds it: no video yet.
      final queued = SearchHit.youTubeOnly(
        title: 'Gypsy',
        artistLabel: 'Fleetwood Mac',
        videoId: null,
      );
      expect(withPhoneYouTube(queued, library).youTube, YouTubeLink.unknown);

      await library.saveNotFound(artist: 'Fleetwood Mac', title: 'Gypsy');
      expect(withPhoneYouTube(queued, library).youTube, YouTubeLink.notFound);

      await library.saveTrackMatch(
        'Fleetwood Mac',
        'Gypsy',
        const YouTubeVideo(id: 'gyp', title: 't', channel: 'c'),
      );
      final shown = withPhoneYouTube(queued, library);
      expect(shown.youTube, YouTubeLink.linked);
      expect(shown.youtubeVideoId, 'gyp');
    },
  );

  test('keeps at most the limit, dropping the least recently played', () async {
    final library = newLibrary();
    await library.load();
    for (final id in ['a', 'b', 'c']) {
      now = now.add(const Duration(minutes: 1));
      await library.cacheComplete(id, await downloaded(library, id), 3);
    }
    expect(library.cachedCount, 3);
    expect(library.cachedBytes, 3000);

    // Playing "a" again makes "b" the least recently played.
    now = now.add(const Duration(minutes: 1));
    expect(await library.cachedFile('a'), isNotNull);
    now = now.add(const Duration(minutes: 1));
    final d = await downloaded(library, 'd');
    await library.cacheComplete('d', d, 3);

    expect(await library.cachedFile('b'), isNull);
    expect(await File('${root.path}/youtube_cache/b.webm').exists(), isFalse);
    expect(
      await File('${root.path}/youtube_cache/b.webm.mime').exists(),
      isFalse,
    );
    for (final id in ['a', 'c', 'd']) {
      expect(await library.cachedFile(id), isNotNull, reason: id);
    }

    await library.trim(1);
    expect(library.cachedCount, 1);
    await library.clearCache();
    expect(library.cachedCount, 0);
  });

  test(
    'unfinished downloads are deleted on start; a vanished file is dropped',
    () async {
      final library = newLibrary();
      await library.load();
      final kept = await downloaded(library, 'kept');
      await library.cacheComplete('kept', kept, 25);
      final gone = await downloaded(library, 'gone');
      await library.cacheComplete('gone', gone, 25);
      await gone.delete();
      final part = File('${root.path}/youtube_cache/half.webm.part');
      await part.writeAsString('x');

      final again = newLibrary();
      await again.load();
      expect(await part.exists(), isFalse);
      expect(again.cachedCount, 1);
      expect(await again.cachedFile('kept'), isNotNull);
    },
  );

  test('a local.db from before the YouTube tables is upgraded', () async {
    final dir = await Directory('${root.path}/local').create(recursive: true);
    final old = await databaseFactoryFfi.openDatabase(
      '${dir.path}/local.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE local_songs (id INTEGER PRIMARY KEY, title VARCHAR, '
          'file_path VARCHAR NOT NULL UNIQUE, main_db_id INTEGER, '
          'pending INTEGER NOT NULL DEFAULT 0, added_at INTEGER NOT NULL)',
        ),
      ),
    );
    await old.close();

    final library = newLibrary();
    await library.load();
    await library.saveMatch(
      1,
      const YouTubeVideo(id: 'x', title: 'T', channel: 'C'),
    );
    expect(library.matchFor(1), 'x');
  });

  group('download', () {
    late HttpServer server;
    late List<int> audio;
    late List<String?> ranges;
    var honourRange = true;

    setUp(() async {
      audio = List.generate(2 * 1024 * 1024 + 123, (i) => i % 251);
      ranges = [];
      honourRange = true;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path != '/a') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        final range = request.headers.value(HttpHeaders.rangeHeader);
        ranges.add(range);
        final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range ?? '');
        if (!honourRange || match == null) {
          request.response.add(audio);
        } else {
          final start = int.parse(match.group(1)!);
          final end = min(int.parse(match.group(2)!), audio.length - 1);
          request.response
            ..statusCode = HttpStatus.partialContent
            ..headers.set('content-range', 'bytes $start-$end/${audio.length}')
            ..add(audio.sublist(start, end + 1));
        }
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    String url() => 'http://${server.address.address}:${server.port}/a';

    test('fetches 1 MB ranges and records the complete file', () async {
      final library = newLibrary();
      await library.load();
      await library.download('v', url(), 'webm', 25);

      expect(ranges, [
        'bytes=0-1048575',
        'bytes=1048576-2097151',
        'bytes=2097152-3145727',
      ]);
      final file = await library.cachedFile('v');
      expect(await file!.readAsBytes(), audio);
      expect(
        await File('${root.path}/youtube_cache/v.webm.part').exists(),
        isFalse,
      );
    });

    test('a server ignoring Range gives the whole file at once', () async {
      honourRange = false;
      final library = newLibrary();
      await library.load();
      await library.download('v', url(), 'webm', 25);
      expect(ranges, hasLength(1));
      expect(await (await library.cachedFile('v'))!.readAsBytes(), audio);
    });

    test('a failed download leaves nothing behind', () async {
      final library = newLibrary();
      await library.load();
      await library.download('v', '${url()}/missing', 'webm', 25);
      final address = url();
      await server.close(force: true);
      await library.download('w', address, 'webm', 25);
      expect(library.cachedCount, 0);
      final leftovers = await Directory('${root.path}/youtube_cache')
          .list()
          .toList();
      expect(leftovers, isEmpty);
    });
  });
}
