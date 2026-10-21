import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/screens/data_saver_screen.dart';
import 'package:music_database_app/src/screens/privacy_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app(SourceSettings settings, Widget home) => SourceSettingsScope(
    notifier: settings,
    child: MaterialApp(theme: buildAppTheme(dummifyTheme), home: home),
  );

  test('lyrics are on by default and the switch is remembered', () async {
    final settings = SourceSettings();
    await settings.load();
    expect(settings.lyrics, isTrue);
    await settings.setLyrics(false);

    final again = SourceSettings();
    await again.load();
    expect(again.lyrics, isFalse);
  });

  testWidgets('Oszczędzanie danych switches lyrics off', (tester) async {
    final settings = SourceSettings();
    await tester.runAsync(settings.load);
    await tester.pumpWidget(app(settings, const DataSaverScreen()));

    expect(find.text('Pobieraj teksty piosenek'), findsOneWidget);
    await tester.tap(find.text('Pobieraj teksty piosenek'));
    await tester.pump();
    expect(settings.lyrics, isFalse);
  });

  testWidgets(
    'Prywatność i połączenia names every service and leads to its switch',
    (tester) async {
      // Tall enough for the whole screen, so nothing needs scrolling.
      tester.view.physicalSize = const Size(800, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = SourceSettings();
      await tester.runAsync(settings.load);
      await tester.pumpWidget(app(settings, const PrivacyScreen()));

      for (final title in [
        'Serwer MusicDatabase',
        'GitHub',
        'YouTube',
        'Konto Google',
        'Spotify',
        'Okładki: iTunes, Deezer, miniatury YouTube',
        'LRCLIB: teksty piosenek',
        'Przeglądarka i „Udostępnij”',
        'Kto widzi Twoje dane',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      const lyricsOn = 'Teraz: łączy się z internetem (LRCLIB)';
      expect(find.text(lyricsOn), findsOneWidget);
      final off = find.text('Teraz: nie łączy się');
      final offBefore = off.evaluate().length;
      // Every section says whether it connects now.
      expect(find.textContaining('Teraz: '), findsNWidgets(6));

      await tester.tap(
        find.text('Oszczędzanie danych › Pobieraj teksty piosenek'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DataSaverScreen), findsOneWidget);

      await tester.tap(find.text('Pobieraj teksty piosenek'));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(lyricsOn), findsNothing);
      expect(off, findsNWidgets(offBefore + 1));
      final red = tester.widget<Text>(off.first).style!.color;
      expect(red, Theme.of(tester.element(off.first)).colorScheme.error);
    },
  );
}
