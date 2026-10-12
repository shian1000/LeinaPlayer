import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_database_app/main.dart';
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

  test('Lain is the dark theme until the user picks another', () async {
    SharedPreferences.setMockInitialValues({});
    final themes = ThemeController();
    await themes.load();
    expect(themes.dark, same(lainTheme));
  });

  testWidgets('shows bottom navigation with all tabs', (tester) async {
    await pumpApp(tester);

    for (final label in ['Home', 'Wyszukaj', 'Biblioteka', 'Utwórz']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Popularne radio'), findsOneWidget);
    expect(find.text('Premium'), findsNothing);
  });

  testWidgets('dummy leaf reports its menu id', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Muzyka'));
    await tester.pump();

    expect(find.text('Atrapa: Home › Filtr: Muzyka'), findsOneWidget);
  });

  testWidgets('Utwórz tab opens create sheet', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Utwórz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blend'));
    await tester.pumpAndSettle();

    expect(find.text('Atrapa: Utwórz › Blend'), findsOneWidget);
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
    expect(
      find.text(
        'Atrapa: Biblioteka › Utwórz (+) › Playlista › Utwórz nową playlistę',
      ),
      findsOneWidget,
    );

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
      // A pushed tab route (Ustawienia) with a root sheet (Utwórz) over it.
      await tester.tap(find.byType(CircleAvatar).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ustawienia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Utwórz'));
      await tester.pumpAndSettle();
      expect(find.text('Blend'), findsOneWidget);

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

      expect(find.text('Blend'), findsNothing);
      expect(find.text('Źródła muzyki'), findsOneWidget);
    },
  );

  testWidgets('Otwieranie linków: ask each time, or a remembered choice', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byType(CircleAvatar).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ustawienia'));
    await tester.pumpAndSettle();
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

  testWidgets('Informacje i pomoc: private use, licence and source link', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byType(CircleAvatar).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ustawienia'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Informacje i pomoc'), 200);
    // Clear of the bottom bar, which would take the tap.
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Informacje i pomoc'));
    await tester.pumpAndSettle();

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
  });

  testWidgets('profile drawer opens settings inside current tab', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byType(CircleAvatar).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ustawienia'));
    await tester.pumpAndSettle();

    expect(find.text('Źródła muzyki'), findsOneWidget);
  });

  testWidgets(
    'appearance: themes, dark-mode switch and system mode all apply',
    (tester) async {
      await pumpApp(tester);

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
    await pumpApp(tester);

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

  testWidgets('YouTube settings and playback order under Źródła muzyki', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byType(CircleAvatar).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ustawienia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Źródła muzyki'));
    await tester.pumpAndSettle();
    expect(find.text('1. Telefon, 2. YouTube'), findsOneWidget);
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
    await tester.tap(find.text('Kolejność odtwarzania'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byIcon(Icons.drag_handle).first,
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();
    expect(find.text('1. YouTube'), findsOneWidget);
    expect(find.text('2. Telefon'), findsOneWidget);
    expect(prefs.getStringList('sources.playback_order'), ['youtube', 'phone']);
  });

  testWidgets('database address is validated and saved under Źródła muzyki', (
    tester,
  ) async {
    await pumpApp(tester);

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
    await pumpApp(tester);
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
