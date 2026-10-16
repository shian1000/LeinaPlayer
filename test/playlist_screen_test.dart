import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/library_folders.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/playlist_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_account.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/data/youtube_playlist.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/playback/playback_queue.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/track_player.dart';
import 'package:music_database_app/src/screens/library_screen.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/widgets/playing_bars.dart';
import 'package:music_database_app/src/widgets/song_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/fixtures.dart';
import 'support/waiting.dart';
import 'support/youtube_api_fakes.dart';

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
  late PlaybackQueue queue;
  late LibraryFolders folders;
  late List<String> fetched;
  late FakeYouTubeApi youTubeApi;
  late YouTubeAccount youTubeAccount;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fetched = [];
    youTubeApi = FakeYouTubeApi();
    youTubeAccount = YouTubeAccount(
      auth: FakeGoogleAuth(),
      api: youTubeApi,
      supported: true,
    );
  });

  tearDown(() async {
    queue.dispose();
    youTubeAccount.dispose();
    folders.dispose();
    player.dispose();
    playlists.dispose();
    youTubeLibrary.dispose();
    library.dispose();
    catalog.dispose();
    sync.dispose();
    settings.dispose();
    await storage.delete(recursive: true);
  });

  /// Lets real SQLite work finish, until [until] shows (a fixed wait was too short with the whole
  /// suite running in parallel); spinners never settle, so only pump meanwhile.
  Future<void> settle(WidgetTester tester, {required Finder until}) async {
    await pumpUntil(tester, () => until.evaluate().isNotEmpty);
    await tester.pumpAndSettle();
  }

  /// [before] runs once the libraries are loaded, before Biblioteka is shown.
  Future<void> pumpLibrary(
    WidgetTester tester, {
    Future<void> Function()? before,
  }) async {
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
      folders = LibraryFolders();
      player = PlayerController();
      await writeMusicDb((await sync.localFile('music.db')).path);
      await catalog.ensureLoaded();
      await library.load();
      await youTubeLibrary.load();
      await playlists.load();
      await settings.load();
      await folders.load();
      await before?.call();
    });
    queue = PlaybackQueue(
      prefetchDelay: Duration.zero,
      TrackPlayer(
        player: player,
        settings: settings,
        youTubeLibrary: youTubeLibrary,
        youTubeAudio: YouTubeAudio(newPipeAvailable: false),
        youTubeSearch: YouTubeSearch(),
      ),
    );
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
                  child: PlaybackQueueScope(
                    notifier: queue,
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
                        child: LibraryFoldersScope(
                          notifier: folders,
                          child: YouTubeAccountScope(
                            notifier: youTubeAccount,
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
    await settle(tester, until: find.textContaining('Zaimportowano'));

    expect(fetched, ['PLtest']);
    expect(
      find.text('Zaimportowano „Do auta”: 2 utw., w bazie danych 1.'),
      findsOneWidget,
    );
    expect(find.text('Do auta'), findsOneWidget);
    expect(find.text('Playlista • Shian'), findsOneWidget);

    await tester.tap(find.text('Do auta'));
    await settle(tester, until: find.text('Utwór'));
    expect(find.text('2 utwory • 7 min'), findsOneWidget);
    expect(find.text('Małomiasteczkowy'), findsOneWidget);
    expect(find.text('Utwór'), findsOneWidget);
    // Like the reference app: just the artist under the title, and a ⋮ per track.
    expect(find.text('Dawid Podsiadło'), findsWidgets);
    expect(find.textContaining('•  Małomiasteczkowy'), findsNothing);
    expect(find.byTooltip('Menu utworu (⋮)'), findsNWidgets(2));
    // Both play from YouTube; only the unrecognised one is marked as not in the database.
    expect(find.byTooltip('Spoza bazy danych'), findsOneWidget);
    expect(find.byTooltip('Na YouTube'), findsOneWidget);
    expect(
      find.byTooltip('Na YouTube (znalezione przez telefon)'),
      findsOneWidget,
    );

    // Search within the playlist: by title or artist, accents ignored; Back closes it first.
    await tester.tap(find.byTooltip('Szukaj w playliście'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'malomiast');
    await tester.pumpAndSettle();
    expect(find.text('Małomiasteczkowy'), findsOneWidget);
    expect(find.text('Utwór'), findsNothing);
    await tester.enterText(find.byType(TextField), 'nieznany');
    await tester.pumpAndSettle();
    expect(find.text('Utwór'), findsOneWidget);
    expect(find.text('Małomiasteczkowy'), findsNothing);
    await tester.enterText(find.byType(TextField), 'xyz');
    await tester.pumpAndSettle();
    expect(find.text('Brak wyników dla „xyz”'), findsOneWidget);
    await tester.tap(find.byTooltip('Zamknij wyszukiwanie'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Małomiasteczkowy'), findsOneWidget);
    expect(find.text('Utwór'), findsOneWidget);

    // ⋮ › the tracks MusicDatabase doesn't have: only the unrecognised one.
    await tester.tap(find.byTooltip('Menu playlisty (⋮)'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Wyświetl utwory, których nie ma w bazie danych'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Wyświetl utwory, których nie ma w bazie danych'),
    );
    await settle(tester, until: find.text('Poza bazą danych: 1 z 2'));
    expect(find.text('Utwory spoza bazy danych'), findsOneWidget);
    expect(find.text('Poza bazą danych: 1 z 2'), findsOneWidget);
    expect(find.text('Utwór'), findsOneWidget);
    expect(find.text('Małomiasteczkowy'), findsNothing);
  });

  /// A Biblioteka playlist of the two songs in [pumpLibrary]'s YouTube playlist.
  Future<void> importDoAuta() async {
    await playlists.importYouTube(
      await YouTubePlaylists(
        newPipeAvailable: false,
        explode: (id) async => YouTubePlaylistData(
          id: id,
          name: 'Do auta',
          owner: 'Shian',
          videos: const [
            YouTubeVideo(
              id: 'X2XWBcd5jn0',
              title: 'Dawid Podsiadło - Małomiasteczkowy',
              channel: 'Dawid Podsiadło',
            ),
            YouTubeVideo(
              id: 'nn',
              title: 'Nieznany - Utwór (Official Video)',
              channel: 'Nieznany',
            ),
          ],
        ),
      ).fetch('PLtest', settings),
    );
  }

  testWidgets(
    'holding a track ticks it; Back unticks; the ticked tracks go to a new '
    'playlist',
    (tester) async {
      // Both tracks on screen above the selection bar.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpLibrary(tester, before: importDoAuta);
      await tester.tap(find.text('Do auta'));
      await settle(tester, until: find.text('Utwór'));

      await tester.longPress(find.text('Małomiasteczkowy'));
      await tester.pumpAndSettle();
      expect(find.text('Zaznaczono: 1'), findsOneWidget);
      // While ticking, a tap ticks instead of playing.
      await tester.tap(find.text('Utwór'));
      await tester.pumpAndSettle();
      expect(find.text('Zaznaczono: 2'), findsOneWidget);
      expect(find.text('Odznacz'), findsOneWidget);
      await tester.tap(find.text('Utwór'));
      await tester.pumpAndSettle();
      expect(find.text('Zaznaczono: 1'), findsOneWidget);

      // Back unticks everything and stays on the playlist.
      await tester.tap(find.byTooltip('Wstecz'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Zaznaczono'), findsNothing);
      expect(find.text('Małomiasteczkowy'), findsOneWidget);

      await tester.longPress(find.text('Utwór'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wszystkie'));
      await tester.pumpAndSettle();
      expect(find.text('Zaznaczono: 2'), findsOneWidget);
      await tester.tap(find.text('Do playlisty'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nowa playlista'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Wybrane');
      await tester.tap(find.text('Zapisz'));
      await settle(tester, until: find.text('Utworzono playlistę „Wybrane”'));
      expect(find.textContaining('Zaznaczono'), findsNothing);

      final made = playlists.playlists.firstWhere((p) => p.name == 'Wybrane');
      final tracks = await tester.runAsync(() => playlists.tracks(made.id));
      // In the order they were ticked.
      expect([for (final t in tracks!) t.title], ['Utwór', 'Małomiasteczkowy']);
    },
  );

  testWidgets('⋮ › Zmień nazwę renames the playlist', (tester) async {
    await pumpLibrary(tester, before: importDoAuta);
    await tester.tap(find.text('Do auta'));
    await settle(tester, until: find.text('Utwór'));

    await tester.tap(find.byTooltip('Menu playlisty (⋮)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zmień nazwę'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'W trasę');
    await tester.tap(find.text('Zapisz'));
    await pumpUntil(tester, () => find.text('Do auta').evaluate().isEmpty);
    await tester.pumpAndSettle();

    expect(find.text('W trasę'), findsOneWidget);
    expect(playlists.playlists.single.name, 'W trasę');
  });

  testWidgets('Biblioteka highlights the playlist the playing song was queued '
      'from', (tester) async {
    await pumpLibrary(tester, before: importDoAuta);
    final title = find.descendant(
      of: find.byType(CurrentTitle),
      matching: find.text('Do auta'),
    );
    expect(
      tester.widget<Text>(title).style?.color,
      isNot(dummifyTheme.palette.accent),
    );
    expect(find.byType(PlayingBars), findsNothing);

    final playlist = playlists.playlists.single;
    final hits = [
      SearchHit.phoneOnly(
        LocalSong(id: 1, filePath: '/music/a.mp3', title: 'a', pending: true),
      ),
    ];
    unawaited(queue.start(hits, 0, playlistId: playlist.id + 1));
    await tester.pump();
    expect(find.byType(PlayingBars), findsNothing);

    unawaited(queue.start(hits, 0, playlistId: playlist.id));
    await tester.pump();
    expect(
      tester.widget<Text>(title).style?.color,
      dummifyTheme.palette.accent,
    );
    expect(find.byType(PlayingBars), findsOneWidget);
  });

  testWidgets('Biblioteka: a playlist moved into a new folder shows only inside it; sorting '
      'is remembered', (tester) async {
    await pumpLibrary(tester, before: importDoAuta);

    await tester.longPress(find.text('Do auta'));
    await tester.pumpAndSettle();
    expect(find.text('Przenieś do folderu'), findsOneWidget);
    await tester.tap(find.text('Nowy folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Podróże');
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();

    expect(find.text('Podróże'), findsOneWidget);
    expect(find.text('Folder • 1 playlista'), findsOneWidget);
    expect(find.text('Do auta'), findsNothing);
    // A category keeps the folder holding a playlist; "Nastroje" leaves it out.
    await tester.tap(find.text('Playlisty'));
    await tester.pumpAndSettle();
    expect(find.text('Podróże'), findsOneWidget);
    expect(find.text('Do auta'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nastroje'));
    await tester.pumpAndSettle();
    expect(find.text('Podróże'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Podróże'));
    await tester.pumpAndSettle();
    expect(find.text('Do auta'), findsOneWidget);
    expect(folders.openedAt(folders.folders.single.key), isNotNull);

    // Out of the folder again, from its own screen.
    await tester.longPress(find.text('Do auta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bez folderu'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pusty folder'), findsOneWidget);

    await tester.tap(find.byTooltip('Menu folderu (⋮)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń folder'));
    await tester.pumpAndSettle();
    expect(find.text('Do auta'), findsOneWidget);
    expect(folders.folders, isEmpty);

    await tester.tap(find.text('Ostatnie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alfabetycznie'));
    await tester.pumpAndSettle();
    expect(find.text('Alfabetycznie'), findsOneWidget);
    final reloaded = LibraryFolders();
    await tester.runAsync(reloaded.load);
    expect(reloaded.sort, LibrarySort.alphabetical);
  });

  testWidgets(
    'a playlist made on the phone is shared after making it on YouTube',
    (tester) async {
      await pumpLibrary(
        tester,
        before: () async {
          await importDoAuta();
          final imported = playlists.playlists.single;
          final tracks = await playlists.tracks(imported.id);
          await playlists.create('Na telefonie', [
            for (final t in tracks)
              playlistHit(t, catalog, library, youTubeLibrary),
          ]);
        },
      );
      await tester.tap(find.text('Na telefonie'));
      await settle(tester, until: find.text('Utwór'));

      await tester.tap(find.byTooltip('Udostępnij'));
      await tester.pumpAndSettle();
      expect(find.text('Otwórz w YouTube'), findsNothing);
      await tester.tap(find.text('Kopiuj link'));
      await tester.pumpAndSettle();
      expect(find.textContaining('nie ma jeszcze linku'), findsOneWidget);

      await tester.tap(find.byTooltip('Udostępnij'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Utwórz na YouTube'));
      await tester.pumpAndSettle();
      expect(find.text('Utworzyć playlistę na YouTube?'), findsOneWidget);
      await tester.tap(find.text('Utwórz'));
      await settle(tester, until: find.text('Playlista jest na YouTube'));
      expect(find.text('Dodano 2 utw.'), findsOneWidget);
      expect(youTubeApi.playlists.values.single, ['X2XWBcd5jn0', 'nn']);
      await tester.tap(find.text('Zamknij'));
      await tester.pumpAndSettle();

      expect(youTubeAccount.email, 'ja@example.com');
      await tester.tap(find.byTooltip('Udostępnij'));
      await tester.pumpAndSettle();
      expect(find.text('Utwórz na YouTube'), findsNothing);
      expect(find.text('Otwórz w YouTube'), findsOneWidget);
      final made = playlists.playlists.firstWhere(
        (p) => p.name == 'Na telefonie',
      );
      expect(
        made.link,
        Uri.parse(
          'https://www.youtube.com/playlist?list=${youTubeApi.playlists.keys.single}',
        ),
      );
    },
  );
}
