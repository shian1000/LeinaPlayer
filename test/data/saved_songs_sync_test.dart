import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/incoming_links.dart';
import 'package:music_database_app/src/data/later_links.dart';
import 'package:music_database_app/src/data/saved_songs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MusicDatabase's item-by-item endpoints for saved songs and later links as the hand-off
/// describes them (`docs/handoffs/musicdatabase-saved-songs.md`), cut down to what the phone
/// relies on.
class FakeItemServer {
  FakeItemServer(this.collection, this.field);

  final String collection;
  final String field;
  late HttpServer _server;
  final items = <String, Map<String, Object?>>{};
  final requests = <String>[];
  int counter = 0;
  bool supported = true;
  final user = 'tester';

  Uri get address => Uri.parse('http://127.0.0.1:${_server.port}/');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  Map<String, Object?>? live(String uid) =>
      items[uid]?['deleted'] == true ? null : items[uid];

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    requests.add('${request.method} ${request.uri.path}');
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
    if (!supported ||
        parts.length < 3 ||
        parts[0] != 'users' ||
        parts[1] != user ||
        parts[2] != collection) {
      return reply(HttpStatus.notFound);
    }
    final query = request.uri.queryParameters;
    if (request.method == 'GET' && parts.length == 3) {
      final since = int.parse(query['since'] ?? '0');
      return reply(HttpStatus.ok, {
        'revision': counter,
        field: [
          for (final item in items.values)
            if ((item['revision']! as int) > since) item,
        ],
      });
    }
    final uid = parts[3];
    final stored = items[uid];
    int changedAt(Map<String, Object?> item) =>
        (item['updated_at'] ?? item['deleted_at'])! as int;
    if (request.method == 'PUT') {
      final sent = jsonDecode(body) as Map<String, Object?>;
      if (stored != null &&
          sent['base_revision'] != stored['revision'] &&
          (sent['updated_at']! as int) <= changedAt(stored)) {
        return reply(HttpStatus.conflict, stored);
      }
      final saved = {
        ...sent..remove('base_revision'),
        'revision': ++counter,
        'deleted': false,
      };
      items[uid] = saved;
      return reply(HttpStatus.ok, saved);
    }
    if (request.method == 'DELETE') {
      final deletedAt = int.parse(query['deleted_at']!);
      if (stored != null &&
          int.parse(query['base_revision']!) != stored['revision'] &&
          deletedAt <= changedAt(stored)) {
        return reply(HttpStatus.conflict, stored);
      }
      final marker = {
        'uid': uid,
        'revision': ++counter,
        'deleted': true,
        'deleted_at': deletedAt,
      };
      items[uid] = marker;
      return reply(HttpStatus.ok, marker);
    }
    reply(HttpStatus.methodNotAllowed);
  }
}

SearchHit _song(String title) =>
    SearchHit.youTubeOnly(title: title, artistLabel: 'A', videoId: 'v$title');

void main() {
  String? user;
  var clock = DateTime(2026, 10, 20, 12);
  DateTime now() => clock = clock.add(const Duration(seconds: 1));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    user = 'tester';
    clock = DateTime(2026, 10, 20, 12);
  });

  group('saved and liked songs', () {
    late FakeItemServer server;

    setUp(() async {
      server = FakeItemServer('saved-songs', 'songs');
      await server.start();
    });

    tearDown(() => server.close());

    ({SavedSongs saved, LikedSongs liked, SavedSongsSync sync}) phone({
      int Function(int)? currentSongId,
    }) {
      final saved = SavedSongs(now: now, userName: () => user);
      final liked = LikedSongs(now: now, userName: () => user);
      return (
        saved: saved,
        liked: liked,
        sync: SavedSongsSync(
          [saved, liked],
          now: now,
          userName: () => user,
          authToken: () => 'tok',
          currentSongId: currentSongId,
        ),
      );
    }

    test('songs saved before syncing go to the account on the first sync and '
        'come back on a reinstalled phone in their order', () async {
      // Stored by the version before syncing: bare TrackRefs, newest first.
      SharedPreferences.setMockInitialValues({
        'liked_songs': jsonEncode([
          {'title': 'New', 'artist': 'A', 'main_db_id': 5},
          {'title': 'Old', 'artist': 'A', 'video_id': 'vOld'},
        ]),
      });
      final first = phone(currentSongId: (id) => id == 5 ? 7 : id);
      await first.liked.load();
      await first.saved.setAll([_song('Later')], true);
      await first.sync.sync([server.address]);

      expect(first.sync.lastSync!.problem, isNull);
      final stored = server.items.values.toList();
      expect(stored, hasLength(3));
      final newSong = stored.firstWhere(
        (s) => (s['song']! as Map)['title'] == 'New',
      );
      expect(newSong['list'], 'liked');
      // MusicDatabase merged song 5 into 7 since it was liked.
      expect((newSong['song']! as Map)['song_id'], 7);
      expect(
        stored.where((s) => s['list'] == 'later').single['song'],
        containsPair('video_id', 'vLater'),
      );

      SharedPreferences.setMockInitialValues({});
      final reinstalled = phone();
      await reinstalled.sync.sync([server.address]);
      expect(reinstalled.liked.songs.map((s) => s.title), ['New', 'Old']);
      expect(reinstalled.liked.songs.first.mainDbId, 7);
      expect(reinstalled.saved.songs.single.title, 'Later');
      expect(reinstalled.saved.contains(_song('Later')), isTrue);

      // Nothing to send back: only the GET.
      server.requests.clear();
      await reinstalled.sync.sync([server.address]);
      expect(server.requests, ['GET /users/tester/saved-songs']);
    });

    test('the same song liked on two phones is one item', () async {
      final first = phone();
      await first.liked.setAll([_song('X')], true);
      await first.sync.sync([server.address]);
      SharedPreferences.setMockInitialValues({});
      final second = phone();
      await second.liked.setAll([_song('X')], true);
      await second.sync.sync([server.address]);

      expect(server.items, hasLength(1));
      expect(second.liked.songs, hasLength(1));
    });

    test(
      'unliking on one phone removes the song from the other for good',
      () async {
        final first = phone();
        await first.liked.setAll([_song('X'), _song('Y')], true);
        await first.sync.sync([server.address]);
        SharedPreferences.setMockInitialValues({});
        final second = phone();
        await second.sync.sync([server.address]);
        expect(second.liked.songs.map((s) => s.title), ['X', 'Y']);

        await second.liked.setAll([_song('X')], false);
        expect(second.liked.songs.map((s) => s.title), ['Y']);
        await second.sync.sync([server.address]);
        expect(server.live(server.items.keys.first), isNull);

        await first.sync.sync([server.address]);
        expect(first.liked.songs.map((s) => s.title), ['Y']);
        // Not sent back by the phone that still had it.
        await first.sync.sync([server.address]);
        expect(
          server.items.values.where((i) => i['deleted'] == true),
          hasLength(1),
        );

        // Liking it again later brings it back everywhere.
        await first.liked.setAll([_song('X')], true);
        await first.sync.sync([server.address]);
        await second.sync.sync([server.address]);
        expect(second.liked.songs.map((s) => s.title), ['X', 'Y']);
      },
    );

    test('an older change loses to a newer one from another phone', () async {
      final first = phone();
      await first.saved.setAll([_song('X')], true);
      await first.sync.sync([server.address]);
      SharedPreferences.setMockInitialValues({});
      final second = phone();
      await second.sync.sync([server.address]);

      // The first phone removes it, then the second (later) saves it again on top.
      await first.saved.setAll([_song('X')], false);
      await second.saved.setAll([_song('X')], true);
      await second.sync.sync([server.address]);
      await first.sync.sync([server.address]);

      expect(first.saved.songs.map((s) => s.title), ['X']);
      expect(server.live(server.items.keys.single), isNotNull);
    });

    test(
      'logged out: nothing is sent and the account\'s songs are hidden',
      () async {
        final first = phone();
        await first.liked.setAll([_song('Mine')], true);
        await first.sync.sync([server.address]);

        user = null;
        first.liked.accountChanged();
        expect(first.liked.songs, isEmpty);
        await first.liked.setAll([_song('Offline')], true);
        server.requests.clear();
        await first.sync.sync([server.address]);
        expect(server.requests, isEmpty);
        expect(first.liked.songs.map((s) => s.title), ['Offline']);

        // Logging in again: the account's songs are back, the offline one joins them.
        user = 'tester';
        first.liked.accountChanged();
        await first.sync.sync([server.address]);
        expect(first.liked.songs.map((s) => s.title), ['Offline', 'Mine']);
        expect(server.items, hasLength(2));
      },
    );

    test('a server without the endpoint keeps everything waiting', () async {
      server.supported = false;
      final first = phone();
      await first.liked.setAll([_song('X')], true);
      await first.sync.sync([server.address]);

      expect(
        first.sync.lastSync!.problem,
        'Serwer MusicDatabase nie obsługuje jeszcze polubionych i zapisanych '
        'utworów',
      );
      expect(first.liked.songs, hasLength(1));
      expect(first.liked.all.single.sync.dirty, isTrue);

      server.supported = true;
      await first.sync.sync([server.address]);
      expect(server.items, hasLength(1));
    });
  });

  group('links saved for later', () {
    late FakeItemServer server;

    setUp(() async {
      server = FakeItemServer('later-links', 'links');
      await server.start();
    });

    tearDown(() => server.close());

    ({MemoryLaterStore store, LaterLinks links}) phone() {
      final store = MemoryLaterStore();
      return (
        store: store,
        links: LaterLinks.synced(
          store: store,
          now: now,
          userName: () => user,
          authToken: () => 'tok',
        ),
      );
    }

    Future<void> save(MemoryLaterStore store, String url, String from) async {
      store.save(
        url: url,
        service: LinkService.youtube,
        kind: 'Film z YouTube',
        personId: await store.addPerson(from),
        at: now(),
      );
    }

    test('links saved by the sheet go to the account with their sender\'s name '
        'and come to another phone under its own people', () async {
      final first = phone();
      await save(first.store, 'https://youtu.be/aaaaaaaaaaa', 'Ola');
      await first.links.load();
      await first.links.setOpened(first.links.links.single, true);
      await first.links.sync([server.address]);

      expect(first.links.lastSync!.problem, isNull);
      final stored = server.items.values.single;
      expect(stored['url'], 'https://youtu.be/aaaaaaaaaaa');
      expect(stored['person'], 'Ola');
      expect(stored['opened_at'], isNotNull);

      final second = phone();
      await second.store.addPerson('ola');
      await second.links.load();
      await second.links.sync([server.address]);
      final link = second.links.links.single;
      expect(link.id, stored['uid']);
      expect(link.opened, isTrue);
      expect(second.links.people, hasLength(1));
      expect(second.links.personOf(link)!.name, 'ola');
    });

    test('removing a link or its person removes it everywhere', () async {
      final first = phone();
      await save(first.store, 'https://youtu.be/aaaaaaaaaaa', 'Ola');
      await save(first.store, 'https://youtu.be/bbbbbbbbbbb', 'Adam');
      await first.links.load();
      await first.links.sync([server.address]);
      final second = phone();
      await second.links.sync([server.address]);
      expect(second.links.links, hasLength(2));

      await first.links.remove(
        first.links.links.firstWhere((l) => l.url.endsWith('a')),
      );
      await first.links.removePerson(
        first.links.people.singleWhere((p) => p.name == 'Adam'),
      );
      expect(first.links.links, isEmpty);
      await first.links.sync([server.address]);
      expect(server.items.values.every((i) => i['deleted'] == true), isTrue);
      // The markers are gone from the phone once sent.
      expect((await first.store.load()).links, isEmpty);

      await second.links.sync([server.address]);
      expect(second.links.links, isEmpty);
    });

    test(
      'renaming a person sends their links again under the new name',
      () async {
        final first = phone();
        await save(first.store, 'https://youtu.be/aaaaaaaaaaa', 'Ola');
        await first.links.load();
        await first.links.sync([server.address]);

        await first.links.renamePerson(first.links.people.single, 'Aleksandra');
        await first.links.sync([server.address]);
        expect(server.items.values.single['person'], 'Aleksandra');
      },
    );

    test('the same link saved again keeps its id and goes again', () async {
      final first = phone();
      await save(first.store, 'https://youtu.be/aaaaaaaaaaa', 'Ola');
      await first.links.load();
      await first.links.sync([server.address]);
      final id = first.links.links.single.id;

      await save(first.store, 'https://youtu.be/aaaaaaaaaaa', 'Ola');
      await first.links.load();
      expect(first.links.links.single.id, id);
      await first.links.sync([server.address]);
      expect(server.items, hasLength(1));
      expect(server.items[id]!['revision'], 2);
    });

    test(
      'logged out: links stay on the phone, the account\'s are hidden',
      () async {
        final first = phone();
        await save(first.store, 'https://youtu.be/aaaaaaaaaaa', 'Ola');
        await first.links.load();
        await first.links.sync([server.address]);

        user = null;
        first.links.accountChanged();
        expect(first.links.links, isEmpty);
        await save(first.store, 'https://youtu.be/bbbbbbbbbbb', 'Ola');
        await first.links.load();
        server.requests.clear();
        await first.links.sync([server.address]);
        expect(server.requests, isEmpty);
        expect(first.links.links, hasLength(1));

        user = 'tester';
        first.links.accountChanged();
        await first.links.sync([server.address]);
        expect(first.links.links, hasLength(2));
        expect(server.items, hasLength(2));
      },
    );
  });
}
