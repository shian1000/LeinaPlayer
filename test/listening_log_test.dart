import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/listening_log.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/playback/listening_tracker.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Backend implements AudioBackend {
  final positions = StreamController<Duration>.broadcast();
  final _state = StreamController<({bool playing, bool completed})>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();

  @override
  Stream<Duration> get position => positions.stream;
  @override
  Stream<Duration?> get duration => _duration.stream;
  @override
  Stream<({bool playing, bool completed})> get state => _state.stream;
  @override
  Stream<MediaSkip> get skips => const Stream.empty();
  @override
  Future<void> open(NowPlaying track) async =>
      _duration.add(const Duration(minutes: 3));
  @override
  Future<void> crossfadeTo(NowPlaying track, Duration fade) async {}
  @override
  Future<void> play() async => _state.add((playing: true, completed: false));
  @override
  Future<void> pause() async => _state.add((playing: false, completed: false));
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> dispose() async {}
}

/// MusicDatabase's listen endpoints as the hand-off describes them
/// (`docs/handoffs/musicdatabase-listening-stats.md`), cut down to what the phone relies on.
class _FakeListenServer {
  late HttpServer _server;
  final listens = <String, Map<String, Object?>>{};
  int counter = 0;
  bool supported = true;
  int posts = 0;

  Uri get address => Uri.parse('http://127.0.0.1:${_server.port}/');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  void store(Map<String, Object?> listen) {
    final uid = listen['uid']! as String;
    final stored = listens[uid];
    final ms = listen['listened_ms']! as int;
    if (stored != null && (stored['listened_ms']! as int) >= ms) return;
    listens[uid] = {...?stored, ...listen, 'revision': ++counter};
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final response = request.response;
    void reply(int status, [Object? json]) {
      response.statusCode = status;
      if (json != null) {
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(json));
      }
      response.close();
    }

    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'Bearer tok') {
      return reply(HttpStatus.unauthorized);
    }
    if (!supported || request.uri.path != '/users/owner/listens') {
      return reply(HttpStatus.notFound);
    }
    if (request.method == 'GET') {
      final since = int.parse(request.uri.queryParameters['since'] ?? '0');
      final limit = int.parse(request.uri.queryParameters['limit'] ?? '1000');
      final changed = [
        for (final l in listens.values)
          if ((l['revision']! as int) > since) l,
      ]..sort((a, b) => (a['revision']! as int) - (b['revision']! as int));
      final page = changed.take(limit).toList();
      final more = changed.length > limit;
      return reply(HttpStatus.ok, {
        'revision': more ? page.last['revision'] : counter,
        'listens': page,
        'more': more,
      });
    }
    posts++;
    final sent = jsonDecode(body) as Map<String, Object?>;
    for (final l in sent['listens']! as List) {
      store(l as Map<String, Object?>);
    }
    return reply(HttpStatus.ok, {'revision': counter});
  }
}

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary library;
  String? user;
  var clock = DateTime(2026, 10, 16, 12);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('listening_log_test');
    sync = DatabaseSync(storageRoot: () async => root);
    catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    library = LocalLibrary(
      catalog,
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
    );
    user = null;
    clock = DateTime(2026, 10, 16, 12);
  });

  tearDown(() async {
    library.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  ListeningLog newLog() => ListeningLog(
    library.database,
    userName: () => user,
    authToken: () => user == null ? null : 'tok',
    now: () => clock,
  );

  SearchHit song(String title) => SearchHit.youTubeOnly(
    title: title,
    artistLabel: 'Kino',
    videoId: 'vid$title',
  );

  group('ListeningTracker', () {
    late _Backend backend;
    late PlayerController player;
    late StreamController<QueuePlay> played;
    late ListeningLog log;
    late ListeningTracker tracker;

    setUp(() {
      backend = _Backend();
      player = PlayerController(backend: () => backend);
      played = StreamController<QueuePlay>.broadcast();
      log = newLog();
      tracker = ListeningTracker(
        played: played.stream,
        player: player,
        log: log,
        playlistUid: (id) => id == 7 ? 'uid-7' : null,
      );
    });

    tearDown(() {
      tracker.dispose();
      player.dispose();
      log.dispose();
      played.close();
    });

    Future<void> startSong(String title, {int? playlistId}) async {
      clock = clock.add(const Duration(minutes: 5));
      await player.play(
        NowPlaying(
          title: title,
          artist: 'Kino',
          source: 'https://stream/$title',
          youtubeVideoId: 'vid$title',
          coverSeed: title,
        ),
      );
      played.add((
        hit: song(title),
        playlistId: playlistId,
        playlistName: playlistId == null ? null : 'Do auta',
        moodKey: null,
        external: false,
      ));
      await pumpEventQueue();
    }

    Future<void> positions(List<int> seconds) async {
      for (final s in seconds) {
        backend.positions.add(Duration(seconds: s));
        await pumpEventQueue();
      }
    }

    test(
      'counts the position moving on while playing, not seeks or pauses',
      () async {
        await startSong('Gruppa krovi', playlistId: 7);
        await positions([0, 1, 2, 3]);
        // A seek forward.
        await positions([60, 61]);
        await player.togglePlay();
        await pumpEventQueue();
        await positions([62, 63]);
        await player.togglePlay();
        await pumpEventQueue();
        await positions([64]);

        await startSong('Kukushka');
        await positions([0, 2]);

        final listens = await log.listens(account: null);
        expect(
          [for (final l in listens) l.title],
          ['Gruppa krovi', 'Kukushka'],
        );
        final first = listens.first;
        expect(first.listened, const Duration(seconds: 5));
        expect(first.duration, const Duration(minutes: 3));
        expect(first.source, ListenSource.youtube);
        expect(first.youtubeVideoId, 'vidGruppa krovi');
        expect(first.playlistUid, 'uid-7');
        expect(first.playlistName, 'Do auta');
        expect(listens.last.listened, const Duration(seconds: 2));
      },
    );

    test('a song handed to the YouTube app ends the play before', () async {
      await startSong('Gruppa krovi');
      await positions([0, 1]);
      played.add((
        hit: song('Kukushka'),
        playlistId: null,
        playlistName: null,
        moodKey: null,
        external: true,
      ));
      await pumpEventQueue();
      await positions([2, 3]);

      final listens = await log.listens(account: null);
      expect(listens, hasLength(1));
      expect(listens.single.listened, const Duration(seconds: 1));
      expect(log.current, isNull);
    });

    test('the listened time reaches local.db as the song goes on', () async {
      await startSong('Gruppa krovi');
      await positions([for (var s = 0; s <= 31; s++) s]);
      final rows = await (await library.database()).query('listens');
      expect(rows.single['listened_ms'], 30000);
    });
  });

  group('sync', () {
    late _FakeListenServer server;
    late ListeningLog log;

    setUp(() async {
      server = _FakeListenServer();
      await server.start();
      log = newLog();
    });

    tearDown(() async {
      log.dispose();
      await server.close();
    });

    Future<void> play(String title, int seconds) async {
      await log.start(title: title, source: ListenSource.phone);
      await log.listened(Duration(seconds: seconds));
      await log.finish();
      clock = clock.add(const Duration(minutes: 5));
    }

    test('plays made logged out go to the account that logs in', () async {
      await play('Gruppa krovi', 200);
      user = 'owner';
      await play('Kukushka', 10);
      await log.sync([server.address]);

      expect(log.lastSync?.problem, isNull);
      expect([
        for (final l in server.listens.values) l['title'],
      ], unorderedEquals(['Gruppa krovi', 'Kukushka']));
      expect(server.listens.values.first.containsKey('account'), isFalse);
      final mine = await log.listens(account: 'owner');
      expect([for (final l in mine) l.account], ['owner', 'owner']);

      // Nothing new: nothing sent.
      final posts = server.posts;
      await log.sync([server.address]);
      expect(server.posts, posts);
    });

    test(
      'takes other phones\' plays, page by page, and the longer time',
      () async {
        user = 'owner';
        final uid = await log.start(title: 'Here', source: ListenSource.phone);
        await log.listened(const Duration(seconds: 20));
        await log.finish();
        for (var i = 0; i < ListeningLog.batchSize + 3; i++) {
          server.store({
            'uid': 'other-$i',
            'started_at': clock.millisecondsSinceEpoch + i,
            'listened_ms': 1000,
            'title': 'Song $i',
            'source': 'server',
          });
        }
        server.store({
          'uid': uid,
          'started_at': clock.millisecondsSinceEpoch,
          'listened_ms': 90000,
          'title': 'Here',
          'source': 'phone',
        });

        await log.sync([server.address]);
        expect(log.lastSync?.problem, isNull);
        final listens = await log.listens(account: 'owner');
        expect(listens, hasLength(ListeningLog.batchSize + 4));
        expect(
          listens.firstWhere((l) => l.uid == uid).listened,
          const Duration(seconds: 90),
        );
        expect(server.listens[uid]!['listened_ms'], 90000);
        expect(server.posts, 0);
      },
    );

    test(
      'a server without the endpoints says so and keeps the plays',
      () async {
        user = 'owner';
        server.supported = false;
        await play('Gruppa krovi', 200);
        await log.sync([server.address]);
        expect(
          log.lastSync?.problem,
          'Serwer MusicDatabase nie obsługuje jeszcze statystyk słuchania',
        );

        server.supported = true;
        await log.sync([server.address]);
        expect(server.listens, hasLength(1));
      },
    );
  });
}
