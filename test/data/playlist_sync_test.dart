import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/custom_covers.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/playlist_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_playlist.dart';
import 'package:music_database_app/src/data/youtube_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_covers.dart';
import 'fixtures.dart';

/// MusicDatabase's playlist endpoints, with its rules (its `playlist_sync.py`) cut down to
/// what the phone relies on.
class FakePlaylistServer {
  late HttpServer _server;
  final playlists = <String, Map<String, Object?>>{};
  final requests = <String>[];
  final covers = FakeCoverBlobs();
  int counter = 0;
  String token = 'tok';
  String user = 'tester';

  /// false: a server from before added tracks, which drops their mark.
  bool keepsAddedMark = true;

  Uri get address => Uri.parse('http://127.0.0.1:${_server.port}/');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  /// A playlist made on the server (e.g. from a folder in MusicDatabase's menu).
  Map<String, Object?> add(Map<String, Object?> playlist) {
    final stored = {
      'source': null,
      'source_id': null,
      'source_owner': null,
      'cover': null,
      'excluded_source_tracks': const <String>[],
      'created_at': playlist['updated_at'],
      ...playlist,
      'revision': ++counter,
      'deleted': false,
    };
    playlists[stored['uid']! as String] = stored;
    return stored;
  }

  Future<void> _handle(HttpRequest request) async {
    requests.add('${request.method} ${request.uri.path}');
    final raw = await readBody(request);
    final response = request.response;
    void reply(int status, [Object? json]) {
      response.statusCode = status;
      if (json != null) {
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(json));
      }
      response.close();
    }

    if (request.method == 'PUT' && request.contentLength < 0) {
      return reply(HttpStatus.lengthRequired);
    }
    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'Bearer $token') {
      return reply(HttpStatus.unauthorized);
    }
    if (covers.handle(request, raw)) return;
    final body = textOf(raw);
    final parts = request.uri.pathSegments;
    if (parts.length < 3 || parts[0] != 'users' || parts[2] != 'playlists') {
      return reply(HttpStatus.notFound);
    }
    if (parts[1] != user) return reply(HttpStatus.forbidden);
    final query = request.uri.queryParameters;
    if (request.method == 'GET' && parts.length == 3) {
      final since = int.parse(query['since'] ?? '0');
      final changed =
          playlists.values
              .where((p) => (p['revision']! as int) > since)
              .toList()
            ..sort(
              (a, b) =>
                  (a['revision']! as int).compareTo(b['revision']! as int),
            );
      return reply(HttpStatus.ok, {
        'revision': counter,
        'playlists': [for (final p in changed) _out(p)],
      });
    }
    if (parts.length != 4) return reply(HttpStatus.notFound);
    final uid = parts[3];
    if (request.method == 'PUT') {
      final sent = jsonDecode(body) as Map<String, Object?>;
      if (covers.missing(sent) case final missing?) {
        return reply(HttpStatus.badRequest, missing);
      }
      var stored = playlists[uid];
      if (stored == null &&
          sent['source'] != null &&
          sent['source_id'] != null) {
        stored = playlists.values
            .where(
              (p) =>
                  p['deleted'] != true &&
                  p['source'] == sent['source'] &&
                  p['source_id'] == sent['source_id'],
            )
            .firstOrNull;
      }
      if (stored != null &&
          sent['base_revision'] != stored['revision'] &&
          (sent['updated_at']! as int) <= (stored['updated_at']! as int)) {
        return reply(HttpStatus.conflict, _out(stored));
      }
      final keptUid = stored?['uid'] ?? uid;
      final saved = {
        'cover': stored?['cover'],
        'excluded_source_tracks':
            stored?['excluded_source_tracks'] ?? const <String>[],
        ...sent..remove('base_revision'),
        if (!keepsAddedMark)
          'tracks': [
            for (final t in sent['tracks']! as List)
              {...t as Map<String, Object?>}..remove('added'),
          ],
        'uid': keptUid,
        'revision': ++counter,
        'deleted': false,
      };
      playlists[keptUid as String] = saved;
      return reply(HttpStatus.ok, _out(saved));
    }
    if (request.method == 'DELETE') {
      final deletedAt = int.parse(query['deleted_at']!);
      final stored = playlists[uid];
      if (stored == null) {
        return reply(HttpStatus.ok, {
          'uid': uid,
          'revision': 0,
          'updated_at': deletedAt,
          'deleted': true,
        });
      }
      if (stored['deleted'] != true &&
          int.parse(query['base_revision']!) != stored['revision'] &&
          deletedAt <= (stored['updated_at']! as int)) {
        return reply(HttpStatus.conflict, _out(stored));
      }
      if (stored['deleted'] != true) {
        playlists[uid] = {
          'uid': uid,
          'revision': ++counter,
          'updated_at': deletedAt,
          'deleted': true,
        };
      }
      return reply(HttpStatus.ok, _out(playlists[uid]!));
    }
    reply(HttpStatus.notFound);
  }

  static Map<String, Object?> _out(Map<String, Object?> p) =>
      p['deleted'] == true
      ? {
          'uid': p['uid'],
          'revision': p['revision'],
          'updated_at': p['updated_at'],
          'deleted': true,
        }
      : p;
}

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary local;
  late YouTubeLibrary youTube;
  late PlaylistLibrary playlists;
  late CustomCovers covers;
  late FakePlaylistServer server;
  String? userName;
  String? token;
  var clock = DateTime(2026, 10, 13, 12);
  var unauthorized = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    userName = 'tester';
    token = 'tok';
    unauthorized = 0;
    clock = DateTime(2026, 10, 13, 12);
    root = await Directory.systemTemp.createTemp('playlist_sync_test');
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
    covers = CustomCovers(directory: () async => Directory('${root.path}/c'));
    await covers.load();
    playlists = PlaylistLibrary(
      local.database,
      catalog,
      youTube,
      now: () => clock,
      userName: () => userName,
      authToken: () => token,
      covers: covers,
    )..onUnauthorized = () => unauthorized++;
    await playlists.load();
    server = FakePlaylistServer();
    await server.start();
  });

  tearDown(() async {
    await server.close();
    playlists.dispose();
    covers.dispose();
    youTube.dispose();
    local.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  YouTubePlaylistData data(
    List<String> videoIds, {
    String id = 'PL1',
    String name = 'Moja',
  }) => YouTubePlaylistData(
    id: id,
    name: name,
    owner: 'Autor',
    videos: [
      for (final v in videoIds)
        YouTubeVideo(
          id: v,
          title: 'Ktoś - $v',
          channel: 'c',
          duration: const Duration(seconds: 100),
        ),
    ],
  );

  Future<void> syncNow() => playlists.sync([server.address]);

  test('sends a playlist imported while logged in, with its tracks', () async {
    await playlists.importYouTube(data(['a', 'b']));
    await syncNow();

    expect(playlists.lastSync!.problem, isNull);
    final stored = server.playlists.values.single;
    expect(stored['name'], 'Moja');
    expect(stored['source'], 'youtube');
    expect(stored['source_id'], 'PL1');
    expect(stored['source_owner'], 'Autor');
    expect(
      [for (final t in stored['tracks']! as List) t['youtube_video_id']],
      ['a', 'b'],
    );
    expect(playlists.playlists.single.account, 'tester');

    // Nothing changed since: only the GET goes.
    server.requests.clear();
    await syncNow();
    expect(server.requests, ['GET /users/tester/playlists']);
  });

  test(
    'a track removed from an imported playlist stays out on other phones too',
    () async {
      final id = (await playlists.importYouTube(data(['a', 'b']))).playlist.id;
      await syncNow();

      clock = clock.add(const Duration(minutes: 1));
      await playlists.removeTrack(id, 0);
      await syncNow();
      expect(playlists.lastSync!.problem, isNull);
      final stored = server.playlists.values.single;
      expect(stored['excluded_source_tracks'], ['a']);
      expect(
        [for (final t in stored['tracks']! as List) t['youtube_video_id']],
        ['b'],
      );

      // Another phone: the exclusion comes with the playlist and holds on its next import.
      stored['excluded_source_tracks'] = ['a', 'b'];
      stored['revision'] = ++server.counter;
      await syncNow();
      clock = clock.add(const Duration(minutes: 1));
      await playlists.importYouTube(data(['a', 'b', 'c']));
      expect(
        [for (final t in await playlists.tracks(id)) t.youtubeVideoId],
        ['c'],
      );
    },
  );

  for (final keepsMark in [true, false]) {
    test(
      'a song added to an imported playlist stays through sync and the next '
      'import${keepsMark ? '' : ' (a server that drops the mark)'}',
      () async {
        server.keepsAddedMark = keepsMark;
        await catalog.ensureLoaded();
        final id = (await playlists.importYouTube(data(['a', 'b'])))
            .playlist
            .id;
        clock = clock.add(const Duration(minutes: 1));
        await playlists.addSongs(id, [
          SearchHit.main(catalog.byId(2)!, const []),
        ]);
        await syncNow();
        expect(playlists.lastSync!.problem, isNull);
        final sent = server.playlists.values.single['tracks']! as List;
        expect([
          for (final t in sent) (t as Map)['added'],
        ], keepsMark ? [false, false, true] : [null, null, null]);
        expect((await playlists.tracks(id)).last.added, isTrue);

        clock = clock.add(const Duration(minutes: 1));
        await playlists.importYouTube(data(['a', 'b', 'c']));
        expect(
          [
            for (final t in await playlists.tracks(id))
              t.youtubeVideoId ?? t.mainDbId,
          ],
          ['a', 'b', 2, 'c'],
        );
      },
    );
  }

  test('a picked cover goes with its playlist; the picture only when the server lacks it', () async {
    final picture = [1, 2, 3, 4];
    final hash = CustomCovers.hashOf(picture);
    await covers.store(hash, picture, jpeg: false);
    final id = (await playlists.importYouTube(data(['a']))).playlist.id;
    await syncNow();

    clock = clock.add(const Duration(minutes: 1));
    await playlists.setCover(id, hash);
    expect(playlists.byId(id)!.cover, hash);
    server.requests.clear();
    await syncNow();
    expect(playlists.lastSync!.problem, isNull);
    expect(server.playlists.values.single['cover'], hash);
    expect(server.covers.blobs[hash], picture);
    expect(server.requests, [
      'GET /users/tester/playlists',
      'PUT /users/tester/playlists/${server.playlists.keys.single}',
      'PUT /users/tester/covers/$hash',
      'PUT /users/tester/playlists/${server.playlists.keys.single}',
    ]);

    // Another change sends the same cover without its picture.
    clock = clock.add(const Duration(minutes: 1));
    await playlists.importYouTube(data(['a', 'b']));
    server.requests.clear();
    await syncNow();
    expect(server.requests.where((r) => r.contains('/covers/')), isEmpty);
    expect(server.playlists.values.single['cover'], hash);

    clock = clock.add(const Duration(minutes: 1));
    await playlists.setCover(id, null);
    await syncNow();
    expect(server.playlists.values.single['cover'], isNull);
    expect(await playlists.usedCovers(), isEmpty);
  });

  test('a cover picked on another phone is downloaded', () async {
    final picture = [9, 8, 7];
    final hash = CustomCovers.hashOf(picture);
    server.covers.blobs[hash] = picture;
    server.add({
      'uid': 'other-0001',
      'name': 'Z drugiego telefonu',
      'cover': hash,
      'updated_at': 1000,
      'tracks': const [],
    });
    await syncNow();

    expect(playlists.playlists.single.cover, hash);
    expect(await covers.fileFor(hash)!.readAsBytes(), picture);
    expect(await playlists.usedCovers(), {hash});
  });

  test('receives the server\'s playlists, and their deletion', () async {
    server.add({
      'uid': 'folder-0001',
      'name': '0. Fixed',
      'source': 'folder',
      'source_id': '/media/x/0. Fixed',
      'updated_at': 1000,
      'tracks': [
        {
          'song_id': 2,
          'title': 'Going to California',
          'artist': 'Led Zeppelin',
        },
        {'song_id': null, 'title': 'Spoza bazy', 'youtube_removed': true},
      ],
    });
    await syncNow();

    final fixed = playlists.playlists.single;
    expect(fixed.name, '0. Fixed');
    expect(fixed.source, PlaylistSource.folder);
    expect(fixed.link, isNull);
    final tracks = await playlists.tracks(fixed.id);
    expect([for (final t in tracks) t.mainDbId], [2, null]);
    expect(tracks[1].videoRemoved, isTrue);

    server.playlists['folder-0001'] = {
      'uid': 'folder-0001',
      'revision': ++server.counter,
      'updated_at': 2000,
      'deleted': true,
    };
    await syncNow();
    expect(playlists.playlists, isEmpty);
  });

  test('deleting an account playlist deletes it on the server', () async {
    await playlists.importYouTube(data(['a']));
    await syncNow();
    final id = playlists.playlists.single.id;

    await playlists.delete(id);
    expect(playlists.playlists, isEmpty);
    await syncNow();
    expect(server.playlists.values.single['deleted'], isTrue);
    final rows = await (await local.database()).query('playlists');
    expect(rows, isEmpty);
  });

  test('a newer change from elsewhere wins over an older one here', () async {
    await playlists.importYouTube(data(['a']));
    await syncNow();
    final uid = server.playlists.keys.single;

    // Changed here at 12:05 (not sent yet), on another phone at 12:10.
    clock = DateTime(2026, 10, 13, 12, 5);
    await playlists.importYouTube(data(['a', 'b']));
    server.playlists[uid] = {
      ...server.playlists[uid]!,
      'name': 'Z drugiego telefonu',
      'updated_at': DateTime(2026, 10, 13, 12, 10).millisecondsSinceEpoch,
      'tracks': [
        {'title': 'c', 'youtube_video_id': 'c'},
      ],
      'revision': ++server.counter,
    };
    await syncNow();

    final playlist = playlists.playlists.single;
    expect(playlist.name, 'Z drugiego telefonu');
    expect(
      [for (final t in await playlists.tracks(playlist.id)) t.youtubeVideoId],
      ['c'],
    );
    expect(server.playlists[uid]!['name'], 'Z drugiego telefonu');
  });

  test('a newer change here wins over an older one from elsewhere', () async {
    await playlists.importYouTube(data(['a']));
    await syncNow();
    final uid = server.playlists.keys.single;

    server.playlists[uid] = {
      ...server.playlists[uid]!,
      'name': 'Starsza zmiana',
      'updated_at': DateTime(2026, 10, 13, 12, 1).millisecondsSinceEpoch,
      'revision': ++server.counter,
    };
    clock = DateTime(2026, 10, 13, 12, 5);
    await playlists.rename(playlists.playlists.single.id, 'Nowsza');
    await syncNow();

    expect(server.playlists[uid]!['name'], 'Nowsza');
    expect(playlists.playlists.single.name, 'Nowsza');
  });

  test(
    'the same playlist imported elsewhere first keeps that one\'s id',
    () async {
      server.add({
        'uid': 'other-phone-1',
        'name': 'Moja',
        'source': 'youtube',
        'source_id': 'PL1',
        'updated_at': 1000,
        'tracks': const [],
      });
      // Imported here before ever syncing. The server's copy arrives first and waits; the
      // phone's change is newer, so it stays.
      await playlists.importYouTube(data(['a']));
      await syncNow();

      final rows = await (await local.database()).query('playlists');
      expect(rows, hasLength(1));
      expect(rows.single['uid'], 'other-phone-1');
      expect(server.playlists, hasLength(1));
      expect(
        (server.playlists['other-phone-1']!['tracks']! as List).single['title'],
        'a',
      );
    },
  );

  test(
    'logging out hides the account\'s playlists until it logs in again',
    () async {
      await playlists.importYouTube(data(['a']));
      userName = null;
      token = null;
      await playlists.load();
      expect(playlists.playlists, isEmpty);

      await playlists.importYouTube(data(['b'], id: 'PL2', name: 'Telefon'));
      expect(playlists.playlists.single.account, isNull);
      server.requests.clear();
      await syncNow();
      expect(server.requests, isEmpty);

      userName = 'tester';
      token = 'tok';
      await playlists.load();
      expect(
        {for (final p in playlists.playlists) p.name},
        {'Moja', 'Telefon'},
      );
      expect(await playlists.phoneOnlyCount(), 1);
      await playlists.addPhoneOnlyToAccount();
      await syncNow();
      expect(
        {for (final p in server.playlists.values) p['name']},
        {'Moja', 'Telefon'},
      );
    },
  );

  test('a refused login stops the sync and asks to log in again', () async {
    await playlists.importYouTube(data(['a']));
    server.token = 'other';
    await syncNow();
    expect(unauthorized, 1);
    expect(playlists.lastSync!.problem, contains('zaloguj się ponownie'));
    expect(server.playlists, isEmpty);
  });
}
