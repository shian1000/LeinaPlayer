import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app_name.dart';
import 'src/data/album_covers.dart';
import 'src/data/custom_covers.dart';
import 'src/data/database_sync.dart';
import 'src/data/incoming_links.dart';
import 'src/data/home_layout.dart';
import 'src/data/later_links.dart';
import 'src/data/library_folders.dart';
import 'src/data/listening_log.dart';
import 'src/data/local_library.dart';
import 'src/data/account.dart';
import 'src/data/mood_filter.dart';
import 'src/data/moods.dart';
import 'src/data/outbox.dart';
import 'src/data/play_history.dart';
import 'src/data/playlist_library.dart';
import 'src/data/saved_songs.dart';
import 'src/data/smart_playlists.dart';
import 'src/data/hidden_songs.dart';
import 'src/data/server_downloads.dart';
import 'src/data/song_catalog.dart';
import 'src/data/source_settings.dart';
import 'src/data/track_ref.dart';
import 'src/data/youtube_account.dart';
import 'src/data/youtube_audio.dart';
import 'src/data/youtube_library.dart';
import 'src/data/youtube_search.dart';
import 'src/playback/downloads.dart';
import 'src/playback/listening_tracker.dart';
import 'src/playback/playback_queue.dart';
import 'src/playback/player_controller.dart';
import 'src/playback/queue_session.dart';
import 'src/playback/track_player.dart';
import 'src/screens/app_shell.dart';
import 'src/screens/home_screen.dart';
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
        // Covers are decoded whole otherwise (an iTunes one is 1000+ px): slower to hand over
        // and fewer fit in audio_service's bitmap cache.
        artDownscaleWidth: 512,
        artDownscaleHeight: 512,
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

  void _updateCrossfade() =>
      _player.crossfade = Duration(seconds: _sourceSettings.crossfadeSeconds);

  /// Takes effect from the next song the notification shows.
  void _updateNotificationNames() =>
      widget.mediaSession?.latinNames = _themeController.latinNames;

  late final _albumCovers = AlbumCovers(
    _localLibrary.database,
    _sourceSettings,
  );
  final _customCovers = CustomCovers();
  late final Future<void> _coversLoaded;
  final _account = Account();
  final _youTubeAccount = YouTubeAccount();
  late final _outbox = Outbox(
    userName: () => _account.userName,
    authToken: () => _account.token,
  )..onUnauthorized = _account.tokenRejected;
  Timer? _outboxSendSoon;
  late final _youTubeSearch = widget.youTubeSearch ?? YouTubeSearch();
  late final _youTubeAudio = widget.youTubeAudio ?? YouTubeAudio();
  late final _youTubePlaylists = widget.youTubePlaylists ?? YouTubePlaylists();
  late final _serverDownloads = ServerDownloads(_localLibrary.database);
  late final _trackPlayer = TrackPlayer(
    player: _player,
    settings: _sourceSettings,
    youTubeLibrary: _youTubeLibrary,
    youTubeAudio: _youTubeAudio,
    youTubeSearch: _youTubeSearch,
    outbox: _outbox,
    serverDownloads: _serverDownloads,
    serverAddresses: _databaseSync.serverAddresses,
  );
  late final _playbackQueue = PlaybackQueue(
    _trackPlayer,
    filter: _moodFilter,
    hidden: _hiddenSongs,
  );
  late final _downloads = Downloads(
    _trackPlayer,
    _serverDownloads,
    _youTubeLibrary,
    database: _localLibrary.database,
    resolve: (ref) =>
        resolveTrack(ref, _songCatalog, _localLibrary, _youTubeLibrary),
  );
  late final _moodFilter = MoodFilter(
    moodsOf: (songId) => _moodLibrary.moodKeysOf(songId),
    knownMoods: () => _moodLibrary.moodKeys,
    moodChanges: _moodLibrary,
  );
  late final _playlistLibrary = PlaylistLibrary(
    _localLibrary.database,
    _songCatalog,
    _youTubeLibrary,
    userName: () => _account.userName,
    authToken: () => _account.token,
    covers: _customCovers,
  )..onUnauthorized = _account.tokenRejected;
  Timer? _playlistSyncSoon;
  late final _moodLibrary =
      MoodLibrary(
          _localLibrary.database,
          _databaseSync,
          userName: () => _account.userName,
          authToken: () => _account.token,
          canEditGlobal: () => _account.hasPermission(Account.editGlobalMoods),
          covers: _customCovers,
        )
        ..onUnauthorized = _account.tokenRejected
        ..onPermissionRevoked = _account.permissionRevoked;
  Timer? _moodSyncSoon;

  /// The user whose playlists Biblioteka shows; another one logging in shows theirs.
  String? _playlistsUser;
  late final _playHistory = PlayHistory(_localLibrary.database);
  late final _listeningLog = ListeningLog(
    _localLibrary.database,
    userName: () => _account.userName,
    authToken: () => _account.token,
  )..onUnauthorized = _account.tokenRejected;
  late final _listeningTracker = ListeningTracker(
    played: _playbackQueue.played,
    player: _player,
    log: _listeningLog,
    playlistUid: (id) =>
        _playlistLibrary.playlists.where((p) => p.id == id).firstOrNull?.uid,
    mood: (key) => [
      ..._moodLibrary.userMoods,
      ..._moodLibrary.globalMoods,
    ].where((m) => m.key == key).firstOrNull,
  );
  late final _queueSession = QueueSession(
    queue: _playbackQueue,
    player: _player,
    resolve: (ref) =>
        resolveTrack(ref, _songCatalog, _localLibrary, _youTubeLibrary),
  );
  late final StreamSubscription<QueuePlay> _historySub;
  final _incomingLinks = IncomingLinks();
  final _laterLinks = LaterLinks();
  late final _libraryFolders = LibraryFolders(
    userName: () => _account.userName,
    authToken: () => _account.token,
  )..onUnauthorized = _account.tokenRejected;
  Timer? _folderSyncSoon;
  final _savedSongs = SavedSongs();
  final _hiddenSongs = HiddenSongs();
  final _smartPlaylists = SmartPlaylists();
  final _homeLayout = HomeLayout(defaults: HomeScreen.defaultSections);
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
    _updateNotificationNames();
    _themeController.addListener(_updateNotificationNames);
    _moodFilter.load().catchError(
      (Object e) => debugPrint('Loading the mood filter failed: $e'),
    );
    _sourceSettings.load().catchError(
      (Object e) => debugPrint('Loading music source settings failed: $e'),
    );
    _sourceSettings.addListener(_updateCrossfade);
    final localLoaded = _localLibrary.load().catchError(
      (Object e) => debugPrint('Loading local library failed: $e'),
    );
    final youTubeLoaded = _youTubeLoaded = _youTubeLibrary.load().catchError(
      (Object e) => debugPrint('Loading YouTube library failed: $e'),
    );
    _serverDownloads.load().catchError(
      (Object e) => debugPrint('Loading downloaded server files failed: $e'),
    );
    _songCatalog.addListener(_forgetSettledMatches);
    _songCatalog.addListener(_useUserYouTubeLinks);
    _outbox.addListener(_useUserYouTubeLinks);
    _playHistory.load().catchError(
      (Object e) => debugPrint('Loading play history failed: $e'),
    );
    _laterLinks.load();
    _youTubeAccount.load().catchError(
      (Object e) => debugPrint('Loading the YouTube account failed: $e'),
    );
    _libraryFolders.load().catchError(
      (Object e) => debugPrint('Loading Biblioteka folders failed: $e'),
    );
    _savedSongs.load().catchError(
      (Object e) => debugPrint('Loading saved songs failed: $e'),
    );
    _hiddenSongs.load().catchError(
      (Object e) => debugPrint('Loading hidden songs failed: $e'),
    );
    _smartPlaylists.load().catchError(
      (Object e) => debugPrint('Loading dynamic playlists failed: $e'),
    );
    _homeLayout.load().catchError(
      (Object e) => debugPrint('Loading the Home layout failed: $e'),
    );
    _coversLoaded = _customCovers.load().catchError(
      (Object e) => debugPrint('Loading custom covers failed: $e'),
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
    _listeningTracker;
    _listeningLog.onManyUnsent = _syncListens;
    _restoreSession(localLoaded, youTubeLoaded);
    // After the first frame, when AppShell already listens (the link that started the app
    // would otherwise go nowhere).
    WidgetsBinding.instance.addPostFrameCallback((_) => _incomingLinks.start());
    // A few seconds' wait lets several changes in a row go to MusicDatabase together.
    _playlistLibrary.onChanged = () {
      _playlistSyncSoon?.cancel();
      _moodSyncSoon?.cancel();
      _playlistSyncSoon = Timer(const Duration(seconds: 3), _syncPlaylists);
    };
    _songCatalog.setMoodNames(_moodLibrary.moodNamesOf);
    _moodLibrary.addListener(_songCatalog.moodsChanged);
    _moodLibrary.onChanged = () {
      _moodSyncSoon?.cancel();
      _moodSyncSoon = Timer(const Duration(seconds: 3), _syncMoods);
    };
    _libraryFolders.onChanged = () {
      _folderSyncSoon?.cancel();
      _folderSyncSoon = Timer(const Duration(seconds: 3), _syncFolders);
    };
    _playlistLibrary.addListener(_updateFolderItems);
    _moodLibrary.addListener(_updateFolderItems);
    _account.addListener(_accountChanged);
    // Android often keeps the app alive for days, so "once a day on start" also has to cover
    // coming back to an app that was only in the background.
    _lifecycle = AppLifecycleListener(
      onResume: () async {
        // The link sheet may have saved one meanwhile.
        unawaited(_laterLinks.load());
        unawaited(_downloads.resume());
        await _databaseSync.syncIfDue();
        await _sendOutbox();
        await _syncPlaylists();
        await _syncMoods();
        await _syncFolders();
        await _syncListens();
      },
      onHide: () {
        _queueSession.save();
        _listeningTracker.save().catchError(
          (Object e) => debugPrint('Saving listening stats failed: $e'),
        );
      },
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
      final bad = catalog.badVideos;
      // Never music.db's own link (MusicDatabase takes a picked video off its list): the phone
      // would take it for a dead one.
      final dropped = await _youTubeLibrary.useBadVideos(
        BadVideos(
          everySong: {
            for (final v in bad.everySong)
              if (catalog.findByYouTubeId(v) == null) v,
          },
          forSong: bad.forSong,
        ),
      );
      if (dropped > 0) {
        debugPrint(
          'Forgot $dropped phone YouTube findings MusicDatabase turned down',
        );
      }
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
      // Videos found for songs without a link before this was reported, or matched outside
      // TrackPlayer (a shared link); already reported ones are skipped.
      for (final id in _youTubeLibrary.matchedSongIds) {
        final song = catalog.byId(id);
        if (song == null || song.youTube != YouTubeLink.unknown) continue;
        // The user picked the song's video by hand; that goes as a correction.
        if (_youTubeLibrary.userLinksFor(id)?.video != null) continue;
        final found = await _youTubeLibrary.matchDetailsFor(id);
        if (found == null || _youTubeLibrary.isVideoRemoved(found.id)) continue;
        await _outbox.reportFoundYouTubeLink(song, found);
      }
    } catch (e) {
      debugPrint('Forgetting settled YouTube findings failed: $e');
    }
  }

  /// The YouTube links the user set in "Informacje o utworze" are field corrections in the
  /// outbox; the phone plays them in place of music.db's until a downloaded music.db changes the
  /// value they correct (accepted, or settled otherwise).
  void _useUserYouTubeLinks() {
    final video = <int, String>{};
    final musicVideo = <int, String>{};
    for (final c in _outbox.corrections) {
      if (c.table != 'songs') continue;
      final song = _songCatalog.byId(c.rowId);
      if (song == null) continue;
      final (links, current) = switch (c.column) {
        'youtube_video_id' => (video, song.youtubeValue),
        'music_video_youtube_id' => (musicVideo, song.musicVideoId),
        _ => (null, null),
      };
      if (links == null ||
          _outbox.correctionOf(c.table, c.rowId, c.column, current) == null) {
        continue;
      }
      links[c.rowId] = '${c.newValue ?? ''}';
    }
    _youTubeLibrary.useUserLinks({
      for (final id in {...video.keys, ...musicVideo.keys})
        id: UserYouTubeLinks(video: video[id], musicVideo: musicVideo[id]),
    });
  }

  /// The last song and queue come back once the songs they refer to can be found.
  Future<void> _restoreSession(Future<void> local, Future<void> youTube) async {
    try {
      await Future.wait([local, youTube, _songCatalog.ensureLoaded()]);
    } catch (e) {
      debugPrint('Loading songs before restoring the queue failed: $e');
    }
    await _queueSession.restore();
    // Downloads Android stopped last time.
    unawaited(_downloads.resume());
  }

  Future<void> _startDatabaseSync() async {
    await _account.load().catchError(
      (Object e) => debugPrint('Loading the account failed: $e'),
    );
    _accountChanged();
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

  /// Logging in or out changes which playlists Biblioteka shows; a login also fetches the
  /// account's playlists from MusicDatabase. Also called once the saved login is read, which
  /// is when playlists are first loaded.
  void _accountChanged() {
    final user = _account.userName;
    if (_playlistsLoaded && user == _playlistsUser) return;
    final first = !_playlistsLoaded;
    _playlistsUser = user;
    _playlistsLoaded = true;
    final playlists = _playlistLibrary
        .load()
        .then((_) => _syncPlaylists())
        .catchError((Object e) => debugPrint('Loading playlists failed: $e'));
    final moods = _moodLibrary
        .load()
        .then((_) => _syncMoods())
        .catchError((Object e) => debugPrint('Loading moods failed: $e'));
    // Folders after both: their items have to be on the phone first.
    Future.wait([playlists, moods]).then((_) async {
      if (first) await _pruneCovers();
      await _syncFolders();
    });
    _syncListens();
  }

  /// Lets folders name their playlists and moods for MusicDatabase.
  void _updateFolderItems() {
    _libraryFolders
        .updateItems(
          playlists: _playlistLibrary.playlists,
          moods: [..._moodLibrary.userMoods, ..._moodLibrary.globalMoods],
        )
        .catchError(
          (Object e) => debugPrint('Updating folder items failed: $e'),
        );
  }

  /// Exchanges the account's Biblioteka folders with MusicDatabase.
  Future<void> _syncFolders() async {
    try {
      await _libraryFolders.sync(await _databaseSync.serverAddresses());
    } catch (e) {
      debugPrint('Syncing folders failed: $e');
    }
  }

  /// Exchanges the account's plays (the listening stats) with MusicDatabase.
  Future<void> _syncListens() async {
    try {
      await _listeningLog.sync(await _databaseSync.serverAddresses());
    } catch (e) {
      debugPrint('Syncing listening stats failed: $e');
    }
  }

  /// Deletes the cover pictures no playlist or mood refers to any more (replaced, removed or
  /// deleted with their playlist), once after start.
  Future<void> _pruneCovers() async {
    try {
      await _coversLoaded;
      await _customCovers.prune({
        ...await _playlistLibrary.usedCovers(),
        ...await _moodLibrary.usedCovers(),
      });
    } catch (e) {
      debugPrint('Pruning covers failed: $e');
    }
  }

  bool _playlistsLoaded = false;

  /// Exchanges the account's playlists with MusicDatabase, over the same addresses as the
  /// download; changes that can't go now wait for the next start, return to the app or change.
  Future<void> _syncPlaylists() async {
    try {
      await _playlistLibrary.sync(await _databaseSync.serverAddresses());
    } catch (e) {
      debugPrint('Syncing playlists failed: $e');
    }
  }

  /// Exchanges the account's moods with MusicDatabase (and sends changes to global moods),
  /// after asking what the user may do now: a permission granted or revoked in MusicDatabase
  /// shows without logging in again.
  Future<void> _syncMoods() async {
    try {
      final servers = await _databaseSync.serverAddresses();
      await _account.refreshPermissions(servers);
      await _moodLibrary.sync(servers);
    } catch (e) {
      debugPrint('Syncing moods failed: $e');
    }
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
    _themeController.removeListener(_updateNotificationNames);
    _songCatalog.removeListener(_forgetSettledMatches);
    _songCatalog.removeListener(_useUserYouTubeLinks);
    _outbox.removeListener(_useUserYouTubeLinks);
    _moodLibrary.removeListener(_songCatalog.moodsChanged);
    _outboxSendSoon?.cancel();
    _playlistSyncSoon?.cancel();
    _moodSyncSoon?.cancel();
    _folderSyncSoon?.cancel();
    _playlistLibrary.removeListener(_updateFolderItems);
    _moodLibrary.removeListener(_updateFolderItems);
    _account.removeListener(_accountChanged);
    _coverLook.dispose();
    _lifecycle.dispose();
    _historySub.cancel();
    _listeningTracker.dispose();
    _listeningLog.dispose();
    _incomingLinks.dispose();
    _queueSession.dispose();
    _playHistory.dispose();
    _laterLinks.dispose();
    _youTubeAccount.dispose();
    _libraryFolders.dispose();
    _savedSongs.dispose();
    _hiddenSongs.dispose();
    _smartPlaylists.dispose();
    _homeLayout.dispose();
    _playbackQueue.dispose();
    _downloads.dispose();
    _serverDownloads.dispose();
    _moodFilter.dispose();
    _sourceSettings.removeListener(_updateCrossfade);
    _player.dispose();
    _sourceSettings.dispose();
    _albumCovers.dispose();
    _customCovers.dispose();
    _playlistLibrary.dispose();
    _moodLibrary.dispose();
    _youTubeLibrary.dispose();
    _localLibrary.dispose();
    _songCatalog.dispose();
    _databaseSync.dispose();
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HiddenSongsScope(
      notifier: _hiddenSongs,
      child: DownloadsScope(
        notifier: _downloads,
        child: YouTubeAccountScope(
          notifier: _youTubeAccount,
          child: CustomCoversScope(
            notifier: _customCovers,
            child: DatabaseSyncScope(
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
                          child: MoodLibraryScope(
                            notifier: _moodLibrary,
                            child: MoodFilterScope(
                              notifier: _moodFilter,
                              child: PlayHistoryScope(
                                notifier: _playHistory,
                                child: ListeningLogScope(
                                  notifier: _listeningLog,
                                  child: LaterLinksScope(
                                    notifier: _laterLinks,
                                    child: LibraryFoldersScope(
                                      notifier: _libraryFolders,
                                      child: SavedSongsScope(
                                        notifier: _savedSongs,
                                        child: SmartPlaylistsScope(
                                          notifier: _smartPlaylists,
                                          child: HomeLayoutScope(
                                            notifier: _homeLayout,
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
                                                      playlists:
                                                          _youTubePlaylists,
                                                      child: ThemeScope(
                                                        notifier:
                                                            _themeController,
                                                        child: ListenableBuilder(
                                                          listenable:
                                                              _themeController,
                                                          builder: (context, _) => MaterialApp(
                                                            title: appName,
                                                            debugShowCheckedModeBanner:
                                                                false,
                                                            theme: buildAppTheme(
                                                              _themeController
                                                                  .light,
                                                            ),
                                                            darkTheme:
                                                                buildAppTheme(
                                                                  _themeController
                                                                      .dark,
                                                                ),
                                                            themeMode:
                                                                _themeController
                                                                    .themeMode,
                                                            // Tab screens have no AppBar to set the status-bar icon colour, so
                                                            // match it to the active theme here (dark icons on light themes and
                                                            // vice versa).
                                                            builder: (context, child) =>
                                                                AnnotatedRegion<
                                                                  SystemUiOverlayStyle
                                                                >(
                                                                  value:
                                                                      Theme.of(
                                                                            context,
                                                                          ).brightness ==
                                                                          Brightness
                                                                              .light
                                                                      ? SystemUiOverlayStyle
                                                                            .dark
                                                                      : SystemUiOverlayStyle
                                                                            .light,
                                                                  child: child!,
                                                                ),
                                                            home: AppShell(
                                                              links:
                                                                  _incomingLinks
                                                                      .links,
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
