import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/account.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/screens/account_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/waiting.dart';

void main() {
  testWidgets('Konto: a wrong password says so, then logging in and out', (
    tester,
  ) async {
    // testWidgets answers every request with HTTP 400; this test talks to a real local server.
    final mocked = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = mocked);
    final server = (await tester.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    ))!;
    addTearDown(() => tester.runAsync(() => server.close(force: true)));
    var loggedOut = false;
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      if (request.uri.path == '/login' && request.contentLength < 0) {
        // Like MusicDatabase's server: no chunked bodies.
        request.response.statusCode = HttpStatus.lengthRequired;
      } else if (request.uri.path == '/login') {
        final login = jsonDecode(body) as Map<String, Object?>;
        if (login['password'] == 'tajne1') {
          request.response.write(
            jsonEncode({'username': 'owner', 'token': 'tok'}),
          );
        } else {
          request.response.statusCode = HttpStatus.unauthorized;
        }
      } else {
        loggedOut = request.uri.path == '/logout';
        request.response.statusCode = HttpStatus.noContent;
      }
      await request.response.close();
    });
    SharedPreferences.setMockInitialValues({
      'database_sync.url': 'http://127.0.0.1:${server.port}/',
    });
    final sync = DatabaseSync();
    final account = Account();
    await tester.runAsync(() async {
      await sync.load();
      await account.load();
    });

    await tester.pumpWidget(
      DatabaseSyncScope(
        notifier: sync,
        child: AccountScope(
          notifier: account,
          child: MaterialApp(
            theme: buildAppTheme(dummifyTheme),
            home: const AccountScreen(),
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(AccountScreen.userFieldKey), 'owner');
    await tester.enterText(find.byKey(AccountScreen.passwordFieldKey), 'zle');
    await tester.tap(find.text('Zaloguj'));
    await pumpUntil(
      tester,
      () => find.textContaining('Nieprawidłowa').evaluate().isNotEmpty,
    );
    expect(find.textContaining('Nieprawidłowa'), findsOneWidget);
    expect(account.loggedIn, isFalse);

    await tester.enterText(
      find.byKey(AccountScreen.passwordFieldKey),
      'tajne1',
    );
    await tester.tap(find.text('Zaloguj'));
    await pumpUntil(tester, () => account.loggedIn);
    await tester.pump();
    expect(find.text('owner'), findsOneWidget);
    expect(find.text('Zalogowano'), findsOneWidget);

    await tester.tap(find.text('Wyloguj'));
    await tester.pumpAndSettle();
    expect(find.text('Wylogować?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Wyloguj'));
    await pumpUntil(tester, () => loggedOut);
    // The revoke request's timeout timer runs on the test clock; let it run out.
    await tester.pump(Account.timeout);
    await tester.pumpAndSettle();
    expect(account.loggedIn, isFalse);
    expect(find.text('Zaloguj się do MusicDatabase'), findsOneWidget);
  });
}
