import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/widgets/song_info.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/fixtures.dart';
import '../support/waiting.dart';

void main() {
  sqfliteFfiInit();

  Widget app(Widget child, {DatabaseSync? sync}) {
    final page = MaterialApp(
      theme: buildAppTheme(dummifyTheme),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
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
}
