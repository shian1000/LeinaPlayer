import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/incoming_links.dart';
import '../data/local_library.dart';
import '../data/song_catalog.dart';
import '../data/source_settings.dart';
import '../data/spotify_playlist.dart';
import '../data/video_link.dart';
import '../data/youtube_library.dart';
import '../data/youtube_search.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/song_tile.dart';
import 'create_sheet.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'now_playing.dart';
import 'playlist_import.dart';
import 'playlist_screen.dart';
import 'profile_drawer.dart';
import 'recents_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class _TabSpec {
  const _TabSpec(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const _tabs = [
  _TabSpec('Home', Icons.home_outlined, Icons.home),
  _TabSpec('Wyszukaj', Icons.search, Icons.search),
  _TabSpec('Biblioteka', Icons.library_music_outlined, Icons.library_music),
  _TabSpec('Utwórz', Icons.add, Icons.add),
];

const _libraryTabIndex = 2;
const _createTabIndex = 3;

/// Root layout: bottom navigation, the profile drawer, and one nested navigator per tab so the
/// bottom bar stays visible when drilling into e.g. a playlist (same as the reference app).
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _navigatorKeys = List.generate(
    _createTabIndex,
    (_) => GlobalKey<NavigatorState>(),
  );
  int _currentTab = 0;
  StreamSubscription<String>? _linksSub;

  @override
  void initState() {
    super.initState();
    _linksSub = widget.links?.listen(_onLink);
  }

  @override
  void dispose() {
    _linksSub?.cancel();
    super.dispose();
  }

  /// A playlist link (YouTube or Spotify) is imported and opened in Biblioteka; a YouTube video
  /// link is played (recognised as a MusicDatabase song where possible) in the full player.
  Future<void> _onLink(String text) async {
    // Whatever was open (a sheet, a dialog, the full player) gives way to the link.
    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    if (text.contains('spotify')) {
      if (extractSpotifyPlaylistId(text) != null ||
          findSpotifyShortLink(text) != null) {
        return _importAndOpen(text);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ze Spotify można tu otworzyć tylko playlistę.'),
        ),
      );
      return;
    }
    final link = parseYouTubeLink(text);
    switch (link) {
      case null:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'To nie jest link do filmu ani playlisty z YouTube ani do playlisty ze Spotify.',
            ),
          ),
        );
      case YouTubePlaylistLink(:final listId):
        await _importAndOpen(listId);
      case YouTubeVideoLink():
        await _playVideo(link);
    }
  }

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
    SearchScreen(),
    LibraryScreen(),
  ];

  void openDrawer() => _scaffoldKey.currentState!.openDrawer();

  void _openSettings() {
    _scaffoldKey.currentState!.closeDrawer();
    _navigatorKeys[_currentTab].currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  void _openRecents() {
    _scaffoldKey.currentState!.closeDrawer();
    _navigatorKeys[_currentTab].currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const RecentsScreen()),
    );
  }

  void _onTabTapped(int index) {
    if (index == _createTabIndex) {
      showCreateSheet(context, idPrefix: 'Utwórz');
      return;
    }
    if (index == _currentTab) {
      _navigatorKeys[index].currentState!.popUntil((route) => route.isFirst);
    } else {
      setState(() => _currentTab = index);
    }
  }

  void _onBack() {
    final scaffold = _scaffoldKey.currentState!;
    if (scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
      return;
    }
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
      child: Scaffold(
        key: _scaffoldKey,
        drawer: ProfileDrawer(
          onOpenSettings: _openSettings,
          onOpenRecents: _openRecents,
        ),
        body: IndexedStack(
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
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            _BottomBar(currentIndex: _currentTab, onTap: _onTabTapped),
          ],
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
