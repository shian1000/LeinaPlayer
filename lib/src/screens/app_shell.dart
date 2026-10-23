import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_updates.dart';
import '../data/database_sync.dart';
import '../data/incoming_links.dart';
import '../data/local_library.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/source_settings.dart';
import '../data/spotify_playlist.dart';
import '../data/video_link.dart';
import '../data/youtube_library.dart';
import '../data/youtube_search.dart';
import '../playback/playback_queue.dart';
import '../playback/track_player.dart';
import '../theme.dart';
import '../widgets/feature_info.dart';
import '../widgets/queue_toast.dart';
import '../widgets/song_tile.dart';
import '../widgets/update_dialog.dart';
import 'discover_screen.dart';
import 'feature_infos.dart';
import 'first_run_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'now_playing.dart';
import 'playlist_import.dart';
import 'playlist_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class _TabSpec {
  const _TabSpec(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

// After Juxtopposed's Spotify redesign: "Odkrywaj" and the profile ("Ja") are tabs; "Utwórz"
// is Biblioteka's "+".
const _tabs = [
  _TabSpec('Home', Icons.home_outlined, Icons.home),
  _TabSpec('Odkrywaj', Icons.auto_awesome_outlined, Icons.auto_awesome),
  _TabSpec('Wyszukaj', Icons.search, Icons.search),
  _TabSpec('Biblioteka', Icons.library_music_outlined, Icons.library_music),
  _TabSpec('Ja', Icons.person_outline, Icons.person),
];

const _libraryTabIndex = 3;

/// Root layout: bottom navigation and one nested navigator per tab so the bottom bar stays
/// visible when drilling into e.g. a playlist (same as the reference app).
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.links});

  /// YouTube and Spotify links shared to the app or opened with it ([IncomingLinks]).
  final Stream<String>? links;

  static AppShellState of(BuildContext context) =>
      context.findAncestorStateOfType<AppShellState>()!;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  final _navigatorKeys = List.generate(
    _tabs.length,
    (_) => GlobalKey<NavigatorState>(),
  );
  int _currentTab = 0;
  StreamSubscription<String>? _linksSub;
  final _toast = QueueToast();
  AppUpdates? _updates;
  bool _updateOffered = false;
  DatabaseSync? _sync;
  bool _firstRunShown = false;

  @override
  void initState() {
    super.initState();
    _linksSub = widget.links?.listen(_onLink);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final updates = context
        .getInheritedWidgetOfExactType<AppUpdatesScope>()
        ?.notifier;
    if (updates != _updates) {
      _updates?.removeListener(_offerUpdate);
      _updates = updates?..addListener(_offerUpdate);
      _offerUpdate();
    }

    final sync = context
        .getInheritedWidgetOfExactType<DatabaseSyncScope>()
        ?.notifier;
    if (sync == _sync) return;
    _sync?.removeListener(_askFirstRun);
    _sync = sync?..addListener(_askFirstRun);
    _askFirstRun();
  }

  /// A fresh install's question about GitHub, once its settings are read (`DatabaseSync.load`).
  void _askFirstRun() {
    if (_firstRunShown || !(_sync?.needsGitHubChoice ?? false)) return;
    _firstRunShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FirstRunScreen.show(context);
    });
  }

  /// A newer release is offered once per start, until answered "Później".
  void _offerUpdate() {
    final updates = _updates;
    final release = updates?.available;
    if (_updateOffered || updates == null || !updates.shouldOffer) return;
    _updateOffered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showUpdateDialog(context, updates, release!);
    });
  }

  @override
  void dispose() {
    _updates?.removeListener(_offerUpdate);
    _sync?.removeListener(_askFirstRun);
    _linksSub?.cancel();
    _toast.dispose();
    super.dispose();
  }

  /// Opens [url] like a link given to the app ("Na później" uses it).
  Future<void> openLink(String url) => _onLink(url);

  /// A playlist link (YouTube or Spotify, or a Spotify album) is imported and opened in
  /// Biblioteka; a YouTube video or Spotify track link is played (recognised as a MusicDatabase
  /// song where possible) in the full player.
  Future<void> _onLink(String text) async {
    // Whatever was open (a sheet, a dialog, the full player) gives way to the link.
    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    if (text.contains('spotify.') || text.contains('spotify:')) {
      return _onSpotifyLink(text);
    }
    final link = parseYouTubeLink(text);
    switch (link) {
      case null:
        _tell(
          'To nie jest link do filmu ani playlisty z YouTube ani do utworu, albumu lub '
          'playlisty ze Spotify.',
        );
      case YouTubePlaylistLink(:final listId):
        await _importAndOpen(listId);
      case YouTubeVideoLink():
        await _playVideo(link);
    }
  }

  Future<void> _onSpotifyLink(String text) async {
    final direct = parseSpotifyLink(text);
    if (direct != null && direct.kind != SpotifyLinkKind.track) {
      return _importAndOpen(text);
    }
    if (direct == null && findSpotifyShortLink(text) == null) {
      return _tell('Ze Spotify można tu otworzyć utwór, album albo playlistę.');
    }
    final spotify = YouTubeScope.spotifyOf(context);
    final catalog = SongCatalogScope.of(context);
    final playlists = PlaylistLibraryScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final queue = PlaybackQueueScope.of(context);
    String? playlist;
    await runQueueAction(context, (onStatus) async {
      onStatus('Sprawdzam link ze Spotify…');
      final SpotifyTrack track;
      try {
        var link = direct;
        if (link == null) {
          link = await spotify.resolveShortLink(findSpotifyShortLink(text)!);
          if (link == null) {
            return const PlayOutcome.failed(
              'Ten link ze Spotify nie prowadzi do utworu, albumu ani playlisty.',
            );
          }
          if (link.kind != SpotifyLinkKind.track) {
            playlist = 'spotify:${link.kind.name}:${link.id}';
            return null;
          }
        }
        track = await spotify.fetchTrack(link.id);
      } on SpotifyException catch (e) {
        return PlayOutcome.failed(e.message);
      }
      final hit = await hitForSpotifyTrack(
        track,
        catalog: catalog,
        playlists: playlists,
        library: library,
        youTube: youTube,
      );
      final outcome = await queue.start([hit], 0, onStatus: onStatus);
      if (outcome.played && !outcome.external && mounted) {
        unawaited(NowPlayingScreen.open(context));
      }
      return outcome;
    });
    if (playlist != null && mounted) await _importAndOpen(playlist!);
  }

  void _tell(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _importAndOpen(String link) async {
    final playlist = await runPlaylistImport(context, link);
    if (playlist == null || !mounted) return;
    setState(() => _currentTab = _libraryTabIndex);
    final library = _navigatorKeys[_libraryTabIndex].currentState!;
    library.popUntil((r) => r.isFirst);
    library.push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistScreen(playlist: playlist),
      ),
    );
  }

  Future<void> _playVideo(YouTubeVideoLink link) async {
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final search = YouTubeScope.searchOf(context);
    final settings = SourceSettingsScope.of(context);
    final queue = PlaybackQueueScope.of(context);
    await runQueueAction(context, (onStatus) async {
      onStatus('Sprawdzam link z YouTube…');
      final hit = await hitForVideoLink(
        link,
        catalog: catalog,
        library: library,
        youTube: youTube,
        search: search,
        settings: settings,
      );
      final outcome = await queue.start(
        [hit],
        0,
        youTubeListId: link.listId,
        onStatus: onStatus,
      );
      // Unless it went to the YouTube app after all.
      if (outcome.played && !outcome.external && mounted) {
        unawaited(NowPlayingScreen.open(context));
      }
      return outcome;
    });
  }

  static const _tabRoots = <Widget>[
    HomeScreen(),
    DiscoverScreen(),
    SearchScreen(),
    LibraryScreen(),
    ProfileScreen(),
  ];

  void _onTabTapped(int index) {
    if (index == _currentTab) {
      _navigatorKeys[index].currentState!.popUntil((route) => route.isFirst);
    } else {
      setState(() => _currentTab = index);
    }
  }

  void _onBack() {
    final navigator = _navigatorKeys[_currentTab].currentState!;
    if (navigator.canPop()) {
      navigator.pop();
    } else if (_currentTab != 0) {
      setState(() => _currentTab = 0);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: QueueToastScope(
        notifier: _toast,
        child: Scaffold(
          body: Stack(
            children: [
              IndexedStack(
                index: _currentTab,
                children: [
                  for (var i = 0; i < _tabRoots.length; i++)
                    Navigator(
                      key: _navigatorKeys[i],
                      onGenerateRoute: (_) =>
                          MaterialPageRoute<void>(builder: (_) => _tabRoots[i]),
                    ),
                ],
              ),
              // Right above the mini player, over the screen.
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: QueueToastView(),
              ),
            ],
          ),
          // Like the reference app: touching the mini player (or the tabs) clears the note.
          bottomNavigationBar: Listener(
            onPointerDown: (_) => _toast.hide(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiniPlayer(),
                _BottomBar(currentIndex: _currentTab, onTap: _onTabTapped),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.navBar,
        border: palette.outline == null
            ? null
            : Border(top: BorderSide(color: palette.outline!)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: InkResponse(
                    onTap: () => onTap(i),
                    onLongPress: switch (i) {
                      0 => () => showFeatureInfo(context, FeatureInfos.home),
                      1 => () => showFeatureInfo(
                        context,
                        FeatureInfos.discover,
                      ),
                      _ => null,
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          i == currentIndex
                              ? _tabs[i].activeIcon
                              : _tabs[i].icon,
                          size: 28,
                          color: i == currentIndex
                              ? palette.textPrimary
                              : palette.textSecondary,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _tabs[i].label,
                          style: TextStyle(
                            fontSize: AppFontSize.navLabel,
                            color: i == currentIndex
                                ? palette.textPrimary
                                : palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
