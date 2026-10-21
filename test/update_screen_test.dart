import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/app_updates.dart';
import 'package:music_database_app/src/screens/about_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/widgets/update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/waiting.dart';

void main() {
  late HttpServer gitHub;

  setUp(() async {
    // testWidgets answers every HttpClient request with 400; these talk to a local server.
    final mocked = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = mocked);
    SharedPreferences.setMockInitialValues({});
    gitHub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    gitHub.listen((request) {
      request.response.write(
        jsonEncode({
          'tag_name': '1.0.0+58',
          'html_url': 'https://github.com/owner/repo/releases/tag/1.0.0+58',
          'body': 'Nowy ekran prywatności',
          'assets': [
            {
              'name': 'LeinaRadio-1.0.0+58.apk',
              'browser_download_url': 'https://example.com/LeinaRadio.apk',
            },
          ],
        }),
      );
      request.response.close();
    });
  });

  tearDown(() async {
    await gitHub.close(force: true);
  });

  AppUpdates newUpdates({String repo = 'owner/repo'}) => AppUpdates(
    repo: repo,
    installedBuild: () async => 57,
    apiBase: Uri.parse('http://127.0.0.1:${gitHub.port}/'),
  );

  Widget app(AppUpdates updates, Widget home) => AppUpdatesScope(
    notifier: updates,
    child: MaterialApp(theme: buildAppTheme(dummifyTheme), home: home),
  );

  Future<PackageInfo> packageInfo() async => PackageInfo(
    appName: 'Leina Radio',
    packageName: 'x',
    version: '1.0.0',
    buildNumber: '57',
  );

  testWidgets('Informacje i pomoc shows a newer release and offers it', (
    tester,
  ) async {
    final updates = newUpdates();
    await tester.runAsync(() async {
      await updates.load();
      await updates.check();
    });
    await tester.pumpWidget(
      app(updates, AboutScreen(packageInfo: packageInfo)),
    );
    await tester.pump();

    expect(find.text('Aktualizacje'), findsOneWidget);
    expect(
      find.text('Dostępna wersja 1.0.0 (58) — stuknij, żeby pobrać'),
      findsOneWidget,
    );
    expect(find.text('Sprawdzaj aktualizacje automatycznie'), findsOneWidget);

    await tester.tap(find.text('Aktualizacje'));
    await tester.pumpAndSettle();
    expect(find.text('Dostępna nowa wersja 1.0.0 (58)'), findsOneWidget);
    expect(find.text('Nowy ekran prywatności'), findsOneWidget);

    await tester.tap(find.text('Później'));
    await tester.pumpAndSettle();
    expect(updates.shouldOffer, isFalse);
    // Still shown here after "Później".
    expect(
      find.text('Dostępna wersja 1.0.0 (58) — stuknij, żeby pobrać'),
      findsOneWidget,
    );
  });

  testWidgets('a build without a repository shows nothing about updates', (
    tester,
  ) async {
    final updates = newUpdates(repo: '');
    await tester.pumpWidget(
      app(updates, AboutScreen(packageInfo: packageInfo)),
    );
    await tester.pump();
    expect(find.text('Aktualizacje'), findsNothing);
    expect(find.text('Sprawdzaj aktualizacje automatycznie'), findsNothing);
  });

  testWidgets('the dialog closed by Back asks again next time', (tester) async {
    final updates = newUpdates();
    await tester.runAsync(() async {
      await updates.load();
      await updates.check();
    });
    await tester.pumpWidget(
      app(
        updates,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showUpdateDialog(context, updates, updates.available!),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await pumpUntil(tester, () => find.text('Pobierz').evaluate().isNotEmpty);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Pobierz'), findsNothing);
    expect(updates.shouldOffer, isTrue);
  });
}
