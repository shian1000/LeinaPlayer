import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_database_app/main.dart';
import 'package:music_database_app/src/screens/settings_screen.dart';
import 'package:music_database_app/src/screens/about_screen.dart';
import 'package:music_database_app/src/screens/database_source_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/theme_controller.dart';
import 'package:music_database_app/src/widgets/common.dart';

void main() {
  // Lain (the default dark theme) draws section titles differently; these tests read Dummify's.
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'appearance.dark_theme': 'Dummify',
    }),
  );

  /// With the appearance settings already read, as `main()` does before the first frame.
  Future<void> pumpApp(WidgetTester tester) async {
    final themes = ThemeController();
    await themes.load();
    await tester.pumpWidget(MusicDatabaseApp(themeController: themes));
  }

  test('the version shows the build number and commit only when known', () {
    expect(
      versionLabel('1.0.0', '312', 'c11e6c4+zmiany'),
      '1.0.0 (kompilacja 312, c11e6c4+zmiany)',
    );
    expect(versionLabel('1.0.0', '1', ''), '1.0.0 (kompilacja 1)');
    expect(versionLabel('1.0.0', '', ''), '1.0.0');
  });

  test('Lain is the dark theme until the user picks another', () async {
    SharedPreferences.setMockInitialValues({});
    final themes = ThemeController();
    await themes.load();
    expect(themes.dark, same(lainTheme));
  });

  testWidgets('shows bottom navigation with all tabs', (tester) async {
    await pumpApp(tester);

    for (final label in ['Home', 'Odkrywaj', 'Wyszukaj', 'Biblioteka', 'Ja']) {
      expect(find.text(label), findsWidgets);
    }
    for (final filter in ['Wszystko', 'Utwory', 'Playlisty', 'Nastroje']) {
      expect(find.text(filter), findsOneWidget);
    }
    expect(find.text('Podcasty'), findsNothing);
    expect(find.text('Premium'), findsNothing);
  });

  testWidgets('Home with nothing played and no database says so', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Strona główna jest pusta.'), findsOneWidget);

    await tester.tap(find.text('Nastroje'));
    await tester.pump();
    expect(find.textContaining('Atrapa'), findsNothing);
  });

  testWidgets('Biblioteka\'s + opens the create sheet', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Biblioteka'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Utwórz (+)'));
    await tester.pumpAndSettle();
    for (final label in ['Playlista', 'Nastrój', 'Folder']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Blend'), findsNothing);
  });

  testWidgets('empty Biblioteka; "+" › Playlista offers new and import', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Biblioteka'));
    await tester.pumpAndSettle();

    expect(find.text('Brak playlist'), findsOneWidget);
    expect(find.textContaining('Przykładowa'), findsNothing);

    await tester.tap(find.byTooltip('Utwórz (+)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playlista'));
    await tester.pumpAndSettle();
    expect(find.text('Importuj playlistę'), findsOneWidget);
    await tester.tap(find.text('Utwórz nową playlistę'));
    await tester.pumpAndSettle();
    expect(find.text('Nowa playlista'), findsOneWidget);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Utwórz (+)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playlista'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importuj playlistę'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://example.com/nic');
    await tester.tap(find.text('Importuj'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('To nie jest link do playlisty'),
      findsOneWidget,
    );
  });

  testWidgets(
    'predictive back gesture closes a root sheet, not the tab screen under it',
    (tester) async {
      await pumpApp(tester);
      // A pushed tab route (a Biblioteka category) with a root sheet (Utwórz) over it.
      await tester.tap(find.text('Biblioteka'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Albumy'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Utwórz (+)'));
      await tester.pumpAndSettle();
      expect(find.text('Folder'), findsOneWidget);

      Future<void> sendBackGesture(String method, [Object? arguments]) =>
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            SystemChannels.backGesture.name,
            SystemChannels.backGesture.codec.encodeMethodCall(
              MethodCall(method, arguments),
            ),
            (_) {},
          );
      await sendBackGesture('startBackGesture', {
        'touchOffset': [5.0, 300.0],
        'progress': 0.0,
        'swipeEdge': 0,
      });
      await sendBackGesture('commitBackGesture');
      await tester.pumpAndSettle();

      expect(find.text('Folder'), findsNothing);
      expect(find.textContaining('Brak albumów'), findsOneWidget);
    },
  );

  testWidgets('Otwieranie linków: ask each time, or a remembered choice', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Ja'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Ustawienia'), 200);
    await tester.tap(find.text('Ustawienia'));
    await tester.pumpAndSettle();
    await scrollSettingsTo(tester, 'Otwieranie linków');
    await tester.tap(find.text('Otwieranie linków'));
    await tester.pumpAndSettle();

    expect(find.text('Linki z YouTube'), findsOneWidget);
    expect(find.text('Linki ze Spotify'), findsOneWidget);
    expect(find.text('Pytaj za każdym razem'), findsNWidgets(2));
    await tester.tap(find.text('Linki ze Spotify'));
    await tester.pumpAndSettle();
    expect(find.text('Aplikacja Spotify'), findsOneWidget);
    await tester.tap(find.text('Przeglądarka'));
    await tester.pumpAndSettle();
    expect(find.text('Przeglądarka'), findsOneWidget);
    expect(find.text('Pytaj za każdym razem'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Otwieraj linki w Leina Radio'),
      200,
    );
    expect(find.text('Otwieraj linki w Leina Radio'), findsOneWidget);
  });

  testWidgets(
    'Informacje i pomoc: version, private use, licence and source link',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'Leina Radio',
        packageName: 'music_database_app',
        version: '1.2.3',
        buildNumber: '45',
        buildSignature: '',
      );
      await pumpApp(tester);
      await tester.tap(find.text('Ja'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Ustawienia'), 200);
      await tester.tap(find.text('Ustawienia'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Informacje i pomoc'), 200);
      // Clear of the bottom bar, which would take the tap.
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Informacje i pomoc'));
      await tester.pumpAndSettle();

      expect(find.text('1.2.3 (kompilacja 45)'), findsOneWidget);
      expect(find.text('Tylko do użytku prywatnego'), findsOneWidget);
      expect(find.text('Linki z YouTube i Spotify'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('https://github.com/shian1000/MusicDatabaseApp'),
        200,
      );
      expect(find.textContaining('GPLv3'), findsOneWidget);
      expect(
        find.text('https://github.com/shian1000/MusicDatabaseApp'),
        findsOneWidget,
      );
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.ensureVisible(find.byTooltip('Kopiuj link'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Kopiuj link'));
      await tester.pumpAndSettle();
      expect(copied, 'https://github.com/shian1000/MusicDatabaseApp');
      expect(find.text('Skopiowano link do kodu źródłowego'), findsOneWidget);
    },
  );

  testWidgets('Ja opens settings inside its tab', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Ja'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Ustawienia'), 200);
    await tester.tap(find.text('Ustawienia'));
    await tester.pumpAndSettle();

    expect(find.text('MusicDatabase'), findsOneWidget);
    expect(find.text('Serwer'), findsOneWidget);
  });

  testWidgets('Wyszukaj ustawienie finds settings on deeper screens too', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Ja'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Ustawienia'), 200);
    await tester.tap(find.text('Ustawienia'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Wyszukaj ustawienie'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wyczysc okladki');
    await tester.pumpAndSettle();
    expect(find.text('Wyczyść okładki'), findsOneWidget);
    expect(
      find.text(
        'Ustawienia › Dane › Oszczędzanie danych i tryb offline › '
        'Pamięć podręczna',
      ),
      findsOneWidget,
    );

    // A screen named in its parent's description and found as itself is listed once.
    await tester.enterText(find.byType(TextField), 'pamiec podreczna');
    await tester.pumpAndSettle();
    expect(find.text('Pamięć podręczna'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nie ma takiego');
    await tester.pumpAndSettle();
    expect(find.text('Nie ma ustawienia „nie ma takiego”.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'przenikanie');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Przenikanie utworów'));
    await tester.pumpAndSettle();
    expect(find.text('Kolejność odtwarzania'), findsWidgets);
  });

  testWidgets('Biblioteka\'s grid switch is remembered', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Biblioteka'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Widok siatki'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Widok listy'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('library.grid'), isTrue);
  });

  testWidgets(
    'appearance: themes, dark-mode switch and system mode all apply',
    (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Ja'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Ustawienia'), 200);
      await tester.tap(find.text('Ustawienia'));
      await tester.pumpAndSettle();
      await scrollSettingsTo(tester, 'Wygląd');
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

  testWidgets('Muzyka na telefonie shows folders, scan button and counters', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Ja'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Ustawienia'), 200);
    await tester.tap(find.text('Ustawienia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muzyka na telefonie'));
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

  testWidgets('YouTube search settings and playback order', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Ja'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Ustawienia'), 200);
    await tester.tap(find.text('Ustawienia'));
    await tester.pumpAndSettle();
    await scrollSettingsTo(tester, 'YouTube');
    await tester.tap(find.text('YouTube'));
    await tester.pumpAndSettle();

    SwitchListTile switchOf(String label) => tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, label),
    );
    // Methods can only be chosen once YouTube search is on.
    expect(switchOf('Korzystaj z pakietu youtube_explode').onChanged, isNull);
    await tester.tap(find.text('Włącz szukanie w serwisie YouTube'));
    await tester.pumpAndSettle();
    expect(switchOf('Korzystaj z pakietu youtube_explode').value, isTrue);
    await tester.tap(find.text('Korzystaj z API'));
    await tester.pumpAndSettle();
    expect(find.text('Wymaga kodu YouTube API'), findsOneWidget);

    await tester.tap(find.text('Kod YouTube API'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' AIzaSyTEST1234 ');
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(find.text('••••1234'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('youtube.search_enabled'), isTrue);
    expect(prefs.getBool('youtube.method.api'), isTrue);
    expect(prefs.getString('youtube.api_key'), 'AIzaSyTEST1234');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await scrollSettingsTo(tester, 'Odtwarzanie', delta: -200);
    await tester.tap(find.text('Odtwarzanie'));
    await tester.pumpAndSettle();
    expect(find.text('1. Telefon, 2. Serwer, 3. YouTube'), findsOneWidget);
    await tester.tap(find.text('Kolejność odtwarzania'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byIcon(Icons.drag_handle).last,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.text('1. YouTube'), findsOneWidget);
    expect(find.text('2. Telefon'), findsOneWidget);
    expect(find.text('3. Serwer'), findsOneWidget);
    expect(prefs.getStringList('sources.playback_order'), [
      'youtube',
      'phone',
      'server',
    ]);
  });

  testWidgets('database address is validated and saved under Serwer', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Ja'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Ustawienia'), 200);
    await tester.tap(find.text('Ustawienia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Serwer'));
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
      find.text('Adres serwera (połączenie zdalne)'),
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

  testWidgets('tab titles stay at the same spot on every tab', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    await tester.pumpAndSettle();

    Rect header() => tester.getRect(find.byType(TabHeader).hitTestable());
    await tester.tap(find.text('Wyszukaj').last);
    await tester.pumpAndSettle();
    final onSearch = header();
    for (final tab in ['Biblioteka', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(header().top, onSearch.top, reason: 'header moved on $tab');
    }
  });

  testWidgets('filter icon on Wyszukaj chooses the search fields', (
    tester,
  ) async {
    await pumpApp(tester);
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

/// Scrolls Ustawienia's list until [label] is on screen (the list is longer than the test view).
Future<void> scrollSettingsTo(
  WidgetTester tester,
  String label, {
  double delta = 200,
}) => tester.scrollUntilVisible(
  find.text(label),
  delta,
  scrollable: find
      .descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      )
      .first,
);
