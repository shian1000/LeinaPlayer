import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/library_folders.dart';
import 'package:music_database_app/src/data/playlist_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MusicDatabase's folder endpoints as the hand-off describes them
/// (`docs/handoffs/musicdatabase-folders.md`), cut down to what the phone relies on.
class FakeFolderServer {
  late HttpServer _server;
  final folders = <String, Map<String, Object?>>{};
  int counter = 0;
  bool supportsFolders = true;
  final user = 'tester';

  Uri get address => Uri.parse('http://127.0.0.1:${_server.port}/');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

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
    final parts = request.uri.pathSegments;
    if (!supportsFolders ||
        parts.length < 3 ||
        parts[0] != 'users' ||
        parts[1] != user ||
        parts[2] != 'folders') {
      return reply(HttpStatus.notFound);
    }
    final query = request.uri.queryParameters;
    if (request.method == 'GET' && parts.length == 3) {
      final since = int.parse(query['since'] ?? '0');
      return reply(HttpStatus.ok, {
        'revision': counter,
        'folders': [
          for (final f in folders.values)
            if ((f['revision']! as int) > since) f,
        ],
      });
    }
    final uid = parts[3];
    final stored = folders[uid];
    if (request.method == 'PUT') {
      final sent = jsonDecode(body) as Map<String, Object?>;
      if (stored != null &&
          sent['base_revision'] != stored['revision'] &&
          (sent['updated_at']! as int) <= (stored['updated_at']! as int)) {
        return reply(HttpStatus.conflict, stored);
      }
      final saved = {
        ...sent..remove('base_revision'),
        'revision': ++counter,
        'deleted': false,
      };
      folders[uid] = saved;
      return reply(HttpStatus.ok, saved);
    }
    if (request.method == 'DELETE') {
      final marker = {'uid': uid, 'revision': ++counter, 'deleted': true};
      folders[uid] = marker;
      return reply(HttpStatus.ok, marker);
    }
    reply(HttpStatus.methodNotAllowed);
  }
}

PlaylistSummary _playlist(int id, String uid) => PlaylistSummary(
  id: id,
  uid: uid,
  name: 'Playlista $id',
  owner: null,
  trackCount: 0,
  duration: Duration.zero,
  updatedAt: DateTime(2026, 10, 16),
);

void main() {
  late FakeFolderServer server;
  String? user;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = FakeFolderServer();
    await server.start();
    user = 'tester';
  });

  tearDown(() => server.close());

  LibraryFolders phone() =>
      LibraryFolders(userName: () => user, authToken: () => 'tok');

  /// Another phone of the account: its own `shared_preferences`.
  Future<LibraryFolders> otherPhone() async {
    SharedPreferences.setMockInitialValues({});
    final folders = phone();
    await folders.load();
    return folders;
  }

  test('a folder goes to MusicDatabase with its playlists by uid and comes to '
      'another phone under that phone\'s own ids', () async {
    final first = phone();
    await first.load();
    await first.updateItems(
      playlists: [_playlist(1, 'uid-a'), _playlist(2, 'uid-b')],
      moods: const [],
    );
    final folder = await first.create(' Do auta ');
    await first.move(LibraryFolders.playlistKey(1), folder.id);
    await first.sync([server.address]);

    expect(first.lastSync!.problem, isNull);
    final stored = server.folders[folder.id]!;
    expect(stored['name'], 'Do auta');
    expect(stored['items'], [
      {'type': 'playlist', 'uid': 'uid-a'},
    ]);
    expect(first.folders.single.dirty, isFalse);

    final second = await otherPhone();
    await second.updateItems(
      playlists: [_playlist(7, 'uid-a')],
      moods: const [],
    );
    await second.sync([server.address]);
    expect(second.folders.single.name, 'Do auta');
    expect(second.folders.single.items, [LibraryFolders.playlistKey(7)]);
  });

  test('an item the phone has not got yet waits and shows once it turns up; it '
      'is sent back meanwhile', () async {
    final first = phone();
    await first.load();
    await first.updateItems(
      playlists: [_playlist(1, 'uid-a'), _playlist(2, 'uid-b')],
      moods: const [],
    );
    final folder = await first.create('Mieszane');
    await first.move(LibraryFolders.playlistKey(1), folder.id);
    await first.move(LibraryFolders.playlistKey(2), folder.id);
    await first.sync([server.address]);

    final second = await otherPhone();
    await second.updateItems(
      playlists: [_playlist(5, 'uid-a')],
      moods: const [],
    );
    await second.sync([server.address]);
    expect(second.folders.single.items, [LibraryFolders.playlistKey(5)]);

    // Renamed here before uid-b arrived: uid-b still goes back with it.
    await second.rename(folder.id, 'Mieszane 2');
    await second.sync([server.address]);
    expect(server.folders[folder.id]!['items'], [
      {'type': 'playlist', 'uid': 'uid-a'},
      {'type': 'playlist', 'uid': 'uid-b'},
    ]);

    await second.updateItems(
      playlists: [_playlist(5, 'uid-a'), _playlist(6, 'uid-b')],
      moods: const [],
    );
    expect(second.folders.single.items, [
      LibraryFolders.playlistKey(5),
      LibraryFolders.playlistKey(6),
    ]);
  });

  test('deleting a folder deletes it on the other phones too', () async {
    final first = phone();
    await first.load();
    final folder = await first.create('Stare');
    await first.sync([server.address]);
    final second = await otherPhone();
    await second.sync([server.address]);
    expect(second.folders, hasLength(1));

    await second.delete(folder.id);
    expect(second.folders, isEmpty);
    await second.sync([server.address]);
    expect(server.folders[folder.id]!['deleted'], isTrue);

    await first.sync([server.address]);
    expect(first.folders, isEmpty);
  });

  test('logged out, the account\'s folders are hidden and new ones stay on the '
      'phone until added to the account', () async {
    final folders = phone();
    await folders.load();
    await folders.create('Konto');
    await folders.sync([server.address]);

    user = null;
    expect(folders.folders, isEmpty);
    await folders.create('Tylko tu');
    expect(folders.folders.single.account, isNull);

    user = 'tester';
    expect([for (final f in folders.folders) f.name], ['Konto', 'Tylko tu']);
    expect(folders.phoneOnlyCount, 1);
    await folders.addPhoneOnlyToAccount();
    await folders.sync([server.address]);
    expect(server.folders, hasLength(2));
    expect(folders.phoneOnlyCount, 0);
  });

  test('a server without folders leaves them waiting', () async {
    server.supportsFolders = false;
    final folders = phone();
    await folders.load();
    await folders.create('Czeka');
    await folders.sync([server.address]);

    expect(
      folders.lastSync!.problem,
      'Serwer MusicDatabase nie obsługuje jeszcze folderów',
    );
    expect(folders.folders.single.dirty, isTrue);

    final reloaded = phone();
    await reloaded.load();
    expect(reloaded.folders.single.dirty, isTrue);
  });
}
