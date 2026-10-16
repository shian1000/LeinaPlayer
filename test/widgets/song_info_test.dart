import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/outbox.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/widgets/song_info.dart';
import 'package:music_database_app/src/widgets/song_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';
import '../support/waiting.dart';

void main() {
  sqfliteFfiInit();

  Widget app(Widget child, {DatabaseSync? sync, Outbox? outbox}) {
    Widget page = MaterialApp(
      theme: buildAppTheme(dummifyTheme),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
    if (outbox != null) page = OutboxScope(notifier: outbox, child: page);
    return sync == null ? page : DatabaseSyncScope(notifier: sync, child: page);
  }

  testWidgets('a phone-only song: not in MusicDatabase, its file', (
    tester,
  ) async {
    final hit = SearchHit.phoneOnly(
      LocalSong(
        id: 1,
        filePath: '/music/a.mp3',
        title: 'A',
        artist: 'B',
        pending: true,
      ),
    );
    await tester.pumpWidget(app(SongInfoCard(hit: hit)));
    expect(find.text('Tego utworu nie ma w MusicDatabase.'), findsOneWidget);
    expect(find.text('/music/a.mp3'), findsOneWidget);
    expect(find.text('A · B'), findsOneWidget);
  });

  testWidgets('the song menu shows the same card in a sheet', (tester) async {
    final hit = SearchHit.phoneOnly(
      LocalSong(
        id: 1,
        filePath: '/music/a.mp3',
        title: 'A',
        artist: 'B',
        pending: true,
      ),
    );
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSongMenu(context, hit, idPrefix: 'Test'),
            child: const Text('⋮'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('⋮'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Wyświetl informacje o utworze'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Wyświetl informacje o utworze'));
    await tester.pumpAndSettle();

    expect(find.byType(SongInfoCard), findsOneWidget);
    expect(find.text('Tego utworu nie ma w MusicDatabase.'), findsOneWidget);
    expect(find.text('/music/a.mp3'), findsOneWidget);
  });

  testWidgets('a MusicDatabase song: its row, artists, links and tags', (
    tester,
  ) async {
    databaseFactory = databaseFactoryFfi;
    late Directory root;
    late DatabaseSync sync;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('song_info_test');
      sync = DatabaseSync(storageRoot: () async => root);
      await writeMusicDb((await sync.localFile('music.db')).path);
      await writeTagDb(
        (await sync.localFile('tag.db')).path,
        tags: {
          1: ('spellchecked', 'marker', [3]),
        },
      );
    });
    final hit = SearchHit.main(
      CatalogSong(
        id: 3,
        title: 'Pay Your Respect',
        artistLabel: 'Afina feat. CJ Pitts',
        youtubeVideoId: 'N/A',
      ),
      const [],
    );
    await tester.pumpWidget(app(SongInfoCard(hit: hit), sync: sync));
    await pumpUntil(tester, () => find.text('CJ Pitts').evaluate().isNotEmpty);

    expect(find.text('Gościnnie (feat.)'), findsOneWidget);
    expect(find.text('USA - Ohio'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(
      find.text('oznaczony jako niedostępny na YouTube (N/A)'),
      findsOneWidget,
    );
    expect(find.text('spellchecked'), findsOneWidget);

    sync.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });

  testWidgets('a field corrected: sent to the outbox, music.db value kept', (
    tester,
  ) async {
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    late Directory root;
    late DatabaseSync sync;
    late Outbox outbox;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('song_info_test');
      sync = DatabaseSync(storageRoot: () async => root);
      await writeMusicDb((await sync.localFile('music.db')).path);
      outbox = Outbox(
        storageRoot: () async => root,
        factoryOverride: databaseFactoryFfi,
      );
    });
    final hit = SearchHit.main(
      CatalogSong(id: 3, title: 'Pay Your Respect', artistLabel: 'Afina'),
      const [],
    );
    await tester.pumpWidget(
      app(
        SongInfoCard(hit: hit),
        sync: sync,
        outbox: outbox,
      ),
    );
    await pumpUntil(tester, () => find.text('Rok').evaluate().isNotEmpty);

    // No year in music.db: shown empty, so it can be filled in.
    final yearRow = find.ancestor(
      of: find.text('Rok'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(
        of: yearRow.first,
        matching: find.byIcon(Icons.edit_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2015');
    await tester.tap(find.text('Zapisz'));
    await pumpUntil(
      tester,
      () => find.text('Poprawka czeka na wysłanie: 2015').evaluate().isNotEmpty,
    );
    expect(find.text('—'), findsWidgets);

    final corrections = await tester.runAsync(
      () async => outbox.waitingCorrections,
    );
    expect(corrections!.single.table, 'songs');
    expect(corrections.single.column, 'year');
    expect(corrections.single.oldValue, isNull);
    expect(corrections.single.newValue, 2015);
    expect(await tester.runAsync(outbox.pending), hasLength(1));

    sync.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });

  testWidgets('another artist for the song: a songs.artist_id correction '
      'with the name, the same name again takes it back', (tester) async {
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    late Directory root;
    late DatabaseSync sync;
    late Outbox outbox;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('song_info_test');
      sync = DatabaseSync(storageRoot: () async => root);
      await writeMusicDb((await sync.localFile('music.db')).path);
      outbox = Outbox(
        storageRoot: () async => root,
        factoryOverride: databaseFactoryFfi,
      );
    });
    final hit = SearchHit.main(
      CatalogSong(id: 3, title: 'Pay Your Respect', artistLabel: 'Afina'),
      const [],
    );
    await tester.pumpWidget(
      app(
        SongInfoCard(hit: hit),
        sync: sync,
        outbox: outbox,
      ),
    );
    await pumpUntil(tester, () => find.text('Afina').evaluate().isNotEmpty);

    Future<void> propose(String name) async {
      final row = find.ancestor(
        of: find.text('Afina'),
        matching: find.byType(Row),
      );
      await tester.tap(
        find.descendant(
          of: row.first,
          matching: find.byIcon(Icons.edit_outlined),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ten utwór ma innego wykonawcę'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), name);
      await tester.tap(find.text('Zapisz'));
    }

    await propose('Lola Young');
    await pumpUntil(
      tester,
      () => find
          .text('Poprawka czeka na wysłanie: inny wykonawca — Lola Young')
          .evaluate()
          .isNotEmpty,
    );
    final corrections = await tester.runAsync(
      () async => outbox.waitingCorrections,
    );
    expect(corrections!.single.table, 'songs');
    expect(corrections.single.rowId, 3);
    expect(corrections.single.column, 'artist_id');
    expect(corrections.single.oldValue, 3);
    expect(corrections.single.newValue, 'Lola Young');

    // The song's own artist, spelt differently, is no other artist.
    await propose('AFINA');
    await pumpUntil(
      tester,
      () => find.textContaining('inny wykonawca').evaluate().isEmpty,
    );
    expect(await tester.runAsync(outbox.pending), isEmpty);

    sync.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });

  testWidgets(
    'a YouTube link set by hand: a correction the phone uses at once',
    (tester) async {
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({});
      late Directory root;
      late DatabaseSync sync;
      late Outbox outbox;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('song_info_test');
        sync = DatabaseSync(storageRoot: () async => root);
        await writeMusicDb((await sync.localFile('music.db')).path);
        outbox = Outbox(
          storageRoot: () async => root,
          factoryOverride: databaseFactoryFfi,
        );
      });
      final hit = SearchHit.main(
        CatalogSong(id: 3, title: 'Pay Your Respect', artistLabel: 'Afina'),
        const [],
      );
      await tester.pumpWidget(
        app(
          SongInfoCard(hit: hit),
          sync: sync,
          outbox: outbox,
        ),
      );
      await pumpUntil(
        tester,
        () => find.text('Teledysk (music.db)').evaluate().isNotEmpty,
      );

      Future<void> edit(String label, String text) async {
        final row = find.ancestor(
          of: find.text(label),
          matching: find.byType(Row),
        );
        await tester.ensureVisible(row.first);
        await tester.tap(
          find.descendant(
            of: row.first,
            matching: find.byIcon(Icons.edit_outlined),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), text);
        await tester.tap(find.text('Zapisz'));
        await tester.pump();
      }

      await edit('Teledysk (music.db)', 'not a link');
      await tester.pump();
      expect(
        find.text('To nie jest link do filmu na YouTube.'),
        findsOneWidget,
      );

      await edit('Teledysk (music.db)', 'https://youtu.be/dQw4w9WgXcQ?si=abc');
      await pumpUntil(
        tester,
        () => find
            .text('Poprawka czeka na wysłanie, telefon już używa: dQw4w9WgXcQ')
            .evaluate()
            .isNotEmpty,
      );
      final corrections = await tester.runAsync(
        () async => outbox.waitingCorrections,
      );
      expect(corrections!.single.column, 'music_video_youtube_id');
      expect(corrections.single.oldValue, isNull);
      expect(corrections.single.newValue, 'dQw4w9WgXcQ');

      sync.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );

  test('a YouTube link typed by hand: a link, a bare id, empty or N/A', () {
    expect(parseYouTubeLinkInput(' dQw4w9WgXcQ '), 'dQw4w9WgXcQ');
    expect(
      parseYouTubeLinkInput('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=3'),
      'dQw4w9WgXcQ',
    );
    expect(
      parseYouTubeLinkInput('music.youtube.com/watch?v=dQw4w9WgXcQ'),
      'dQw4w9WgXcQ',
    );
    expect(parseYouTubeLinkInput('youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(parseYouTubeLinkInput(''), '');
    expect(parseYouTubeLinkInput('n/a'), 'N/A');
    expect(parseYouTubeLinkInput('N/A', allowNotOnYouTube: false), isNull);
    expect(
      parseYouTubeLinkInput('https://www.youtube.com/playlist?list=PL1'),
      isNull,
    );
    expect(parseYouTubeLinkInput('hello'), isNull);
  });

  testWidgets('a Latin form can be sent for a name in another alphabet, '
      'even before music.db has the column', (tester) async {
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    late Directory root;
    late DatabaseSync sync;
    late Outbox outbox;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('song_info_test');
      sync = DatabaseSync(storageRoot: () async => root);
      final path = (await sync.localFile('music.db')).path;
      await writeMusicDb(path);
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.rawInsert("INSERT INTO artists (id, name) VALUES (7, 'Кино')");
      await db.rawInsert(
        'INSERT INTO songs (id, title, artist_id) '
        "VALUES (6, 'Группа крови', 7)",
      );
      await db.close();
      outbox = Outbox(
        storageRoot: () async => root,
        factoryOverride: databaseFactoryFfi,
      );
    });
    final hit = SearchHit.main(
      CatalogSong(id: 6, title: 'Группа крови', artistLabel: 'Кино'),
      const [],
    );
    await tester.pumpWidget(
      app(
        SongInfoCard(hit: hit),
        sync: sync,
        outbox: outbox,
      ),
    );
    await pumpUntil(
      tester,
      () => find.text('Tytuł alfabetem łacińskim').evaluate().isNotEmpty,
    );
    expect(find.text('Nazwa alfabetem łacińskim'), findsOneWidget);

    final row = find.ancestor(
      of: find.text('Tytuł alfabetem łacińskim'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(
        of: row.first,
        matching: find.byIcon(Icons.edit_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Gruppa krovi');
    await tester.tap(find.text('Zapisz'));
    await pumpUntil(
      tester,
      () => find
          .text('Poprawka czeka na wysłanie: Gruppa krovi')
          .evaluate()
          .isNotEmpty,
    );
    final corrections = await tester.runAsync(
      () async => outbox.waitingCorrections,
    );
    expect(corrections!.single.table, 'songs');
    expect(corrections.single.column, 'title_latin');
    expect(corrections.single.oldValue, isNull);
    expect(corrections.single.newValue, 'Gruppa krovi');

    sync.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });

  testWidgets('"To jest cały album": a switch sending songs.kind, '
      'switched back the correction is dropped', (tester) async {
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    late Directory root;
    late DatabaseSync sync;
    late Outbox outbox;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('song_info_test');
      sync = DatabaseSync(storageRoot: () async => root);
      final path = (await sync.localFile('music.db')).path;
      await writeMusicDb(path);
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute('ALTER TABLE songs ADD COLUMN kind TEXT');
      await db.close();
      outbox = Outbox(
        storageRoot: () async => root,
        factoryOverride: databaseFactoryFfi,
      );
    });
    final hit = SearchHit.main(
      CatalogSong(id: 3, title: 'Pay Your Respect', artistLabel: 'Afina'),
      const [],
    );
    await tester.pumpWidget(
      app(
        SongInfoCard(hit: hit),
        sync: sync,
        outbox: outbox,
      ),
    );
    await pumpUntil(
      tester,
      () => find.text('To jest cały album').evaluate().isNotEmpty,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await pumpUntil(
      tester,
      () => find.text('Poprawka czeka na wysłanie: tak').evaluate().isNotEmpty,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    final corrections = await tester.runAsync(
      () async => outbox.waitingCorrections,
    );
    expect(corrections!.single.table, 'songs');
    expect(corrections.single.column, 'kind');
    expect(corrections.single.oldValue, isNull);
    expect(corrections.single.newValue, 'full_album');

    await tester.tap(find.byType(Switch));
    await pumpUntil(
      tester,
      () => find.textContaining('Poprawka czeka').evaluate().isEmpty,
    );
    expect(
      await tester.runAsync(() async => outbox.waitingCorrections),
      isEmpty,
    );

    sync.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });

  testWidgets('no Latin form fields for names in Latin letters', (
    tester,
  ) async {
    databaseFactory = databaseFactoryFfi;
    late Directory root;
    late DatabaseSync sync;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('song_info_test');
      sync = DatabaseSync(storageRoot: () async => root);
      await writeMusicDb((await sync.localFile('music.db')).path);
    });
    final hit = SearchHit.main(
      CatalogSong(id: 3, title: 'Pay Your Respect', artistLabel: 'Afina'),
      const [],
    );
    await tester.pumpWidget(app(SongInfoCard(hit: hit), sync: sync));
    await pumpUntil(tester, () => find.text('CJ Pitts').evaluate().isNotEmpty);
    expect(find.text('Tytuł alfabetem łacińskim'), findsNothing);
    expect(find.text('Nazwa alfabetem łacińskim'), findsNothing);

    sync.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });
}
