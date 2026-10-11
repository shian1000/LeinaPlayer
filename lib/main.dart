import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app_name.dart';
import 'src/data/database_sync.dart';
import 'src/data/incoming_links.dart';
import 'src/data/local_library.dart';
import 'src/data/play_history.dart';
import 'src/data/playlist_library.dart';
import 'src/data/song_catalog.dart';
import 'src/data/source_settings.dart';
import 'src/data/track_ref.dart';
import 'src/data/youtube_audio.dart';
import 'src/data/youtube_library.dart';
import 'src/data/youtube_search.dart';
import 'src/playback/playback_queue.dart';
import 'src/playback/player_controller.dart';
import 'src/playback/queue_session.dart';
import 'src/playback/track_player.dart';
import 'src/screens/app_shell.dart';
import 'src/theme.dart';
import 'src/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Media notification, lock-screen and headset controls; while music plays, the foreground
  // service behind them keeps Android from killing the app.
  MediaSession? mediaSession;
  try {
    mediaSession = await AudioService.init(
      builder: MediaSession.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId:
            'com.shian1000.music_database_app.playback',
        androidNotificationChannelName: 'Odtwarzanie',
        androidNotificationOngoing: true,
        // White-on-transparent, as Android draws small notification icons as a mask.
        androidNotificationIcon: 'drawable/ic_stat_leina',
      ),
    );
  } catch (e) {
    debugPrint('Starting the media session failed: $e');
  }
  // Loaded before the first frame so the app doesn't flash the default theme on start.
  final themeController = ThemeController();
  try {
    await themeController.load();
  } catch (e) {
    debugPrint('Loading appearance settings failed: $e');
  }
  runApp(
    MusicDatabaseApp(
      themeController: themeController,
      mediaSession: mediaSession,
    ),
  );
}

class MusicDatabaseApp extends StatefulWidget {
  const MusicDatabaseApp({
    super.key,
    this.themeController,
    this.mediaSession,
    this.youTubeSearch,
    this.youTubeAudio,
    this.youTubePlaylists,
  });

  /// Already-loaded appearance settings; when omitted (tests) defaults are loaded in the
  /// background.
  final ThemeController? themeController;

  /// Plays through the media notification; `null` in tests (and if it failed to start).
  final MediaSession? mediaSession;

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
  late final _player = PlayerController(
    backend: () => JustAudioBackend(widget.mediaSession),
  );
  final _sourceSettings = SourceSettings();
  late final _youTubeSearch = widget.youTubeSearch ?? YouTubeSearch();
  late final _youTubeAudio = widget.youTubeAudio ?? YouTubeAudio();
  late final _youTubePlaylists = widget.youTubePlaylists ?? YouTubePlaylists();
  late final _playbackQueue = PlaybackQueue(
    TrackPlayer(
      player: _player,
      settings: _sourceSettings,
      youTubeLibrary: _youTubeLibrary,
      youTubeAudio: _youTubeAudio,
      youTubeSearch: _youTubeSearch,
    ),
  );
  late final _playlistLibrary = PlaylistLibrary(
    _localLibrary.database,
    _songCatalog,
    _youTubeLibrary,
  );
  late final _playHistory = PlayHistory(_localLibrary.database);
  late final _queueSession = QueueSession(
    queue: _playbackQueue,
    player: _player,
    resolve: (ref) =>
        resolveTrack(ref, _songCatalog, _localLibrary, _youTubeLibrary),
  );
  late final StreamSubscription<QueuePlay> _historySub;
  final _incomingLinks = IncomingLinks();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _startDatabaseSync();
    _sourceSettings.load().catchError(
      (Object e) => debugPrint('Loading music source settings failed: $e'),
    );
    final localLoaded = _localLibrary.load().catchError(
      (Object e) => debugPrint('Loading local library failed: $e'),
    );
    final youTubeLoaded = _youTubeLibrary.load().catchError(
      (Object e) => debugPrint('Loading YouTube library failed: $e'),
    );
    _playHistory.load().catchError(
      (Object e) => debugPrint('Loading play history failed: $e'),
    );
    _historySub = _playbackQueue.played.listen(
      (play) => _playHistory
          .record(
            TrackRef.of(play.hit),
            playlistId: play.playlistId,
            playlistName: play.playlistName,
          )
          .catchError(
            (Object e) => debugPrint('Recording play history failed: $e'),
          ),
    );
    _restoreSession(localLoaded, youTubeLoaded);
    // After the first frame, when AppShell already listens (the link that started the app
    // would otherwise go nowhere).
    WidgetsBinding.instance.addPostFrameCallback((_) => _incomingLinks.start());
    _playlistLibrary.load().catchError(
      (Object e) => debugPrint('Loading playlists failed: $e'),
    );
    // Android often keeps the app alive for days, so "once a day on start" also has to cover
    // coming back to an app that was only in the background.
    _lifecycle = AppLifecycleListener(
      onResume: _databaseSync.syncIfDue,
      onHide: _queueSession.save,
    );
  }

  /// The last song and queue come back once the songs they refer to can be found.
  Future<void> _restoreSession(Future<void> local, Future<void> youTube) async {
    try {
      await Future.wait([local, youTube, _songCatalog.ensureLoaded()]);
    } catch (e) {
      debugPrint('Loading songs before restoring the queue failed: $e');
    }
    await _queueSession.restore();
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
    _historySub.cancel();
    _incomingLinks.dispose();
    _queueSession.dispose();
    _playHistory.dispose();
    _playbackQueue.dispose();
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
              child: PlayHistoryScope(
                notifier: _playHistory,
                child: PlayerScope(
                  notifier: _player,
                  child: PlaybackQueueScope(
                    notifier: _playbackQueue,
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
                              title: appName,
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
                              home: AppShell(links: _incomingLinks.links),
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
  }
}
