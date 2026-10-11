import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'src/data/database_sync.dart';
import 'src/data/local_library.dart';
import 'src/data/playlist_library.dart';
import 'src/data/song_catalog.dart';
import 'src/data/source_settings.dart';
import 'src/data/youtube_audio.dart';
import 'src/data/youtube_library.dart';
import 'src/data/youtube_search.dart';
import 'src/playback/player_controller.dart';
import 'src/screens/app_shell.dart';
import 'src/theme.dart';
import 'src/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Media notification and lock-screen controls; while music plays, the foreground service
  // behind them keeps Android from killing the app.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.shian1000.music_database_app.playback',
    androidNotificationChannelName: 'Odtwarzanie',
    androidNotificationOngoing: true,
  );
  // Loaded before the first frame so the app doesn't flash the default theme on start.
  final themeController = ThemeController();
  try {
    await themeController.load();
  } catch (e) {
    debugPrint('Loading appearance settings failed: $e');
  }
  runApp(MusicDatabaseApp(themeController: themeController));
}

class MusicDatabaseApp extends StatefulWidget {
  const MusicDatabaseApp({
    super.key,
    this.themeController,
    this.youTubeSearch,
    this.youTubeAudio,
    this.youTubePlaylists,
  });

  /// Already-loaded appearance settings; when omitted (tests) defaults are loaded in the
  /// background.
  final ThemeController? themeController;

  /// Replaced in tests, so they don't reach YouTube.
  final YouTubeSearch? youTubeSearch;
  final YouTubeAudio? youTubeAudio;
  final YouTubePlaylists? youTubePlaylists;

  @override
  State<MusicDatabaseApp> createState() => _MusicDatabaseAppState();
}

class _MusicDatabaseAppState extends State<MusicDatabaseApp> {
  late final ThemeController _themeController =
      widget.themeController ?? (ThemeController()..load());
  final _databaseSync = DatabaseSync();
  late final _songCatalog = SongCatalog(_databaseSync);
  late final _localLibrary = LocalLibrary(_songCatalog);
  late final _youTubeLibrary = YouTubeLibrary(_localLibrary.database);
  final _player = PlayerController();
  final _sourceSettings = SourceSettings();
  late final _youTubeSearch = widget.youTubeSearch ?? YouTubeSearch();
  late final _youTubeAudio = widget.youTubeAudio ?? YouTubeAudio();
  late final _youTubePlaylists = widget.youTubePlaylists ?? YouTubePlaylists();
  late final _playlistLibrary = PlaylistLibrary(
    _localLibrary.database,
    _songCatalog,
    _youTubeLibrary,
  );
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _startDatabaseSync();
    _sourceSettings.load().catchError(
      (Object e) => debugPrint('Loading music source settings failed: $e'),
    );
    _localLibrary.load().catchError(
      (Object e) => debugPrint('Loading local library failed: $e'),
    );
    _youTubeLibrary.load().catchError(
      (Object e) => debugPrint('Loading YouTube library failed: $e'),
    );
    _playlistLibrary.load().catchError(
      (Object e) => debugPrint('Loading playlists failed: $e'),
    );
    // Android often keeps the app alive for days, so "once a day on start" also has to cover
    // coming back to an app that was only in the background.
    _lifecycle = AppLifecycleListener(onResume: _databaseSync.syncIfDue);
  }

  Future<void> _startDatabaseSync() async {
    try {
      await _databaseSync.load();
      await _databaseSync.syncIfDue();
    } catch (e) {
      debugPrint('Database sync on start failed: $e');
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _player.dispose();
    _sourceSettings.dispose();
    _playlistLibrary.dispose();
    _youTubeLibrary.dispose();
    _localLibrary.dispose();
    _songCatalog.dispose();
    _databaseSync.dispose();
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DatabaseSyncScope(
      notifier: _databaseSync,
      child: SongCatalogScope(
        notifier: _songCatalog,
        child: LocalLibraryScope(
          notifier: _localLibrary,
          child: YouTubeLibraryScope(
            notifier: _youTubeLibrary,
            child: PlaylistLibraryScope(
              notifier: _playlistLibrary,
              child: PlayerScope(
                notifier: _player,
                child: SourceSettingsScope(
                  notifier: _sourceSettings,
                  child: YouTubeScope(
                    search: _youTubeSearch,
                    audio: _youTubeAudio,
                    playlists: _youTubePlaylists,
                    child: ThemeScope(
                      notifier: _themeController,
                      child: ListenableBuilder(
                        listenable: _themeController,
                        builder: (context, _) => MaterialApp(
                          title: 'MusicDatabase',
                          debugShowCheckedModeBanner: false,
                          theme: buildAppTheme(_themeController.light),
                          darkTheme: buildAppTheme(_themeController.dark),
                          themeMode: _themeController.themeMode,
                          // Tab screens have no AppBar to set the status-bar icon colour, so
                          // match it to the active theme here (dark icons on light themes and
                          // vice versa).
                          builder: (context, child) =>
                              AnnotatedRegion<SystemUiOverlayStyle>(
                                value:
                                    Theme.of(context).brightness ==
                                        Brightness.light
                                    ? SystemUiOverlayStyle.dark
                                    : SystemUiOverlayStyle.light,
                                child: child!,
                              ),
                          home: const AppShell(),
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
  }
}
