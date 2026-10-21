import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/custom_covers.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/moods.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_covers.dart';
import 'fixtures.dart';

/// MusicDatabase's mood endpoints (its `mood_sync.py`, `global_mood_log.py`), cut down to what
/// the phone relies on.
class FakeMoodServer {
  late HttpServer _server;
  final moods = <String, Map<String, Object?>>{};
  final requests = <String>[];
  final covers = FakeCoverBlobs();

  /// The user's own covers of global moods, by mood id, with their own counter.
  final globalCovers = <int, Map<String, Object?>>{};
  int coverCounter = 0;

  /// What `PUT/DELETE /global-moods/…` recorded: (mood id, song id, added).
  final globalChanges = <(int, int, bool)>[];
  int counter = 0;
  String token = 'tok';
  String user = 'tester';
  bool permitted = true;
  Set<int> globalMoodIds = {1};

  Uri get address => Uri.parse('http://127.0.0.1:${_server.port}/');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  Map<String, Object?> add(Map<String, Object?> mood) {
    final stored = {
      'cover': null,
      'created_at': mood['updated_at'],
      ...mood,
      'revision': ++counter,
      'deleted': false,
    };
    moods[stored['uid']! as String] = stored;
    return stored;
  }

  /// The owner promoted [uid] to the global mood [globalId] in MusicDatabase's menu.
  void promote(String uid, int globalId) => moods[uid] = {
    'uid': uid,
    'revision': ++counter,
    'updated_at': moods[uid]!['updated_at'],
    'deleted': true,
    'promoted_to': globalId,
    'promoted_to_name': moods[uid]!['name'],
  };

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

    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'Bearer $token') {
      return reply(HttpStatus.unauthorized);
    }
    if (covers.handle(request, raw)) return;
    final body = textOf(raw);
    final parts = request.uri.pathSegments;
    if (parts.length >= 3 && parts[2] == 'global-mood-covers') {
      if (request.method == 'GET') {
        final since = int.parse(request.uri.queryParameters['since'] ?? '0');
        return reply(HttpStatus.ok, {
          'revision': coverCounter,
          'covers': [
            for (final row in globalCovers.values)
              if ((row['revision']! as int) > since) row,
          ],
        });
      }
      final sent = jsonDecode(body) as Map<String, Object?>;
      if (covers.missing(sent) case final missing?) {
        return reply(HttpStatus.badRequest, missing);
      }
      final moodId = int.parse(parts[3]);
      final stored = globalCovers[moodId];
      if (stored != null &&
          sent['base_revision'] != stored['revision'] &&
          (sent['updated_at']! as int) <= (stored['updated_at']! as int)) {
        return reply(HttpStatus.conflict, stored);
      }
      globalCovers[moodId] = {
        'mood_id': moodId,
        'revision': ++coverCounter,
        'cover': sent['cover'],
        'updated_at': sent['updated_at'],
      };
      return reply(HttpStatus.ok, globalCovers[moodId]);
    }
    if (parts.length == 4 && parts[0] == 'global-moods') {
      final moodId = int.parse(parts[1]);
      final songId = int.parse(parts[3]);
      if (!permitted) {
        return reply(HttpStatus.forbidden, {
          'error': 'permission',
          'permission': 'edit_global_moods',
        });
      }
      if (!globalMoodIds.contains(moodId)) {
        return reply(HttpStatus.notFound, {'error': 'mood', 'mood_id': moodId});
      }
      final added = request.method == 'PUT';
      globalChanges.add((moodId, songId, added));
      return reply(HttpStatus.accepted, {
        'mood_id': moodId,
        'song_id': songId,
        'action': added ? 'add' : 'remove',
      });
    }
    if (parts.length < 3 || parts[0] != 'users' || parts[2] != 'moods') {
      return reply(HttpStatus.notFound);
    }
    if (parts[1] != user) return reply(HttpStatus.forbidden);
    final query = request.uri.queryParameters;
    if (request.method == 'GET' && parts.length == 3) {
      final since = int.parse(query['since'] ?? '0');
      final changed =
          moods.values.where((m) => (m['revision']! as int) > since).toList()
            ..sort(
              (a, b) =>
                  (a['revision']! as int).compareTo(b['revision']! as int),
            );
      return reply(HttpStatus.ok, {'revision': counter, 'moods': changed});
    }
    final uid = parts[3];
    if (request.method == 'PUT') {
      final sent = jsonDecode(body) as Map<String, Object?>;
      if (covers.missing(sent) case final missing?) {
        return reply(HttpStatus.badRequest, missing);
      }
      var stored = moods[uid];
      if (stored != null && stored['deleted'] == true) {
        if (stored['promoted_to'] != null) {
          return reply(HttpStatus.conflict, stored);
        }
      }
      // A new uid with the name of a live mood is merged into it.
      if (stored == null) {
        final same = moods.values
            .where((m) => m['deleted'] != true && m['name'] == sent['name'])
            .firstOrNull;
        if (same != null) {
          final merged = {
            ...same,
            'song_ids': ({
              ...same['song_ids']! as List,
              ...sent['song_ids']! as List,
            }.toList()..sort((a, b) => (a as int).compareTo(b as int))),
            'revision': ++counter,
          };
          moods[same['uid']! as String] = merged;
          return reply(HttpStatus.ok, merged);
        }
      }
      if (stored != null &&
          sent['base_revision'] != stored['revision'] &&
          (sent['updated_at']! as int) <= (stored['updated_at']! as int)) {
        return reply(HttpStatus.conflict, stored);
      }
      final saved = {
        'cover': stored?['cover'],
        ...sent..remove('base_revision'),
        'uid': uid,
        'revision': ++counter,
        'deleted': false,
      };
      moods[uid] = saved;
      return reply(HttpStatus.ok, saved);
    }
    if (request.method == 'DELETE') {
      final deletedAt = int.parse(query['deleted_at']!);
      moods[uid] = {
        'uid': uid,
        'revision': ++counter,
        'updated_at': deletedAt,
        'deleted': true,
      };
      return reply(HttpStatus.ok, moods[uid]);
    }
    reply(HttpStatus.notFound);
  }
}

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary local;
  late MoodLibrary moods;
  late FakeMoodServer server;
  String? userName;
  String? token;
  var permitted = true;
  var clock = DateTime(2026, 10, 13, 12);
  final revoked = <String>[];

  MoodLibrary newLibrary({CustomCovers? covers}) => MoodLibrary(
    local.database,
    sync,
    factoryOverride: databaseFactoryFfi,
    now: () => clock,
    userName: () => userName,
    authToken: () => token,
    canEditGlobal: () => permitted,
    covers: covers,
  )..onPermissionRevoked = revoked.add;

  Future<void> writeTags(Map<int, (String, String, List<int>)> tags) async =>
      writeTagDb((await sync.localFile('tag.db')).path, tags: tags);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    userName = 'tester';
    token = 'tok';
    permitted = true;
    revoked.clear();
    clock = DateTime(2026, 10, 13, 12);
    root = await Directory.systemTemp.createTemp('moods_test');
    sync = DatabaseSync(storageRoot: () async => root);
    await writeMusicDb((await sync.localFile('music.db')).path);
    await writeTags({
      1: ('Siłownia', 'mood', [1, 2]),
      2: ('spellchecked', 'marker', [1, 2, 3]),
    });
    catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    local = LocalLibrary(
      catalog,
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
    );
    moods = newLibrary();
    await moods.load();
    server = FakeMoodServer();
    await server.start();
  });

  tearDown(() async {
    await server.close();
    moods.dispose();
    local.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  Future<void> syncNow() => moods.sync([server.address]);

  test('global moods are tag.db\'s mood tags, never its markers', () async {
    expect([for (final m in moods.globalMoods) m.name], ['Siłownia']);
    expect(moods.globalMoods.single.songIds, {1, 2});

    // A tag.db from before moods has none.
    await writeTagDb(
      (await sync.localFile('tag.db')).path,
      tags: {
        1: ('Siłownia', 'mood', [1]),
      },
      withKind: false,
    );
    final older = newLibrary();
    await older.load();
    expect(older.globalMoods, isEmpty);
    older.dispose();
  });

  test(
    'a mood made here goes to the account; nothing else goes later',
    () async {
      expect(await moods.create('Chill', songIds: [2, 1]), isNull);
      expect(await moods.create('Chill'), contains('już istnieje'));
      await syncNow();

      expect(moods.lastSync!.problem, isNull);
      final stored = server.moods.values.single;
      expect(stored['name'], 'Chill');
      expect(stored['song_ids'], [1, 2]);

      server.requests.clear();
      await syncNow();
      expect(server.requests, [
        'GET /users/tester/moods',
        'GET /users/tester/global-mood-covers',
      ]);

      await moods.setSong(moods.userMoods.single, 2, false);
      await syncNow();
      expect(server.moods.values.single['song_ids'], [1]);
    },
  );

  test('moods from the account arrive; deleted and promoted ones go', () async {
    server.add({
      'uid': 'u-1',
      'name': 'Do biegania',
      'updated_at': 1,
      'song_ids': [4, 5],
    });
    server.add({
      'uid': 'u-2',
      'name': 'Sen',
      'updated_at': 1,
      'song_ids': [3],
    });
    await syncNow();
    expect([for (final m in moods.userMoods) m.name], ['Do biegania', 'Sen']);
    expect(moods.userMoods.first.songIds, {4, 5});

    server.promote('u-1', 7);
    await syncNow();
    expect([for (final m in moods.userMoods) m.name], ['Sen']);

    final sen = moods.userMoods.single;
    await moods.delete(sen);
    expect(moods.userMoods, isEmpty);
    await syncNow();
    expect(server.moods['u-2']!['deleted'], isTrue);
  });

  test('the same name made on two phones becomes one mood', () async {
    server.add({
      'uid': 'other-phone',
      'name': 'Chill',
      'updated_at': 1,
      'song_ids': [1],
    });
    // Made here before this phone heard of the other one.
    await moods.create('Chill', songIds: [3]);
    await moods.sync([server.address]);

    expect(moods.userMoods, hasLength(1));
    expect(moods.userMoods.single.songIds, {1, 3});
    expect(server.moods.keys, ['other-phone']);
  });

  test('changes to global moods need the permission and stay until tag.db has them', () async {
    final gym = moods.globalMoods.single;
    permitted = false;
    await moods.setSong(gym, 3, true);
    expect(moods.globalMoods.single.songIds, {1, 2});

    permitted = true;
    await moods.setSong(gym, 3, true);
    await moods.setSong(gym, 1, false);
    // Changed back before it went: nothing to send for song 1.
    await moods.setSong(moods.globalMoods.single, 1, true);
    expect(moods.globalMoods.single.songIds, {1, 2, 3});

    await syncNow();
    expect(server.globalChanges, [(1, 3, true)]);
    // Accepted, but MusicDatabase's tag.db doesn't have it yet: still shown.
    expect(moods.globalMoods.single.songIds, {1, 2, 3});

    // The next tag.db has it: the phone's own copy of the change goes.
    await writeTags({
      1: ('Siłownia', 'mood', [1, 2, 3]),
    });
    final restarted = newLibrary();
    await restarted.load();
    final db = await local.database();
    expect(await db.query('global_mood_changes'), isEmpty);
    expect(restarted.globalMoods.single.songIds, {1, 2, 3});
    restarted.dispose();
  });

  test('many songs at once: own and global moods', () async {
    await moods.create('Chill');
    await moods.setSongs(moods.userMoods.single, [1, 2, 3], true);
    expect(moods.userMoods.single.songIds, {1, 2, 3});
    expect(moods.moodKeysOf(2), {
      moods.userMoods.single.key,
      moods.globalMoods.single.key,
    });
    await moods.setSongs(moods.userMoods.single, [1, 2], false);
    expect(moods.userMoods.single.songIds, {3});

    await moods.setSongs(moods.globalMoods.single, [2, 3, 4], true);
    expect(moods.globalMoods.single.songIds, {1, 2, 3, 4});
    await syncNow();
    // Song 2 was there already: nothing to send for it.
    expect(server.globalChanges, unorderedEquals([(1, 3, true), (1, 4, true)]));
  });

  test('a revoked permission drops the change', () async {
    server.permitted = false;
    await moods.setSong(moods.globalMoods.single, 4, true);
    await syncNow();

    expect(revoked, ['edit_global_moods']);
    expect(moods.lastSync!.problem, contains('uprawnień'));
    expect(moods.globalMoods.single.songIds, {1, 2});
    expect(
      await (await local.database()).query('global_mood_changes'),
      isEmpty,
    );
  });

  test(
    'logged out: global moods and phone-only ones, added to the account later',
    () async {
      await moods.create('Konto');
      userName = null;
      token = null;
      await moods.load();
      // The account's mood hides; global ones show to anyone.
      expect(moods.userMoods, isEmpty);
      expect(moods.globalMoods, hasLength(1));
      expect(moods.canEditGlobal, isFalse);

      expect(await moods.create('Telefon', songIds: [3]), isNull);
      expect(moods.userMoods.single.phoneOnly, isTrue);
      expect(moods.phoneOnlyCount, 1);
      // Nothing to send while logged out.
      await syncNow();
      expect(server.requests, isEmpty);

      userName = 'tester';
      token = 'tok';
      await moods.load();
      expect([for (final m in moods.userMoods) m.name], ['Konto', 'Telefon']);
      await moods.addPhoneOnlyToAccount();
      await syncNow();
      expect(moods.phoneOnlyCount, 0);
      expect(
        {for (final m in server.moods.values) m['name']},
        {'Konto', 'Telefon'},
      );

      // A phone-only mood deleted goes at once, with no marker to send.
      userName = null;
      token = null;
      await moods.create('Chwilowy');
      await moods.delete(moods.userMoods.single);
      expect(
        await (await local.database()).query('moods', where: 'account IS NULL'),
        isEmpty,
      );
    },
  );

  test('song search finds the songs of a mood by its name', () async {
    await catalog.ensureLoaded();
    catalog.setMoodNames(moods.moodNamesOf);
    moods.addListener(catalog.moodsChanged);
    await moods.create('Do biegania', songIds: [4]);

    expect([for (final s in catalog.search('Siłownia')) s.id], [2, 1]);
    expect([for (final s in catalog.search('biegania')) s.id], [4]);
    // A word from the mood and one from the song together.
    expect([for (final s in catalog.search('silownia led')) s.id], [2]);

    await catalog.setSearchFields({SearchField.title});
    expect(catalog.search('Siłownia'), isEmpty);
    moods.removeListener(catalog.moodsChanged);
  });

  test('a mood\'s cover goes with it, the picture only when needed', () async {
    final covers = CustomCovers(
      directory: () async => Directory('${root.path}/c'),
    );
    final library = newLibrary(covers: covers);
    await library.load();
    final picture = [5, 6, 7];
    final hash = CustomCovers.hashOf(picture);
    await covers.store(hash, picture, jpeg: false);
    await library.create('Chill');
    await library.setCover(library.userMoods.single, hash);
    expect(library.userMoods.single.cover, hash);
    await library.sync([server.address]);

    expect(library.lastSync!.problem, isNull);
    expect(server.moods.values.single['cover'], hash);
    expect(server.covers.blobs[hash], picture);

    // Set on another phone: the new picture is downloaded.
    final other = [1, 1, 2, 3];
    final otherHash = CustomCovers.hashOf(other);
    server.covers.blobs[otherHash] = other;
    final uid = server.moods.keys.single;
    server.moods[uid] = {
      ...server.moods[uid]!,
      'cover': otherHash,
      'updated_at': 99999999999999,
      'revision': ++server.counter,
    };
    await library.sync([server.address]);
    expect(library.userMoods.single.cover, otherHash);
    expect(await covers.fileFor(otherHash)!.readAsBytes(), other);
    library.dispose();
    covers.dispose();
  });

  test('a global mood\'s cover is the user\'s own: phone-only logged out, then synced', () async {
    final covers = CustomCovers(
      directory: () async => Directory('${root.path}/c'),
    );
    final picture = [4, 2];
    final hash = CustomCovers.hashOf(picture);
    await covers.store(hash, picture, jpeg: false);
    userName = null;
    final library = newLibrary(covers: covers);
    await library.load();
    await library.setCover(library.globalMoods.single, hash);
    expect(library.globalMoods.single.cover, hash);

    userName = 'tester';
    await library.load();
    // Not the account's until the phone-only things are added to it.
    expect(library.globalMoods.single.cover, hash);
    await library.addPhoneOnlyToAccount();
    await library.sync([server.address]);
    expect(library.lastSync!.problem, isNull);
    expect(server.globalCovers[1]!['cover'], hash);
    expect(server.covers.blobs[hash], picture);

    // Removed on another phone, later.
    server.globalCovers[1] = {
      'mood_id': 1,
      'revision': ++server.coverCounter,
      'cover': null,
      'updated_at': 99999999999999,
    };
    await library.sync([server.address]);
    expect(library.globalMoods.single.cover, isNull);
    expect(await library.usedCovers(), isEmpty);

    // Logged out again: the account's (removed) cover isn't shown, nor is any other.
    userName = null;
    await library.load();
    expect(library.globalMoods.single.cover, isNull);
    library.dispose();
    covers.dispose();
  });

  test(
    'version 12 phones keep their moods, now allowed without an account',
    () async {
      final oldRoot = await Directory.systemTemp.createTemp('moods_v12');
      final dir = await Directory('${oldRoot.path}/local').create();
      var db = await databaseFactoryFfi.openDatabase('${dir.path}/local.db');
      await db.execute('''
      CREATE TABLE moods (
        id INTEGER PRIMARY KEY AUTOINCREMENT, uid VARCHAR NOT NULL UNIQUE,
        account VARCHAR NOT NULL, name VARCHAR NOT NULL, created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL, revision INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 0, deleted_at INTEGER)''');
      // Only what the later upgrades touch.
      await db.execute('CREATE TABLE playlists (id INTEGER PRIMARY KEY)');
      await db.insert('moods', {
        'uid': 'u',
        'account': 'tester',
        'name': 'Stary',
        'created_at': 1,
        'updated_at': 1,
      });
      await db.setVersion(12);
      await db.close();

      final upgraded = LocalLibrary(
        catalog,
        storageRoot: () async => oldRoot,
        factoryOverride: databaseFactoryFfi,
      );
      db = await upgraded.database();
      expect([for (final r in await db.query('moods')) r['name']], ['Stary']);
      // Version 14 on top: covers.
      expect(await db.query('global_mood_covers'), isEmpty);
      expect((await db.query('moods')).single['cover_sha256'], isNull);
      await db.insert('moods', {
        'uid': 'v',
        'name': 'Bez konta',
        'created_at': 1,
        'updated_at': 1,
      });
      upgraded.dispose();
      await oldRoot.delete(recursive: true);
    },
  );
}
