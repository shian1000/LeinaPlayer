import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/playlist_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_playlist.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/screens/library_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/fixtures.dart';

void main() {
  sqfliteFfiInit();

  late Directory storage;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary library;
  late YouTubeLibrary youTubeLibrary;
  late PlaylistLibrary playlists;
  late SourceSettings settings;
  late PlayerController player;
  late List<String> fetched;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fetched = [];
  });

  tearDown(() async {
    player.dispose();
    playlists.dispose();
    youTubeLibrary.dispose();
    library.dispose();
    catalog.dispose();
    sync.dispose();
    settings.dispose();
    await storage.delete(recursive: true);
  });

  /// Lets real SQLite work finish; spinners shown meanwhile never settle, so only pump.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.runAsync(() async {
      storage = await Directory.systemTemp.createTemp('playlist_screen_test');
      sync = DatabaseSync(storageRoot: () async => storage);
      catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
      library = LocalLibrary(
        catalog,
        storageRoot: () async => storage,
        factoryOverride: databaseFactoryFfi,
      );
      youTubeLibrary = YouTubeLibrary(
        library.database,
        storageRoot: () async => storage,
      );
      playlists = PlaylistLibrary(library.database, catalog, youTubeLibrary);
      settings = SourceSettings();
      player = PlayerController();
      await writeMusicDb((await sync.localFile('music.db')).path);
      await catalog.ensureLoaded();
      await library.load();
      await youTubeLibrary.load();
      await playlists.load();
      await settings.load();
    });
    await tester.pumpWidget(
      DatabaseSyncScope(
        notifier: sync,
        child: SongCatalogScope(
          notifier: catalog,
          child: LocalLibraryScope(
            notifier: library,
            child: YouTubeLibraryScope(
              notifier: youTubeLibrary,
              child: PlaylistLibraryScope(
                notifier: playlists,
                child: PlayerScope(
                  notifier: player,
                  child: SourceSettingsScope(
                    notifier: settings,
                    child: YouTubeScope(
                      search: YouTubeSearch(),
                      audio: YouTubeAudio(newPipeAvailable: false),
                      playlists: YouTubePlaylists(
                        newPipeAvailable: false,
                        explode: (id) async {
                          fetched.add(id);
                          return YouTubePlaylistData(
                            id: id,
                            name: 'Do auta',
                            owner: 'Shian',
                            videos: const [
                              YouTubeVideo(
                                id: 'X2XWBcd5jn0',
                                title: 'Dawid Podsiadło - Małomiasteczkowy',
                                channel: 'Dawid Podsiadło',
                                duration: Duration(minutes: 4),
                              ),
                              YouTubeVideo(
                                id: 'nn',
                                title: 'Nieznany - Utwór (Official Video)',
                                channel: 'Nieznany',
                                duration: Duration(minutes: 3),
                              ),
                            ],
                          );
                        },
                      ),
                      child: MaterialApp(
                        theme: buildAppTheme(dummifyTheme),
                        home: const Scaffold(body: LibraryScreen()),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('import a YouTube playlist and open it from Biblioteka', (
    tester,
  ) async {
    await pumpLibrary(tester);
    expect(find.text('Brak playlist'), findsOneWidget);

    await tester.tap(find.byTooltip('Utwórz (+)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playlista'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importuj playlistę'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://www.youtube.com/playlist?list=PLtest',
    );
    await tester.tap(find.text('Importuj'));
    await settle(tester);

    expect(fetched, ['PLtest']);
    expect(
      find.text('Zaimportowano „Do auta”: 2 utw., w bazie danych 1.'),
      findsOneWidget,
    );
    expect(find.text('Do auta'), findsOneWidget);
    expect(find.text('Playlista • Shian'), findsOneWidget);

    await tester.tap(find.text('Do auta'));
    await settle(tester);
    expect(find.text('2 utwory • 7 min'), findsOneWidget);
    expect(find.text('Małomiasteczkowy'), findsOneWidget);
    expect(find.text('Utwór'), findsOneWidget);
    // Like the reference app: just the artist under the title, and a ⋮ per track.
    expect(find.text('Dawid Podsiadło'), findsWidgets);
    expect(find.textContaining('•  Małomiasteczkowy'), findsNothing);
    expect(find.byTooltip('Menu utworu (⋮)'), findsNWidgets(2));
    // Recognised track: in the database and on YouTube; the other one only on YouTube.
    expect(find.byTooltip('W bazie danych'), findsOneWidget);
    expect(find.byTooltip('Na YouTube'), findsOneWidget);
    expect(
      find.byTooltip('Na YouTube (znalezione przez telefon)'),
      findsOneWidget,
    );
  });
}
