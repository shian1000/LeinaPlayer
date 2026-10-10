import 'dart:io';

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

  DatabaseSync newSync() => DatabaseSync(
    storageRoot: () async => storage,
    now: () => now,
    currentWifi: () async => wifi,
  );

  Future<String> localContent(DatabaseSync sync, String name) async =>
      String.fromCharCodes(await (await sync.localFile(name)).readAsBytes());

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await Directory.systemTemp.createTemp('database_sync_test');
    now = DateTime(2026, 10, 10, 9);
    served = {'music.db': _sqlite, 'tag.db': _sqlite};
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
  });

  tearDown(() async {
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
