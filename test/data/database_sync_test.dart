import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _sqlite = [...'SQLite format 3\u0000'.codeUnits, 1, 2, 3];

void main() {
  late Directory storage;
  late HttpServer server;
  late Map<String, List<int>> served;
  late DateTime now;
  String? wifi;
  // A stand-in for GitHub: the release URLs answer with a redirect to the file host, as
  // GitHub's do.
  late HttpServer gitHub;
  late Map<String, List<int>> released;
  late Map<String, Object?> version;
  late List<String> gitHubRequests;

  DatabaseSync newSync() => DatabaseSync(
    storageRoot: () async => storage,
    now: () => now,
    currentWifi: () async => wifi,
    gitHubRelease: (repo) => Uri.parse(
      'http://127.0.0.1:${gitHub.port}/$repo/releases/download/database/',
    ),
  );

  Map<String, Object?> describe(Map<String, List<int>> files) => {
    'format': 1,
    'published_at': '2026-10-21T11:35:11Z',
    'files': {
      for (final MapEntry(:key, :value) in files.entries)
        key: {
          'size': value.length,
          'sha256': sha256.convert(value).toString(),
          'content_sha256': 'ignored',
        },
    },
  };

  Future<String> localContent(DatabaseSync sync, String name) async =>
      String.fromCharCodes(await (await sync.localFile(name)).readAsBytes());

  setUp(() async {
    // The tests of the server addresses run without the GitHub fallback; its group turns it on.
    SharedPreferences.setMockInitialValues({'database_sync.github_on': false});
    storage = await Directory.systemTemp.createTemp('database_sync_test');
    now = DateTime(2026, 10, 10, 9);
    served = {'music.db': _sqlite, 'tag.db': _sqlite, 'files.db': _sqlite};
    wifi = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      final body = served[request.uri.pathSegments.last];
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.add(body);
      }
      request.response.close();
    });
    released = {
      'music.db': _sqlite,
      'tag.db': [..._sqlite, 7],
    };
    version = describe(released);
    gitHubRequests = [];
    gitHub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    gitHub.listen((request) {
      final segments = request.uri.pathSegments;
      final response = request.response;
      if (segments.first == 'files') {
        final body = released[segments.last];
        if (body == null) {
          response.statusCode = HttpStatus.notFound;
        } else {
          response.add(body);
        }
      } else if (segments.join('/') ==
          'shian1000/LeinaMusicDatabase/releases/download/database/${segments.last}') {
        gitHubRequests.add(segments.last);
        if (segments.last == 'version.json') {
          response.write(jsonEncode(version));
        } else {
          response.statusCode = HttpStatus.found;
          response.headers.set(
            HttpHeaders.locationHeader,
            '/files/${segments.last}',
          );
        }
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      response.close();
    });
  });

  tearDown(() async {
    await gitHub.close(force: true);
    await server.close(force: true);
    await storage.delete(recursive: true);
  });

  group('normalizeUrl', () {
    test('empty input turns downloading off', () {
      expect(DatabaseSync.normalizeUrl('  '), isNull);
    });

    test('adds http:// and a trailing slash', () {
      expect(
        DatabaseSync.normalizeUrl('100.1.2.3:8002').toString(),
        'http://100.1.2.3:8002/',
      );
      expect(
        DatabaseSync.normalizeUrl('https://host/db').toString(),
        'https://host/db/',
      );
    });

    test('a link to one of the files becomes its folder', () {
      expect(
        DatabaseSync.normalizeUrl('http://host:8002/db/music.db').toString(),
        'http://host:8002/db/',
      );
    });

    test('rejects other schemes', () {
      expect(
        () => DatabaseSync.normalizeUrl('ftp://host/'),
        throwsFormatException,
      );
    });
  });

  test('downloads both files once a day', () async {
    final sync = newSync();
    await sync.load();
    await sync.setRemoteUrl('127.0.0.1:${server.port}');

    await sync.syncIfDue();
    expect(sync.lastError, isNull);
    expect(sync.lastSync, now);
    for (final name in DatabaseSync.fileNames) {
      expect(await localContent(sync, name), String.fromCharCodes(_sqlite));
    }

    served = {};
    now = DateTime(2026, 10, 10, 23);
    await sync.syncIfDue();
    expect(sync.lastError, isNull, reason: 'already downloaded today');

    now = DateTime(2026, 10, 11, 8);
    await sync.syncIfDue();
    expect(sync.lastError, 'Serwer zwrócił błąd 404 dla music.db');
  });

  test('goes on without files.db when the server has none', () async {
    final sync = newSync();
    await sync.load();
    await sync.setRemoteUrl('127.0.0.1:${server.port}');
    expect(await sync.syncNow(), isTrue);
    expect(await (await sync.localFile('files.db')).exists(), isTrue);

    served.remove('files.db');
    expect(await sync.syncNow(), isTrue);
    expect(sync.lastError, isNull);
    expect(
      await (await sync.localFile('files.db')).exists(),
      isFalse,
      reason: 'a copy the server no longer has is stale',
    );
    expect(await localContent(sync, 'music.db'), String.fromCharCodes(_sqlite));
  });

  test('remembers address and last download across restarts', () async {
    final first = newSync();
    await first.load();
    await first.setRemoteUrl('127.0.0.1:${server.port}');
    expect(await first.syncNow(), isTrue);

    final second = newSync();
    await second.load();
    expect(second.remoteUrl, first.remoteUrl);
    expect(second.lastSync, now);
  });

  test('keeps the old copy when a new file is not a database', () async {
    final sync = newSync();
    await sync.load();
    await sync.setRemoteUrl('127.0.0.1:${server.port}');
    expect(await sync.syncNow(), isTrue);

    served['tag.db'] = '<html>404</html>'.codeUnits;
    served['music.db'] = [..._sqlite, 9];
    expect(await sync.syncNow(), isFalse);

    expect(sync.lastError, 'tag.db z serwera nie jest bazą SQLite');
    expect(await localContent(sync, 'music.db'), String.fromCharCodes(_sqlite));
    final leftovers = (await sync.databaseDirectory()).listSync().where(
      (e) => e.path.endsWith('.part'),
    );
    expect(leftovers, isEmpty);
  });

  test('reports an unreachable server', () async {
    final sync = newSync();
    await sync.load();
    final port = server.port;
    await server.close(force: true);
    await sync.setRemoteUrl('127.0.0.1:$port');

    expect(await sync.syncNow(), isFalse);
    expect(sync.lastError, 'Nie można połączyć się z serwerem');
    expect(sync.lastSync, isNull);
  });

  group('local address on the home Wi-Fi', () {
    late HttpServer localServer;
    late List<String> localRequests;

    setUp(() async {
      localRequests = [];
      localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      localServer.listen((request) {
        localRequests.add(request.uri.pathSegments.last);
        request.response.add(_sqlite);
        request.response.close();
      });
    });

    tearDown(() => localServer.close(force: true));

    Future<DatabaseSync> configured() async {
      final sync = newSync();
      await sync.load();
      await sync.setRemoteUrl('127.0.0.1:${server.port}');
      await sync.setLocalUrl('127.0.0.1:${localServer.port}');
      await sync.setLocalWifi('Dom');
      return sync;
    }

    test('is used while connected to the saved Wi-Fi', () async {
      final sync = await configured();
      wifi = 'Dom';
      expect(await sync.syncNow(), isTrue);
      expect(sync.lastSource, DatabaseSource.local);
      expect(localRequests, DatabaseSync.fileNames);
    });

    test('is skipped on another network', () async {
      final sync = await configured();
      wifi = 'Kawiarnia';
      expect(await sync.syncNow(), isTrue);
      expect(sync.lastSource, DatabaseSource.remote);
      expect(localRequests, isEmpty);
    });

    test(
      'falls back to the remote address when the local server is down',
      () async {
        final sync = await configured();
        wifi = 'Dom';
        await localServer.close(force: true);
        expect(await sync.syncNow(), isTrue);
        expect(sync.lastSource, DatabaseSource.remote);
      },
    );

    test('without a remote address, nothing is downloaded away from home', () async {
      final sync = await configured();
      await sync.setRemoteUrl('');
      wifi = null;
      expect(sync.hasSource, isTrue);
      expect(await sync.syncNow(), isFalse);
      expect(
        sync.lastError,
        'Telefon nie jest w sieci lokalnej, a adres zdalny nie jest ustawiony',
      );
    });

    test(
      'settings and the source of the last download survive a restart',
      () async {
        final first = await configured();
        wifi = 'Dom';
        expect(await first.syncNow(), isTrue);

        final second = newSync();
        await second.load();
        expect(second.localUrl, first.localUrl);
        expect(second.localWifi, 'Dom');
        expect(second.lastSource, DatabaseSource.local);
      },
    );
  });

  group('GitHub', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<List<int>> localBytes(DatabaseSync sync, String name) async =>
        (await sync.localFile(name)).readAsBytes();

    test('a fresh install downloads the default repository', () async {
      final sync = newSync();
      await sync.load();
      expect(sync.gitHubOn, isTrue);
      expect(sync.gitHubRepo, 'shian1000/LeinaMusicDatabase');
      expect(sync.hasServer, isFalse);
      expect(sync.hasSource, isTrue);

      await sync.syncIfDue();
      expect(sync.lastError, isNull);
      expect(sync.lastSource, DatabaseSource.github);
      expect(sync.lastSync, now);
      expect(await localBytes(sync, 'music.db'), released['music.db']);
      expect(await localBytes(sync, 'tag.db'), released['tag.db']);
      expect(gitHubRequests, ['version.json', 'music.db', 'tag.db']);
    });

    test('downloads only the files whose hash changed', () async {
      final sync = newSync();
      await sync.load();
      expect(await sync.syncNow(), isTrue);

      gitHubRequests.clear();
      expect(await sync.syncNow(), isTrue);
      expect(gitHubRequests, ['version.json'], reason: 'nothing changed');

      released['tag.db'] = [..._sqlite, 8, 8];
      version = describe(released);
      gitHubRequests.clear();
      expect(await sync.syncNow(), isTrue);
      expect(gitHubRequests, ['version.json', 'tag.db']);
      expect(await localBytes(sync, 'tag.db'), [..._sqlite, 8, 8]);
    });

    test('keeps the old pair when a file is newer than version.json', () async {
      final sync = newSync();
      await sync.load();
      expect(await sync.syncNow(), isTrue);

      // A publish under way: music.db already replaced, version.json not yet.
      released['music.db'] = [..._sqlite, 5];
      released['tag.db'] = [..._sqlite, 6];
      version = describe({
        'music.db': [..._sqlite, 4],
        'tag.db': [..._sqlite, 6],
      });
      expect(await sync.syncNow(), isFalse);
      expect(sync.lastError, contains('music.db nie zgadza się'));
      expect(await localBytes(sync, 'music.db'), _sqlite);
      expect(await localBytes(sync, 'tag.db'), [..._sqlite, 7]);
      final leftovers = (await sync.databaseDirectory()).listSync().where(
        (e) => e.path.endsWith('.part'),
      );
      expect(leftovers, isEmpty);
    });

    test('a file briefly missing keeps the old copy', () async {
      final sync = newSync();
      await sync.load();
      expect(await sync.syncNow(), isTrue);

      released['music.db'] = [..._sqlite, 5];
      released.remove('tag.db');
      version = describe({...released, 'tag.db': _sqlite});
      expect(await sync.syncNow(), isFalse);
      expect(sync.lastError, startsWith('GitHub: brak pliku tag.db'));
      expect(await localBytes(sync, 'music.db'), _sqlite);
    });

    test('another format keeps the copy; unknown keys are ignored', () async {
      final sync = newSync();
      await sync.load();
      version = {...describe(released), 'format': 2};
      expect(await sync.syncNow(), isFalse);
      expect(sync.lastError, contains('nieznany format'));
      expect(await (await sync.localFile('music.db')).exists(), isFalse);

      version = {...describe(released), 'mirror': 'somewhere'};
      expect(await sync.syncNow(), isTrue);
    });

    test('a file that is not a database is refused', () async {
      released['tag.db'] = '<html>nope</html>'.codeUnits;
      version = describe(released);
      final sync = newSync();
      await sync.load();
      expect(await sync.syncNow(), isFalse);
      expect(sync.lastError, 'GitHub: tag.db nie jest bazą SQLite');
      expect(await (await sync.localFile('music.db')).exists(), isFalse);
    });

    test('a reachable server comes first', () async {
      final sync = newSync();
      await sync.load();
      await sync.setRemoteUrl('127.0.0.1:${server.port}');
      expect(await sync.syncNow(), isTrue);
      expect(sync.lastSource, DatabaseSource.remote);
      expect(gitHubRequests, isEmpty);
    });

    test('GitHub when the server is down, keeping files.db', () async {
      final sync = newSync();
      await sync.load();
      await sync.setRemoteUrl('127.0.0.1:${server.port}');
      expect(await sync.syncNow(), isTrue);

      await server.close(force: true);
      expect(await sync.syncNow(), isTrue);
      expect(sync.lastSource, DatabaseSource.github);
      expect(await localBytes(sync, 'tag.db'), released['tag.db']);
      expect(
        await (await sync.localFile('files.db')).exists(),
        isTrue,
        reason: 'files.db only comes from a server and still fits its files',
      );
    });

    test('both failing report both', () async {
      final sync = newSync();
      await sync.load();
      final port = server.port;
      await server.close(force: true);
      await sync.setRemoteUrl('127.0.0.1:$port');
      version = {'format': 2};
      expect(await sync.syncNow(), isFalse);
      expect(
        sync.lastError,
        'Nie można połączyć się z serwerem · GitHub: nieznany format bazy — '
        'zostaje obecna kopia (zaktualizuj aplikację)',
      );
    });

    test(
      'switched off, nothing comes from GitHub — and it stays off',
      () async {
        final sync = newSync();
        await sync.load();
        await sync.setGitHubOn(false);
        expect(sync.hasSource, isFalse);
        await sync.syncIfDue();
        expect(gitHubRequests, isEmpty);

        final again = newSync();
        await again.load();
        expect(again.gitHubOn, isFalse);
      },
    );

    test('another repository is used and remembered', () async {
      final sync = newSync();
      await sync.load();
      await sync.setGitHubRepo('https://github.com/friend/Fork.git');
      expect(sync.gitHubRepo, 'friend/Fork');
      expect(await sync.syncNow(), isFalse, reason: 'the fake knows no fork');
      expect(gitHubRequests, isEmpty);

      final again = newSync();
      await again.load();
      expect(again.gitHubRepo, 'friend/Fork');
      await again.setGitHubRepo('');
      expect(again.gitHubRepo, 'shian1000/LeinaMusicDatabase');
    });

    test('normalizeGitHubRepo', () {
      expect(DatabaseSync.normalizeGitHubRepo(' '), isNull);
      expect(DatabaseSync.normalizeGitHubRepo('a/b'), 'a/b');
      expect(
        DatabaseSync.normalizeGitHubRepo(
          'github.com/shian1000/LeinaMusicDatabase/releases',
        ),
        'shian1000/LeinaMusicDatabase',
      );
      for (final bad in ['nope', 'a/..', '-a/b', 'http://example.com/a/b']) {
        expect(
          () => DatabaseSync.normalizeGitHubRepo(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });

  group('discoverLocalServer', () {
    test('finds the server serving music.db in the phone subnet', () async {
      // Loopback 127.0.0.x behaves like a /24 subnet with the test server on .1.
      final sync = DatabaseSync(
        storageRoot: () async => storage,
        currentWifiIp: () async => '127.0.0.42',
      );
      await sync.load();
      final found = await sync.discoverLocalServer(port: server.port);
      expect(found.toString(), 'http://127.0.0.1:${server.port}/');
    });

    test('takes port and path from the remote address', () async {
      final sync = DatabaseSync(
        storageRoot: () async => storage,
        currentWifiIp: () async => '127.0.0.42',
      );
      await sync.load();
      await sync.setRemoteUrl('100.64.0.1:${server.port}');
      final found = await sync.discoverLocalServer();
      expect(found.toString(), 'http://127.0.0.1:${server.port}/');
    });

    test('ignores servers that do not return an SQLite file', () async {
      served = {'music.db': '<html>not a db</html>'.codeUnits};
      final sync = DatabaseSync(
        storageRoot: () async => storage,
        currentWifiIp: () async => '127.0.0.42',
      );
      await sync.load();
      expect(await sync.discoverLocalServer(port: server.port), isNull);
    });

    test('returns null when the phone is not on Wi-Fi', () async {
      final sync = DatabaseSync(
        storageRoot: () async => storage,
        currentWifiIp: () async => null,
      );
      await sync.load();
      expect(await sync.discoverLocalServer(port: server.port), isNull);
    });
  });
}
