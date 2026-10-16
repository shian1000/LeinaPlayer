import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/server_downloads.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary local;
  late HttpServer server;
  final audio = List.generate(5000, (i) => i % 256);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('server_downloads_test');
    sync = DatabaseSync(storageRoot: () async => root);
    catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    local = LocalLibrary(
      catalog,
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/library/7') {
        request.response.add(audio);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    local.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  ServerDownloads newDownloads() =>
      ServerDownloads(local.database, storageRoot: () async => root);

  Uri at(String path) =>
      Uri.parse('http://${server.address.address}:${server.port}$path');

  test('a library file is saved, kept across restarts and removed', () async {
    final downloads = newDownloads();
    await downloads.load();
    const file = ServerFile(id: 7, path: 'Artist/Album/01 Song.flac');

    // An address that doesn't answer first, then one that does.
    expect(
      await downloads.download(file, [
        Uri.parse('http://127.0.0.1:1/library/7'),
        at('/library/7'),
      ]),
      isTrue,
    );
    expect(downloads.isDownloaded(7), isTrue);
    final copy = await downloads.fileFor(7);
    expect(copy!.path, endsWith('/downloads/7.flac'));
    expect(await copy.readAsBytes(), audio);
    expect(downloads.totalBytes, audio.length);

    final again = newDownloads();
    await again.load();
    expect(again.isDownloaded(7), isTrue);

    await again.remove(7);
    expect(again.isDownloaded(7), isFalse);
    expect(await copy.exists(), isFalse);
  });

  test('a file the server hasn\'t got leaves nothing behind', () async {
    final downloads = newDownloads();
    await downloads.load();
    const file = ServerFile(id: 8, path: 'x.mp3');
    expect(await downloads.download(file, [at('/library/8')]), isFalse);
    expect(downloads.entries, isEmpty);
    expect(await Directory('${root.path}/downloads').list().toList(), isEmpty);
  });
}
