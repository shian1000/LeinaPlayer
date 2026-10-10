import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_database_app/main.dart';
import 'package:music_database_app/src/screens/database_source_screen.dart';
import 'package:music_database_app/src/screens/playlist_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/widgets/common.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows bottom navigation with all tabs', (tester) async {
    await tester.pumpWidget(const MusicDatabaseApp());

    for (final label in ['Home', 'Wyszukaj', 'Biblioteka', 'Utwórz']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Popularne radio'), findsOneWidget);
    expect(find.text('Premium'), findsNothing);
  });

  testWidgets('dummy leaf reports its menu id', (tester) async {
    await tester.pumpWidget(const MusicDatabaseApp());

    await tester.tap(find.text('Muzyka'));
    await tester.pump();

    expect(find.text('Atrapa: Home › Filtr: Muzyka'), findsOneWidget);
  });

  testWidgets('Utwórz tab opens create sheet', (tester) async {
    await tester.pumpWidget(const MusicDatabaseApp());

    await tester.tap(find.text('Utwórz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blend'));
    await tester.pumpAndSettle();

    expect(find.text('Atrapa: Utwórz › Blend'), findsOneWidget);
  });

  testWidgets('library playlist opens and its track menu is reachable', (
    tester,
  ) async {
    await tester.pumpWidget(const MusicDatabaseApp());

    await tester.tap(find.text('Biblioteka'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Przykładowa playlista A'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Odtwórz playlistę'), findsOneWidget);
    expect(find.text('Biblioteka'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Utwór 2'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(PlaylistScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byTooltip('Menu utworu (⋮)').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dodaj do kolejki'));
    await tester.pumpAndSettle();

    expect(
      find.text('Atrapa: Playlista › Utwór › Menu (⋮) › Dodaj do kolejki'),
      findsOneWidget,
    );
  });

  testWidgets('profile drawer opens settings inside current tab', (
    tester,
  ) async {
    await tester.pumpWidget(const MusicDatabaseApp());

    await tester.tap(find.byType(CircleAvatar).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ustawienia'));
    await tester.pumpAndSettle();

    expect(find.text('Źródła muzyki'), findsOneWidget);
  });

  testWidgets(
    'appearance: themes, dark-mode switch and system mode all apply',
    (tester) async {
      await tester.pumpWidget(const MusicDatabaseApp());

      await tester.tap(find.byType(CircleAvatar).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ustawienia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wygląd'));
      await tester.pumpAndSettle();

      AppPalette activePalette() =>
          Theme.of(tester.element(find.text('Motyw ciemny')))
              .extension<AppPalette>()!;
      expect(activePalette(), same(dummifyTheme.palette));

      await tester.tap(find.text('Motyw ciemny'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lain'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(activePalette(), same(lainTheme.palette));

      await tester.tap(find.text('Przełącz na tryb ciemny'));
      await tester.pumpAndSettle();
      expect(activePalette(), same(dummifyLightTheme.palette));

      SwitchListTile darkModeSwitch() => tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Przełącz na tryb ciemny'),
      );
      await tester.tap(find.text('Systemowe przełączanie trybu ciemnego'));
      await tester.pumpAndSettle();
      expect(darkModeSwitch().onChanged, isNull);
      expect(find.textContaining('Sterowane przez system'), findsOneWidget);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      expect(activePalette(), same(lainTheme.palette));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appearance.dark_theme'), 'Lain');
      expect(prefs.getBool('appearance.dark_mode'), isFalse);
      expect(prefs.getBool('appearance.follow_system'), isTrue);
    },
  );

  testWidgets('Muzyka lokalna shows folders, scan button and counters', (
    tester,
  ) async {
    await tester.pumpWidget(const MusicDatabaseApp());

    await tester.tap(find.byType(CircleAvatar).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ustawienia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Źródła muzyki'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muzyka lokalna'));
    await tester.pumpAndSettle();

    expect(find.text('Nie dodano folderów'), findsOneWidget);
    expect(find.text('Dodaj folder'), findsOneWidget);
    expect(find.text('Skanuj teraz'), findsOneWidget);
    expect(find.text('Utwory zapisane na urządzeniu: 0'), findsOneWidget);
    expect(find.text('Nowe utwory spoza bazy danych: 0'), findsOneWidget);

    // Scanning with no folders explains what to do instead of asking for permissions.
    await tester.tap(find.text('Skanuj teraz'));
    await tester.pump();
    expect(find.text('Najpierw dodaj folder z muzyką.'), findsOneWidget);
  });

  testWidgets('database address is validated and saved under Źródła muzyki', (
    tester,
  ) async {
    await tester.pumpWidget(const MusicDatabaseApp());

    await tester.tap(find.byType(CircleAvatar).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ustawienia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Źródła muzyki'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Baza danych'));
    await tester.pumpAndSettle();

    final settingsList = find
        .descendant(
          of: find.byType(DatabaseSourceScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Nigdy'),
      200,
      scrollable: settingsList,
    );
    expect(find.text('Wi-Fi sieci lokalnej'), findsOneWidget);
    expect(find.text('Nie wybrano'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(DatabaseSourceScreen.remoteFieldKey),
      -200,
      scrollable: settingsList,
    );

    expect(find.text('Adres serwera (połączenie zdalne)'), findsOneWidget);
    expect(find.text('Adres serwera (sieć lokalna)'), findsOneWidget);
    await tester.enterText(
      find.byKey(DatabaseSourceScreen.remoteFieldKey),
      'ftp://serwer/',
    );
    await tester.ensureVisible(find.text('Zapisz'));
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nieprawidłowy adres (np. http://serwer:8000/)'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(DatabaseSourceScreen.remoteFieldKey), '');
    await tester.ensureVisible(find.text('Zapisz'));
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(
      find.text('Usunięto adresy — baza nie będzie pobierana'),
      findsOneWidget,
    );
  });

  testWidgets('profile avatar stays at the same spot on every tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MusicDatabaseApp());
    await tester.pumpAndSettle();

    Rect avatar() =>
        tester.getRect(find.byType(ProfileAvatar).hitTestable().first);
    final onHome = avatar();
    for (final tab in ['Wyszukaj', 'Biblioteka', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(avatar(), onHome, reason: 'avatar moved on $tab');
    }
  });

  testWidgets('filter icon on Wyszukaj chooses the search fields', (
    tester,
  ) async {
    await tester.pumpWidget(const MusicDatabaseApp());
    await tester.tap(find.text('Wyszukaj').last);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
    await tester.tap(find.byTooltip('Filtry wyszukiwania'));
    await tester.pumpAndSettle();
    expect(find.text('Szukaj w'), findsOneWidget);

    bool? ticked(String label) => tester
        .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, label))
        .value;
    expect(ticked('Tytuł'), isTrue);
    expect(ticked('Wykonawca'), isTrue);
    expect(ticked('Album'), isTrue);
    expect(ticked('Rok'), isFalse);

    await tester.tap(find.text('Rok'));
    await tester.pumpAndSettle();
    expect(ticked('Rok'), isTrue);

    await tester.tap(find.text('Przywróć domyślne'));
    await tester.pumpAndSettle();
    expect(ticked('Rok'), isFalse);
  });
}
