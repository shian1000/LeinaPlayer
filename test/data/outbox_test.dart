import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/outbox.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/song_requests.dart';
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
    'found links go into files of their own, each video of a song once',
    () async {
      final outbox = newOutbox();
      final noLink = CatalogSong(
        id: 7,
        title: 'Obsession',
        artistLabel: 'Elise Trouw',
      );
      const video = YouTubeVideo(
        id: 'foundVideo1',
        title: 'Elise Trouw - Obsession',
        channel: 'Elise Trouw - Topic',
      );
      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
      expect(await outbox.reportFoundYouTubeLink(noLink, video), isTrue);
      expect(await outbox.reportFoundYouTubeLink(noLink, video), isFalse);

      final files = await outbox.pending();
      expect(names(files), [
        '2026-10-12_23-44-05_001.db',
        '2026-10-12_23-44-05_002.db',
      ]);
      final found = await rows(files.last, 'found_youtube_links');
      expect(found.single, containsPair('song_id', 7));
      expect(found.single, containsPair('title', 'Obsession'));
      expect(found.single, containsPair('video_id', 'foundVideo1'));
      expect(
        found.single,
        containsPair('video_channel', 'Elise Trouw - Topic'),
      );
      expect(found.single['found_at'], startsWith('2026-10-12T23:44:05'));
      expect((await outbox.waitingFoundLinks()).single.videoId, 'foundVideo1');

      // Sent: still not reported again; another video of the song is.
      final sent = await Directory('${root.path}/outbox/sent').create();
      await files.last.rename('${sent.path}/${names([files.last]).single}');
      expect(await outbox.reportFoundYouTubeLink(noLink, video), isFalse);
      expect(await outbox.waitingFoundLinks(), isEmpty);
      expect(
        await outbox.reportFoundYouTubeLink(
          noLink,
          const YouTubeVideo(
            id: 'foundVideo2',
            title: 'Obsession',
            channel: '',
          ),
        ),
        isTrue,
      );
      expect(names(await outbox.pending()).last, '2026-10-12_23-44-05_003.db');
    },
  );

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
      user = 'tester';
      await outbox.reportDeadYouTubeLink(losingSleep, 'ad5ukUkNjgw');
      final files = await outbox.pending();
      expect(names(files), [
        '2026-10-12_23-44-05_001.db',
        'tester_2026-10-12_23-44-05_002.db',
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

  group('corrections', () {
    Future<void> correctYear(Outbox outbox, Object? to) => outbox.correctField(
      table: 'songs',
      rowId: 4601,
      column: 'year',
      oldValue: 2019,
      newValue: to,
      song: chromatic,
    );

    test(
      'go into a request of their own, a newer value replacing the older',
      () async {
        final outbox = newOutbox();
        await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
        await correctYear(outbox, 2018);
        now = now.add(const Duration(minutes: 1));
        await correctYear(outbox, 2017);
        await outbox.correctField(
          table: 'artists',
          rowId: 7,
          column: 'origin',
          oldValue: 'USA',
          newValue: null,
          song: chromatic,
        );

        final files = await outbox.pending();
        expect(names(files), [
          '2026-10-12_23-44-05_001.db',
          '2026-10-12_23-44-05_002.db',
        ]);
        // Dead links stay where MusicDatabase already understands them.
        await outbox.reportDeadYouTubeLink(losingSleep, 'ad5ukUkNjgw');
        expect(await outbox.pending(), hasLength(2));
        expect(await rows(files.first, 'dead_youtube_links'), hasLength(2));

        final corrections = await rows(files.last, 'field_corrections');
        expect(corrections, hasLength(2));
        final year = corrections.firstWhere((r) => r['column_name'] == 'year');
        expect(year, containsPair('old_value', 2019));
        expect(year, containsPair('new_value', 2017));
        expect(year, containsPair('title', 'Chromatic'));
        expect(year['corrected_at'], startsWith('2026-10-12T23:45:05'));
        final origin = corrections.firstWhere(
          (r) => r['column_name'] == 'origin',
        );
        expect(origin['new_value'], isNull);

        expect(
          outbox.correctionOf('songs', 4601, 'year', 2019)?.newValue,
          2017,
        );
        expect(outbox.waitingCorrections, hasLength(2));
        // A downloaded music.db with another value settles it.
        expect(outbox.correctionOf('songs', 4601, 'year', 2017), isNull);
      },
    );

    test(
      'set back to the old value, a correction is dropped with its request',
      () async {
        final outbox = newOutbox();
        await correctYear(outbox, 2018);
        expect(await outbox.pending(), hasLength(1));
        await correctYear(outbox, 2019);
        expect(await outbox.pending(), isEmpty);
        expect(outbox.correctionOf('songs', 4601, 'year', 2019), isNull);
        expect(outbox.waitingCorrections, isEmpty);
      },
    );

    test('a sent one is still known, until music.db changes', () async {
      final outbox = newOutbox();
      await correctYear(outbox, 2018);
      final sent = await Directory('${root.path}/outbox/sent').create();
      final file = (await outbox.pending()).single;
      await file.rename('${sent.path}/${file.path.split('/').last}');

      final reloaded = newOutbox();
      await reloaded.load();
      final correction = reloaded.correctionOf('songs', 4601, 'year', 2019);
      expect(correction?.sent, isTrue);
      expect(correction?.newValue, 2018);
      expect(reloaded.waitingCorrections, isEmpty);

      await correctYear(reloaded, 2016);
      expect(names(await reloaded.pending()), ['2026-10-12_23-44-05_002.db']);
      expect(reloaded.correctionOf('songs', 4601, 'year', 2019)?.sent, isFalse);
    });

    test(
      'a sent one set back to the old value is taken back with a newer one',
      () async {
        final outbox = newOutbox();
        await correctYear(outbox, 2018);
        final sent = await Directory('${root.path}/outbox/sent').create();
        final file = (await outbox.pending()).single;
        await file.rename('${sent.path}/${file.path.split('/').last}');
        await outbox.load();

        await correctYear(outbox, 2019);
        final waiting = (await outbox.pending()).single;
        final row = (await rows(waiting, 'field_corrections')).single;
        expect(row, containsPair('old_value', 2019));
        expect(row, containsPair('new_value', 2019));
        expect(
          outbox.correctionOf('songs', 4601, 'year', 2019)?.newValue,
          2019,
        );

        // Corrected again before that is sent: the newer value replaces it.
        await correctYear(outbox, 2017);
        expect(await outbox.pending(), hasLength(1));
        // And set back once more: the waiting one goes, and the sent one is taken back again.
        await correctYear(outbox, 2019);
        expect(
          (await rows(
            (await outbox.pending()).single,
            'field_corrections',
          )).single['new_value'],
          2019,
        );
      },
    );
    test(
      'songs.artist_id: corrected with a name, taken back with the old name',
      () async {
        Future<void> propose(Outbox outbox, String name) => outbox.correctField(
          table: 'songs',
          rowId: 4601,
          column: 'artist_id',
          oldValue: 7,
          newValue: name,
          oldAsValue: 'Elise Trouw',
          song: chromatic,
        );
        final outbox = newOutbox();
        await propose(outbox, 'Lola Young');
        final file = (await outbox.pending()).single;
        final row = (await rows(file, 'field_corrections')).single;
        expect(row, containsPair('old_value', 7));
        expect(row, containsPair('new_value', 'Lola Young'));

        final sent = await Directory('${root.path}/outbox/sent').create();
        await file.rename('${sent.path}/${file.path.split('/').last}');
        await outbox.load();
        await propose(outbox, 'Elise Trouw');
        final back = (await rows(
          (await outbox.pending()).single,
          'field_corrections',
        )).single;
        expect(back, containsPair('old_value', 7));
        expect(back, containsPair('new_value', 'Elise Trouw'));
        // Already taken back: the same again sends nothing more.
        await propose(outbox, 'Elise Trouw');
        expect(await outbox.pending(), hasLength(1));
      },
    );
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
        user = 'tester';
        token = 'tok-123';
        now = now.add(const Duration(minutes: 1));
        await outbox.reportDeadYouTubeLink(losingSleep, 'ad5ukUkNjgw');
        expect(names(await outbox.pending()), [
          'inny_2026-10-12_23-44-05_001.db',
          'tester_2026-10-12_23-45-05_002.db',
        ]);
        answers = [403, 201];
        final result = await outbox.send([base()]);
        expect(result.sent, 1);
        expect(result.problem, contains('innego użytkownika'));
        expect(received.keys, ['tester_2026-10-12_23-45-05_002.db']);
        expect(names(await outbox.pending()), [
          'inny_2026-10-12_23-44-05_001.db',
        ]);
      },
    );
  });

  group('packages', () {
    Map<String, List<int>> unzip(RequestPackage package) => {
      for (final f in ZipDecoder().decodeBytes(package.file.readAsBytesSync()))
        f.name: f.content,
    };

    Future<List<String>> sentNames() async {
      final sent = Directory('${(await newOutbox().directory()).path}/sent');
      return [
        if (sent.existsSync())
          for (final f in sent.listSync()) f.path.split('/').last,
      ]..sort();
    }

    test('cleaning a typed name', () {
      expect(Outbox.cleanSenderName('Łukasz Żółć'), 'lukasz-zolc');
      expect(Outbox.cleanSenderName('  Jan_Kowalski!! '), 'jan_kowalski');
      expect(Outbox.cleanSenderName('Віктор Цой'), 'viktor-tsoy');
      expect(Outbox.cleanSenderName('-Ola'), 'ola');
      expect(Outbox.cleanSenderName('a' * 40), 'a' * 32);
      expect(Outbox.cleanSenderName('Ż'), isNull, reason: 'too short');
      expect(Outbox.cleanSenderName('東京'), isNull);
      expect(Outbox.cleanSenderName(''), isNull);
    });

    test('the waiting requests go into a zip at the top level, signed, and count as sent', () async {
      final outbox = newOutbox();
      await outbox.load();
      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
      await outbox.requestSong(
        const SongRequest(
          title: 'Nowa',
          artist: 'Ktoś',
          source: SongRequestSource.youtube,
        ),
      );
      final waiting = names(await outbox.pending());
      final contents = {
        for (final f in await outbox.pending())
          f.path.split('/').last: f.readAsBytesSync(),
      };
      expect(waiting, hasLength(2));
      expect(outbox.asksForSender, isTrue);

      await outbox.setTypedSender('Łucja Nowak');
      expect(outbox.asksForSender, isFalse);
      expect(outbox.packageSender, 'lucja-nowak');
      final package = (await outbox.exportPackage())!;

      final signed = [for (final n in waiting) 'lucja-nowak_$n'];
      expect(package.names, signed);
      final zipped = unzip(package);
      expect(zipped.keys, signed, reason: 'top level, nothing else');
      for (final n in waiting) {
        expect(zipped['lucja-nowak_$n'], contents[n], reason: 'unchanged');
      }
      expect(package.file.path, endsWith('.zip'));
      expect(await outbox.pending(), isEmpty);
      expect(outbox.waiting, 0);
      expect(await sentNames(), signed..sort());
      expect(outbox.lastPackage, package.names);

      // The next finding starts a new request with the next number; the sent link stays known.
      expect(
        await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY'),
        isFalse,
      );
      await outbox.reportDeadYouTubeLink(losingSleep, 'ad5ukUkNjgw');
      expect(names(await outbox.pending()), ['2026-10-12_23-44-05_003.db']);
    });

    test(
      'a logged-in phone signs with the account; other names stay',
      () async {
        user = 'kasia';
        final outbox = newOutbox();
        await outbox.load();
        await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
        user = null;
        await outbox.reportDeadYouTubeLink(losingSleep, 'ad5ukUkNjgw');
        user = 'basia';
        expect(outbox.asksForSender, isFalse);
        final package = (await outbox.exportPackage())!;
        expect(package.names, [
          'kasia_2026-10-12_23-44-05_001.db',
          'basia_2026-10-12_23-44-05_002.db',
        ]);
      },
    );

    test('a name left empty sends the files unsigned', () async {
      final outbox = newOutbox();
      await outbox.load();
      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
      await outbox.setTypedSender('?');
      expect(outbox.typedSender, '');
      expect(outbox.asksForSender, isFalse);
      final package = (await outbox.exportPackage())!;
      expect(package.names, ['2026-10-12_23-44-05_001.db']);

      final again = newOutbox();
      await again.load();
      expect(again.typedSender, '', reason: 'asked only once');
    });

    test(
      'closing the share sheet puts the requests back as they were',
      () async {
        final outbox = newOutbox();
        await outbox.load();
        await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
        await outbox.setTypedSender('ola');
        final package = (await outbox.exportPackage())!;
        await outbox.undoExport(package);
        expect(names(await outbox.pending()), ['2026-10-12_23-44-05_001.db']);
        expect(outbox.waiting, 1);
        expect(await sentNames(), isEmpty);
        expect(outbox.lastPackage, isEmpty);
      },
    );

    test('the last package can be exported again from sent/', () async {
      final outbox = newOutbox();
      await outbox.load();
      expect(await outbox.exportPackage(), isNull, reason: 'nothing waiting');
      expect(await outbox.rebuildLastPackage(), isNull);

      await outbox.reportDeadYouTubeLink(chromatic, '49JVQEOkNmY');
      await outbox.setTypedSender('ola');
      final first = (await outbox.exportPackage())!;
      final firstBytes = unzip(first);

      final reloaded = newOutbox();
      await reloaded.load();
      final again = (await reloaded.rebuildLastPackage())!;
      expect(again.names, first.names);
      expect(unzip(again), firstBytes);
      expect(await reloaded.pending(), isEmpty, reason: 'nothing moves');
    });

    test('the limits: a file too big is put aside, the rest waits for the next package', () async {
      final outbox = newOutbox();
      await outbox.load();
      final dir = await outbox.directory();
      for (var n = 1; n <= Outbox.maxPackageFiles + 2; n++) {
        File(
          '${dir.path}/2026-10-12_23-44-05_${n.toString().padLeft(3, '0')}.db',
        ).writeAsBytesSync([n % 256]);
      }
      File('${dir.path}/2026-10-12_23-44-05_${Outbox.maxPackageFiles + 3}.db')
          .writeAsBytesSync(List.filled(Outbox.maxPackageFileBytes + 1, 0));
      await outbox.setTypedSender('');
      final package = (await outbox.exportPackage())!;
      expect(package.names, hasLength(Outbox.maxPackageFiles));
      expect(package.leftOut, 2);
      expect(package.refused, 1);
      expect(outbox.waiting, 2);
      expect(
        File(
          '${dir.path}/rejected/2026-10-12_23-44-05_${Outbox.maxPackageFiles + 3}.db',
        ).existsSync(),
        isTrue,
      );
    });
  });
}
