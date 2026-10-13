import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/outbox.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/youtube_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DateTime now;
  String? user;
  String? token;

  Outbox newOutbox() => Outbox(
    storageRoot: () async => root,
    factoryOverride: databaseFactoryFfi,
    now: () => now,
    userName: () => user,
    authToken: () => token,
  );

  final chromatic = CatalogSong(
    id: 4601,
    title: 'Chromatic',
    artistLabel: 'Elise Trouw',
    youtubeVideoId: '49JVQEOkNmY',
  );
  final losingSleep = CatalogSong(
    id: 4602,
    title: 'Losing Sleep',
    artistLabel: 'Elise Trouw',
    youtubeVideoId: 'ad5ukUkNjgw',
  );

  Future<List<Map<String, Object?>>> rows(File file, String table) async {
    final db = await databaseFactoryFfi.openDatabase(file.path);
    try {
      return await db.query(
        table,
        orderBy: table == 'request' ? null : 'song_id',
      );
    } finally {
      await db.close();
    }
  }

  List<String> names(List<File> files) => [
    for (final f in files) f.path.split('/').last,
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('outbox_test');
    now = DateTime(2026, 10, 12, 23, 44, 5);
    user = null;
    token = null;
  });

  tearDown(() => root.delete(recursive: true));

  test('dead links and their replacements go into one request, named by date, time and number', () async {
    final outbox = newOutbox();
    expect(await outbox.pending(), isEmpty);

    expect(
      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY'),
      isTrue,
    );
    now = now.add(const Duration(minutes: 3));
    await outbox.reportReplacement(
      chromatic,
      '49JVQEOkNmY',
      const YouTubeVideo(
        id: 'newChromati',
        title: 'Chromatic',
        channel: 'Elise Trouw',
      ),
    );
    await outbox.reportDeadYouTubeLink(losingSleep, 'ad5ukUkNjgw');

    final files = await outbox.pending();
    expect(names(files), ['2026-10-12_23-44-05_001.db']);
    final request = (await rows(files.single, 'request')).single;
    expect(request['format'], Outbox.format);
    expect(request['user_name'], isNull);
    expect(request['created_at'], startsWith('2026-10-12T23:44:05'));
    final links = await rows(files.single, 'dead_youtube_links');
    expect(links, hasLength(2));
    expect(links.first, containsPair('dead_video_id', '49JVQEOkNmY'));
    expect(links.first, containsPair('replacement_video_id', 'newChromati'));
    expect(links.first, containsPair('replacement_channel', 'Elise Trouw'));
    expect(links.last, containsPair('title', 'Losing Sleep'));
    expect(links.last['replacement_video_id'], isNull);
  });

  test(
    'waiting reports list the songs of unsent requests only, oldest first',
    () async {
      final outbox = newOutbox();
      expect(await outbox.waitingReports(), isEmpty);

      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
      final sent = await Directory('${root.path}/outbox/sent').create();
      final first = (await outbox.pending()).single;
      await first.rename('${sent.path}/${first.path.split('/').last}');

      now = now.add(const Duration(minutes: 1));
      await outbox.reportDeadYouTubeLink(losingSleep, 'ad5ukUkNjgw');
      now = now.add(const Duration(minutes: 1));
      await outbox.reportDeadYouTubeLink(chromatic, 'anotherDead');
      await outbox.reportReplacement(
        chromatic,
        'anotherDead',
        const YouTubeVideo(
          id: 'newChromati',
          title: 'Chromatic (Live)',
          channel: 'Elise Trouw',
        ),
      );

      final reports = await outbox.waitingReports();
      expect(
        [for (final r in reports) (r.songId, r.deadVideoId)],
        [(4602, 'ad5ukUkNjgw'), (4601, 'anotherDead')],
      );
      expect(reports.first.replacementTitle, isNull);
      expect(reports.last.title, 'Chromatic');
      expect(reports.last.replacementTitle, 'Chromatic (Live)');
      expect(reports.last.replacementChannel, 'Elise Trouw');
    },
  );

  test('a link already reported, even in a sent request, is not reported again; numbers go on', () async {
    final outbox = newOutbox();
    await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
    expect(
      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY'),
      isFalse,
    );

    // What sending will do later: the request leaves the outbox.
    final sent = await Directory('${root.path}/outbox/sent').create();
    final first = (await outbox.pending()).single;
    await first.rename('${sent.path}/${first.path.split('/').last}');

    expect(
      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY'),
      isFalse,
    );
    expect(await outbox.pending(), isEmpty);

    user = 'Shian K.';
    now = DateTime(2026, 10, 13, 8, 1, 2);
    await outbox.reportDeadYouTubeLink(losingSleep, 'ad5ukUkNjgw');
    expect(names(await outbox.pending()), [
      'Shian-K-_2026-10-13_08-01-02_002.db',
    ]);
  });

  test(
    'logging in starts a new request: an unsigned one takes no more',
    () async {
      final outbox = newOutbox();
      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
      user = 'owner';
      await outbox.reportDeadYouTubeLink(losingSleep, 'ad5ukUkNjgw');
      final files = await outbox.pending();
      expect(names(files), [
        '2026-10-12_23-44-05_001.db',
        'owner_2026-10-12_23-44-05_002.db',
      ]);
      expect(await rows(files.first, 'dead_youtube_links'), hasLength(1));
      expect(await rows(files.last, 'dead_youtube_links'), hasLength(1));
    },
  );

  test('reports made at the same time share one new request', () async {
    final outbox = newOutbox();
    await Future.wait([
      outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY'),
      outbox.reportDeadYouTubeLink(losingSleep, 'ad5ukUkNjgw'),
    ]);
    final files = await outbox.pending();
    expect(files, hasLength(1));
    expect(await rows(files.single, 'dead_youtube_links'), hasLength(2));
  });

  group('sending', () {
    late HttpServer server;
    late Map<String, List<int>> received;
    late List<int> answers;
    late List<String?> authorizations;

    setUp(() async {
      received = {};
      answers = [];
      authorizations = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        final name = request.uri.pathSegments.last;
        authorizations.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        final code = answers.isEmpty ? 201 : answers.removeAt(0);
        if (request.method == 'PUT' &&
            request.uri.pathSegments.first == 'inbox' &&
            request.contentLength == bytes.length) {
          if (code == 201) received[name] = bytes;
          request.response.statusCode = code;
        } else {
          request.response.statusCode = 400;
        }
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Uri base() => Uri.parse('http://127.0.0.1:${server.port}/');

    test(
      'a received request moves to sent/, and the next report starts a new one',
      () async {
        final outbox = newOutbox();
        await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
        final result = await outbox.send([base()]);
        expect(result.sent, 1);
        expect(result.problem, isNull);
        expect(received.keys, ['2026-10-12_23-44-05_001.db']);
        expect(
          String.fromCharCodes(received.values.single.take(15)),
          'SQLite format 3',
        );
        expect(await outbox.pending(), isEmpty);
        expect(outbox.waiting, 0);
        expect(
          File('${root.path}/outbox/sent/2026-10-12_23-44-05_001.db')
              .existsSync(),
          isTrue,
        );

        now = now.add(const Duration(hours: 1));
        await outbox.reportDeadYouTubeLink(losingSleep, 'ad5ukUkNjgw');
        expect(names(await outbox.pending()), ['2026-10-13_00-44-05_002.db']);
      },
    );

    test('an unreachable address is skipped for the next one', () async {
      final outbox = newOutbox();
      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
      // Nothing listens there (a port just freed).
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = closed.port;
      await closed.close();
      final result = await outbox.send([
        Uri.parse('http://127.0.0.1:$deadPort/'),
        base(),
      ]);
      expect(result.sent, 1);
      expect(received, hasLength(1));
    });

    test(
      'a full inbox or no server: the request waits for the next try',
      () async {
        final outbox = newOutbox();
        await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
        answers = [507];
        var result = await outbox.send([base()]);
        expect(result.sent, 0);
        expect(result.problem, contains('pełna'));
        expect(await outbox.pending(), hasLength(1));
        expect(outbox.waiting, 1);

        final gone = base();
        await server.close(force: true);
        result = await outbox.send([gone], manual: true);
        expect(result.problem, contains('Brak połączenia'));
        expect(await outbox.pending(), hasLength(1));
      },
    );

    test('a request the inbox refuses is kept aside, not sent again, and its number not reused', () async {
      final outbox = newOutbox();
      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
      answers = [409];
      final result = await outbox.send([base()]);
      expect(result.refused, 1);
      expect(await outbox.pending(), isEmpty);
      expect(
        File('${root.path}/outbox/rejected/2026-10-12_23-44-05_001.db')
            .existsSync(),
        isTrue,
      );
      // Already reported (in the refused file): not again.
      expect(
        await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY'),
        isFalse,
      );
      await outbox.reportDeadYouTubeLink(losingSleep, 'ad5ukUkNjgw');
      expect(names(await outbox.pending()).single, endsWith('_002.db'));
    });

    test('nothing waiting: no connection is made', () async {
      final outbox = newOutbox();
      final result = await outbox.send([base()]);
      expect(result.sent, 0);
      expect(outbox.lastSend, isNull);
    });

    test('the server refusing (inbox full) holds automatic sending until the next day', () async {
      var outbox = newOutbox();
      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
      answers = [507];
      final refused = await outbox.send([base()]);
      expect(refused.serverRefused, isTrue);
      expect(outbox.heldForToday, isTrue);

      // Later the same day, also after a restart: no automatic attempt.
      now = now.add(const Duration(minutes: 10));
      outbox = newOutbox();
      await outbox.load();
      expect(outbox.heldForToday, isTrue);
      expect((await outbox.send([base()])).sent, 0);
      expect(received, isEmpty);

      // "Wyślij teraz" tries anyway (still full here).
      answers = [507];
      expect((await outbox.send([base()], manual: true)).serverRefused, isTrue);

      // The next day (the next daily download) it goes by itself, and the hold is gone.
      now = DateTime(2026, 10, 13, 9);
      expect(outbox.heldForToday, isFalse);
      expect((await outbox.send([base()])).sent, 1);
      outbox = newOutbox();
      await outbox.load();
      expect(outbox.heldForToday, isFalse);
    });

    test('no connection does not hold sending back', () async {
      final outbox = newOutbox();
      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
      final gone = base();
      await server.close(force: true);
      final result = await outbox.send([gone]);
      expect(result.problem, isNotNull);
      expect(result.serverRefused, isFalse);
      expect(outbox.heldForToday, isFalse);
    });

    test(
      'automatic sending switched off: only "Wyślij teraz" sends; remembered',
      () async {
        var outbox = newOutbox();
        await outbox.load();
        expect(outbox.autoSend, isTrue);
        await outbox.setAutoSend(false);
        await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
        expect((await outbox.send([base()])).sent, 0);
        expect(received, isEmpty);

        outbox = newOutbox();
        await outbox.load();
        expect(outbox.autoSend, isFalse);
        expect(outbox.waiting, 1);
        expect((await outbox.send([base()], manual: true)).sent, 1);
      },
    );

    test(
      'logged in: the file is named after the user and sent with the token',
      () async {
        user = 'shian_man';
        token = 'tok-123';
        final outbox = newOutbox();
        await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
        expect((await outbox.send([base()])).sent, 1);
        expect(received.keys, ['shian_man_2026-10-12_23-44-05_001.db']);
        expect(authorizations, ['Bearer tok-123']);
      },
    );

    test('the server rejecting the token: kept, and the user is asked to log in again', () async {
      token = 'revoked';
      final outbox = newOutbox();
      var rejected = 0;
      outbox.onUnauthorized = () => rejected++;
      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
      answers = [401];
      final result = await outbox.send([base()]);
      expect(result.problem, contains('zaloguj się ponownie'));
      expect(rejected, 1);
      expect(await outbox.pending(), hasLength(1));
      expect(outbox.heldForToday, isFalse);
    });

    test(
      'a request named after another user waits; the rest still go',
      () async {
        final outbox = newOutbox();
        user = 'inny';
        await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
        user = 'owner';
        token = 'tok-123';
        now = now.add(const Duration(minutes: 1));
        await outbox.reportDeadYouTubeLink(losingSleep, 'ad5ukUkNjgw');
        expect(names(await outbox.pending()), [
          'inny_2026-10-12_23-44-05_001.db',
          'owner_2026-10-12_23-45-05_002.db',
        ]);
        answers = [403, 201];
        final result = await outbox.send([base()]);
        expect(result.sent, 1);
        expect(result.problem, contains('innego użytkownika'));
        expect(received.keys, ['owner_2026-10-12_23-45-05_002.db']);
        expect(names(await outbox.pending()), [
          'inny_2026-10-12_23-44-05_001.db',
        ]);
      },
    );
  });
}
