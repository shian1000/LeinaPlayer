import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/outbox.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/screens/outbox_settings_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/waiting.dart';

void main() {
  sqfliteFfiInit();

  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  late Directory storage;
  late DatabaseSync sync;
  late Outbox outbox;
  late List<Map<Object?, Object?>> shared;
  // What the share sheet answers: an app's name once shared, '' when closed without sharing.
  late String shareAnswer;

  setUp(() {
    SharedPreferences.setMockInitialValues({'database_sync.github_on': false});
    shared = [];
    shareAnswer = 'com.example.messenger';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
          shared.add(call.arguments as Map<Object?, Object?>);
          return shareAnswer;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
    outbox.dispose();
    sync.dispose();
    await storage.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.runAsync(() async {
      storage = await Directory.systemTemp.createTemp('outbox_package_test');
      sync = DatabaseSync(storageRoot: () async => storage);
      outbox = Outbox(
        storageRoot: () async => storage,
        factoryOverride: databaseFactoryFfi,
      );
      await sync.load();
      await outbox.load();
      await outbox.reportDeadYouTubeLink(
        CatalogSong(id: 1, title: 'Utwór', artistLabel: 'Ktoś'),
        'deadVideo12',
      );
    });
    await tester.pumpWidget(
      DatabaseSyncScope(
        notifier: sync,
        child: OutboxScope(
          notifier: outbox,
          child: MaterialApp(
            theme: buildAppTheme(dummifyTheme),
            home: const OutboxSettingsScreen(),
          ),
        ),
      ),
    );
  }

  testWidgets(
    '"Wyślij paczkę…" asks for a name once, shares a zip and counts it as sent',
    (tester) async {
      await pumpScreen(tester);
      expect(find.text('Zapytam przy pierwszej paczce'), findsOneWidget);
      expect(find.text('Wyeksportuj ponownie ostatnią paczkę'), findsNothing);

      await tester.tap(find.text('Wyślij paczkę…'));
      await tester.pumpAndSettle();
      expect(find.text('Podpis paczek ze zgłoszeniami'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Łucja');
      await tester.tap(find.text('Zapisz'));
      await pumpUntil(
        tester,
        () => find.text('Wyeksportowano 1 zgłoszenie').evaluate().isNotEmpty,
      );

      expect(find.text('Wyeksportowano 1 zgłoszenie'), findsOneWidget);
      expect(shared, hasLength(1));
      expect(
        (shared.single['paths']! as List).single as String,
        endsWith('.zip'),
      );
      expect(outbox.waiting, 0);
      expect(find.text('Nic'), findsOneWidget);
      expect(find.text('lucja'), findsOneWidget);
      expect(find.text('Wyeksportuj ponownie ostatnią paczkę'), findsOneWidget);

      await tester.tap(find.text('Wyeksportuj ponownie ostatnią paczkę'));
      await pumpUntil(tester, () => shared.length == 2);
      expect(shared, hasLength(2));
    },
  );

  testWidgets('closing the share sheet leaves the requests waiting', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.runAsync(() => outbox.setTypedSender('ola'));
    shareAnswer = '';

    await tester.tap(find.text('Wyślij paczkę…'));
    await pumpUntil(
      tester,
      () =>
          shared.isNotEmpty &&
          // Made by the export, emptied again by taking it back.
          Directory('${storage.path}/outbox/sent').existsSync() &&
          Directory('${storage.path}/outbox/sent').listSync().isEmpty &&
          find.text('1 zgłoszenie').evaluate().isNotEmpty &&
          find.text('Wyeksportuj ponownie ostatnią paczkę').evaluate().isEmpty,
    );

    expect(find.text('Podpis paczek ze zgłoszeniami'), findsNothing);
    expect(outbox.waiting, 1);
    expect(find.text('1 zgłoszenie'), findsOneWidget);
    expect(find.text('Wyeksportuj ponownie ostatnią paczkę'), findsNothing);
  });
}
