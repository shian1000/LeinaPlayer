import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/latin_names.dart';
import 'package:music_database_app/src/data/lyrics_transliteration.dart';
import 'package:music_database_app/src/screens/appearance_screen.dart';
import 'package:music_database_app/src/screens/transliteration_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app(
    ThemeController themes, {
    Widget home = const AppearanceScreen(),
  }) => ThemeScope(
    notifier: themes,
    child: MaterialApp(theme: buildAppTheme(dummifyTheme), home: home),
  );

  testWidgets('Wygląd opens everything about transliteration on one screen', (
    tester,
  ) async {
    final themes = ThemeController();
    await tester.pumpWidget(app(themes));

    expect(find.text('Metoda transliteracji'), findsNothing);
    await tester.scrollUntilVisible(find.text('Transliteracja'), 200);
    await tester.pump();
    await tester.tap(find.text('Transliteracja'));
    await tester.pumpAndSettle();
    expect(find.text('Nazwy w alfabecie łacińskim'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Języki wyłączone z transliteracji'),
      200,
    );
    expect(find.text('Metoda transliteracji'), findsOneWidget);
  });

  testWidgets('languages are left out of transliteration', (tester) async {
    final themes = ThemeController();
    await tester.pumpWidget(app(themes, home: const TransliterationScreen()));

    await tester.scrollUntilVisible(
      find.text('Języki wyłączone z transliteracji'),
      200,
    );
    await tester.pump();
    await tester.tap(find.text('Języki wyłączone z transliteracji'));
    await tester.pumpAndSettle();
    expect(find.text('Arabic'), findsOneWidget);
    expect(find.text('Polish'), findsNothing);

    await tester.tap(find.text('Arabic'));
    await tester.pump();
    expect(themes.excludedLanguages, {'Arabic'});
  });

  testWidgets('Latin names and lyrics transliteration are picked', (
    tester,
  ) async {
    final themes = ThemeController();
    await tester.pumpWidget(app(themes, home: const TransliterationScreen()));

    await tester.scrollUntilVisible(
      find.text('Łacinka zamiast oryginalnego alfabetu'),
      200,
    );
    await tester.pump();
    await tester.tap(find.text('Łacinka zamiast oryginalnego alfabetu'));
    await tester.pump();
    expect(themes.latinNames, LatinNames.instead);

    await tester.scrollUntilVisible(find.text('Na życzenie'), 200);
    await tester.pump();
    await tester.tap(find.text('Na życzenie'));
    await tester.pump();
    expect(themes.lyricsTransliteration, LyricsTransliteration.onRequest);
  });

  testWidgets('a transliteration method not built yet stays unpicked', (
    tester,
  ) async {
    final themes = ThemeController();
    await tester.pumpWidget(app(themes, home: const TransliterationScreen()));

    for (final method in ['Pobierz z serwera', 'Przelicz na miejscu']) {
      await tester.scrollUntilVisible(find.text(method), 200);
      await tester.pump();
      await tester.tap(find.text(method));
      await tester.pump();
      expect(find.text('Work in progress :)'), findsOneWidget);
      expect(themes.transliterationMethod, TransliterationMethod.none);
    }
  });
}
