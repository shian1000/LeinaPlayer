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
}
