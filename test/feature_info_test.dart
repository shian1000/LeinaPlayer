import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/screens/privacy_screen.dart';
import 'package:music_database_app/src/screens/settings_screen.dart';
import 'package:music_database_app/src/screens/spotify_source_screen.dart';
import 'package:music_database_app/src/screens/youtube_playback_screen.dart';
import 'package:music_database_app/src/screens/youtube_source_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SourceSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SourceSettings();
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(settings.load);
    await tester.pumpWidget(
      SourceSettingsScope(
        notifier: settings,
        child: YouTubeScope(
          search: YouTubeSearch(),
          audio: YouTubeAudio(newPipeAvailable: true),
          playlists: YouTubePlaylists(newPipeAvailable: false),
          child: MaterialApp(theme: buildAppTheme(dummifyTheme), home: screen),
        ),
      ),
    );
  }

  Future<void> longPress(WidgetTester tester, String text) async {
    await tester.longPress(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('Ustawienia › Serwer explains itself and leads to privacy', (
    tester,
  ) async {
    await show(tester, const SettingsScreen());
    await longPress(tester, 'Serwer');

    expect(find.text('Serwer MusicDatabase'), findsOneWidget);
    for (final section in [
      'Co to jest',
      'Do czego służy',
      'Jak działa',
      'Z czego korzysta',
      'Z czym się łączy',
    ]) {
      expect(find.text(section), findsOneWidget);
    }

    await tester.tap(find.text('Prywatność i połączenia').last);
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyScreen), findsOneWidget);
  });

  testWidgets('Zgłoszenia poprawek explains itself', (tester) async {
    await show(tester, const SettingsScreen());
    await longPress(tester, 'Zgłoszenia poprawek');
    expect(find.text('Jak działa'), findsOneWidget);
    expect(find.textContaining('Wyślij paczkę'), findsOneWidget);
  });

  testWidgets('YouTube search methods explain themselves; the API is marked '
      'as not tried yet', (tester) async {
    await show(tester, const YouTubeSourceScreen());
    await longPress(tester, YouTubeMethod.newPipe.label);
    expect(find.text('NewPipeExtractor (wyszukiwanie)'), findsOneWidget);
    expect(find.textContaining('W budowie'), findsNothing);
    Navigator.of(tester.element(find.text('Jak działa'))).pop();
    await tester.pumpAndSettle();

    await longPress(tester, YouTubeMethod.api.label);
    expect(find.text('YouTube Data API'), findsWidgets);
    expect(find.textContaining('W budowie'), findsOneWidget);
  });

  testWidgets('YouTube playback methods explain NewPipe and youtube_explode', (
    tester,
  ) async {
    await show(tester, const YouTubePlaybackScreen());
    await longPress(tester, YouTubePlaybackMethod.newPipe.label);
    expect(find.text('NewPipeExtractor (odtwarzanie)'), findsOneWidget);
    Navigator.of(tester.element(find.text('Jak działa'))).pop();
    await tester.pumpAndSettle();

    await longPress(tester, YouTubePlaybackMethod.explode.label);
    expect(find.text('youtube_explode (odtwarzanie)'), findsOneWidget);
  });

  testWidgets('Spotify API is marked as not tried yet', (tester) async {
    await show(tester, const SpotifySourceScreen());
    await longPress(tester, 'Spotify API');
    expect(find.textContaining('W budowie'), findsOneWidget);
    expect(find.text('Z czym się łączy'), findsOneWidget);
  });
}
