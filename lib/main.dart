import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app_name.dart';
import 'src/data/album_covers.dart';
import 'src/data/database_sync.dart';
import 'src/data/incoming_links.dart';
import 'src/data/local_library.dart';
import 'src/data/account.dart';
import 'src/data/outbox.dart';
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
    backend: () => JustAudioBackend(
      widget.mediaSession,
      (track) => _albumCovers.artFile(
        track.cover,
        filter: _themeController.coverFilter,
        color: _themeController.monochromeColor,
        strength: _themeController.coverFilterStrength,
        background: _themeController.monochromeBackground,
      ),
      _coverLook,
    ),
  );
  final _sourceSettings = SourceSettings();

  /// The cover filter and its colour: the notification's cover is made again when they change.
  final _coverLook = ValueNotifier('');
  void _updateCoverLook() => _coverLook.value =
      '${_themeController.coverFilter.name}|'
      '${_themeController.monochromeColor.toARGB32()}|'
      '${_themeController.coverFilterStrength}|'
      '${_themeController.monochromeBackground?.toARGB32()}';

  /// The native link chooser takes the theme's colours; sent again only when they change.
  String? _chooserLook;
  void _updateChooserLook() {
    Map<String, Object?> colours(AppThemeDef def) {
      final p = def.palette;
      return {
        'surface': p.surface.toARGB32(),
        'surfaceHigh': p.surfaceHigh.toARGB32(),
        'textPrimary': p.textPrimary.toARGB32(),
        'textSecondary': p.textSecondary.toARGB32(),
        'accent': p.accent.toARGB32(),
        'divider': p.divider.toARGB32(),
        'fontFamily': def.fontFamily,
      };
    }

    final mode = _themeController.themeMode.name;
    final light = colours(_themeController.light);
    final dark = colours(_themeController.dark);
    final key = '$mode|$light|$dark';
    if (key == _chooserLook) return;
    _chooserLook = key;
    setLinkChooserLook(mode: mode, light: light, dark: dark);
  }

  late final _albumCovers = AlbumCovers(
    _localLibrary.database,
    _sourceSettings,
  );
  final _account = Account();
  late final _outbox = Outbox(
    userName: () => _account.userName,
    authToken: () => _account.token,
  )..onUnauthorized = _account.tokenRejected;
  Timer? _outboxSendSoon;
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
      outbox: _outbox,
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
  late final Future<void> _youTubeLoaded;

  /// The `music.db` download whose settled songs were last cleaned out of the phone's matches.
  DateTime? _settledFor;

  @override
  void initState() {
    super.initState();
    _startDatabaseSync();
    _updateCoverLook();
    _themeController.addListener(_updateCoverLook);
    _updateChooserLook();
    _themeController.addListener(_updateChooserLook);
    _sourceSettings.load().catchError(
      (Object e) => debugPrint('Loading music source settings failed: $e'),
    );
    final localLoaded = _localLibrary.load().catchError(
      (Object e) => debugPrint('Loading local library failed: $e'),
    );
    final youTubeLoaded = _youTubeLoaded = _youTubeLibrary.load().catchError(
      (Object e) => debugPrint('Loading YouTube library failed: $e'),
    );
    _songCatalog.addListener(_forgetSettledMatches);
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
      onResume: () async {
        await _databaseSync.syncIfDue();
        await _sendOutbox();
      },
      onHide: _queueSession.save,
    );
    // A minute's wait lets the video found instead of a dead link join the same request.
    _outbox.onReported = () {
      _outboxSendSoon?.cancel();
      _outboxSendSoon = Timer(const Duration(minutes: 1), _sendOutbox);
    };
  }

  /// Once a newly downloaded `music.db` is loaded, the phone's own YouTube findings for songs it
  /// now settles (a link or "N/A") — or no longer has — are dropped: MusicDatabase's value wins
  /// anyway. A link YouTube removed settles nothing: the phone's replacement stays until
  /// MusicDatabase changes it, and the dead link is in the outbox for MusicDatabase.
  Future<void> _forgetSettledMatches() async {
    final catalog = _songCatalog;
    final syncTime = catalog.loadedSyncTime;
    if (catalog.status != CatalogStatus.ready ||
        syncTime == null ||
        syncTime == _settledFor) {
      return;
    }
    _settledFor = syncTime;
    try {
      await _youTubeLoaded;
      final forgotten = await _youTubeLibrary.forgetSettled((id) {
        final song = catalog.byId(id);
        if (song == null) return true;
        return switch (song.youTube) {
          YouTubeLink.unknown => false,
          YouTubeLink.linked => !_youTubeLibrary.isVideoRemoved(
            song.youtubeVideoId!,
          ),
          _ => true,
        };
      });
      if (forgotten > 0) {
        debugPrint(
          'Forgot $forgotten phone YouTube findings settled by music.db',
        );
      }
      // Also those found dead before the outbox existed; already reported ones are skipped.
      for (final videoId in _youTubeLibrary.removedVideos) {
        final song = catalog.findByYouTubeId(videoId);
        if (song == null) continue;
        if (!await _outbox.reportDeadYouTubeLink(song, videoId)) continue;
        final found = await _youTubeLibrary.matchDetailsFor(song.id);
        if (found != null) {
          await _outbox.reportReplacement(song, videoId, found);
        }
      }
    } catch (e) {
      debugPrint('Forgetting settled YouTube findings failed: $e');
    }
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
    await _account.load().catchError(
      (Object e) => debugPrint('Loading the account failed: $e'),
    );
    try {
      await _databaseSync.load();
      await _databaseSync.syncIfDue();
    } catch (e) {
      debugPrint('Database sync on start failed: $e');
    }
    await _outbox.load().catchError(
      (Object e) => debugPrint('Reading the outbox failed: $e'),
    );
    await _sendOutbox();
  }

  /// Hands the outbox to MusicDatabase's inbox, over the same addresses as the download;
  /// whatever can't go now waits for the next start, return to the app or new report.
  Future<void> _sendOutbox() async {
    try {
      await _outbox.send(await _databaseSync.serverAddresses());
    } catch (e) {
      debugPrint('Sending the outbox failed: $e');
    }
  }

  @override
  void dispose() {
    _themeController.removeListener(_updateCoverLook);
    _themeController.removeListener(_updateChooserLook);
    _songCatalog.removeListener(_forgetSettledMatches);
    _outboxSendSoon?.cancel();
    _coverLook.dispose();
    _lifecycle.dispose();
    _historySub.cancel();
    _incomingLinks.dispose();
    _queueSession.dispose();
    _playHistory.dispose();
    _playbackQueue.dispose();
    _player.dispose();
    _sourceSettings.dispose();
    _albumCovers.dispose();
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
      child: AccountScope(
        notifier: _account,
        child: OutboxScope(
          notifier: _outbox,
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
                          child: AlbumCoversScope(
                            notifier: _albumCovers,
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
                                    theme: buildAppTheme(
                                      _themeController.light,
                                    ),
                                    darkTheme: buildAppTheme(
                                      _themeController.dark,
                                    ),
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
          ),
        ),
      ),
    );
  }
}
