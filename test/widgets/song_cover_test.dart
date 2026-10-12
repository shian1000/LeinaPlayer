import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/album_covers.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/theme_controller.dart';
import 'package:music_database_app/src/widgets/cover_art.dart';
import 'package:music_database_app/src/widgets/song_cover.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/waiting.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary local;
  late SourceSettings settings;
  late ThemeController themes;
  late AlbumCovers covers;

  final cover = CoverRequest(
    artist: 'Lain',
    title: 'Duvet',
    filePath: '/m/duvet.mp3',
    seed: 'duvet',
  );

  Future<void> setUpAll(WidgetTester tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('song_cover_test');
      sync = DatabaseSync(storageRoot: () async => root);
      catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      local = LocalLibrary(
        catalog,
        storageRoot: () async => root,
        factoryOverride: databaseFactoryFfi,
      );
      settings = SourceSettings();
      await settings.load();
      themes = ThemeController();
      await themes.setCoverFilter(CoverFilter.lain);
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 40, 40),
        ui.Paint()..color = const ui.Color(0xFF3060A0),
      );
      final image = await recorder.endRecording().toImage(40, 40);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      covers = AlbumCovers(
        local.database,
        settings,
        storageRoot: () async => root,
        readEmbedded: (path) async => path == cover.filePath ? png : null,
        getJson: (_) async => throw const SocketException('offline'),
        getBytes: (_) async => throw const SocketException('offline'),
      );
    });
  }

  tearDown(() async {
    covers.dispose();
    themes.dispose();
    settings.dispose();
    local.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  Widget app(Widget child) => MaterialApp(
    theme: buildAppTheme(dummifyTheme),
    home: ThemeScope(
      notifier: themes,
      child: AlbumCoversScope(
        notifier: covers,
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );

  /// Real decoding and the filter's isolate need real time.
  Future<void> waitForCover(WidgetTester tester) async {
    await pumpUntil(tester, () => find.byType(CoverArt).evaluate().isEmpty);
    expect(find.byType(CoverArt), findsNothing);
  }

  testWidgets(
    'a filtered cover never falls back to the placeholder once shown',
    (tester) async {
      await setUpAll(tester);
      var rebuilds = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$rebuilds'),
                  SongCover(cover: cover),
                ],
              );
            },
          ),
        ),
      );
      await waitForCover(tester);

      // Like play/pause on a playlist: every row is built again.
      rebuild(() => rebuilds++);
      await tester.pump();
      expect(find.byType(CoverArt), findsNothing);

      // A cover built anew (e.g. the player opened again) shows it in its first frame.
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpWidget(app(SongCover(cover: cover)));
      expect(find.byType(CoverArt), findsNothing);
    },
  );
}
