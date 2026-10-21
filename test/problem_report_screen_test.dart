import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/error_log.dart';
import 'package:music_database_app/src/screens/error_log_screen.dart';
import 'package:music_database_app/src/screens/problem_report_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'support/waiting.dart';

void main() {
  late Directory dir;
  late ErrorLog log;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('problem_report_test');
    log = ErrorLog(directory: () async => dir)
      ..record('Loading playlists failed: SocketException');
  });

  tearDown(() async => dir.delete(recursive: true));

  Widget app(Widget home) =>
      MaterialApp(theme: buildAppTheme(dummifyTheme), home: home);

  testWidgets('Zgłoś problem shows the report and hands it to "Udostępnij"', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? shared;
    await tester.pumpWidget(
      app(
        ProblemReportScreen(
          log: log,
          packageInfo: () async => PackageInfo(
            appName: 'Leina Radio',
            packageName: 'x',
            version: '1.0.0',
            buildNumber: '72',
          ),
          device: () async => (
            manufacturer: 'HUAWEI',
            model: 'SNE-LX1',
            android: '10 (API 29)',
          ),
          share: (report) async => shared = report,
        ),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          find.textContaining('Telefon: HUAWEI SNE-LX1').evaluate().isNotEmpty,
    );
    expect(
      find.textContaining('Loading playlists failed: SocketException'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Nie pobiera bazy');
    await tester.pump();
    expect(
      find.textContaining('Co się stało:\nNie pobiera bazy'),
      findsOneWidget,
    );

    await tester.tap(find.text('Wyślij'));
    await tester.pump();
    expect(shared, contains('Nie pobiera bazy'));
    expect(shared, contains('Wersja: 1.0.0, kompilacja 72'));
    expect(shared, contains('Loading playlists failed'));
  });

  testWidgets(
    'Dziennik błędów lists the newest first and clears after asking',
    (tester) async {
      log.record('Second problem');
      await tester.pumpWidget(app(ErrorLogScreen(log: log)));
      final first = tester.getTopLeft(find.text('Second problem')).dy;
      final second = tester
          .getTopLeft(find.text('Loading playlists failed: SocketException'))
          .dy;
      expect(first, lessThan(second));

      await tester.tap(find.byTooltip('Wyczyść'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wyczyść'));
      await tester.runAsync(() => waitUntil(() => log.entries.isEmpty));
      await tester.pumpAndSettle();
      expect(find.text('Brak błędów z ostatnich 14 dni'), findsOneWidget);
    },
  );
}
