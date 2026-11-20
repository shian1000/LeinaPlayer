import 'package:flutter/material.dart';

import '../app_name.dart';
import '../data/sync_sources.dart';
import '../data/text_normalizer.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'about_screen.dart';
import 'account_screen.dart';
import 'appearance_screen.dart';
import 'backup_screen.dart';
import 'cache_settings_screen.dart';
import 'cover_sources_screen.dart';
import 'data_saver_screen.dart';
import 'github_source_screen.dart';
import 'history_settings_screen.dart';
import 'link_settings_screen.dart';
import 'local_music_screen.dart';
import 'outbox_settings_screen.dart';
import 'playback_settings_screen.dart';
import 'playback_sources_screen.dart';
import 'feature_infos.dart';
import 'privacy_screen.dart';
import 'private_server_screen.dart';
import 'problems_screen.dart';
import 'sync_settings_screen.dart';
import '../widgets/feature_info.dart';
import 'spotify_source_screen.dart';
import 'youtube_playback_screen.dart';
import 'youtube_source_screen.dart';

class _SettingsEntry {
  const _SettingsEntry(
    this.icon,
    this.title,
    this.subtitle,
    this.opens, {
    this.keywords = const [],
    this.deeper = const [],
    this.info,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder opens;

  /// Settings on its screen not named in [subtitle], found by "Wyszukaj ustawienie".
  final List<String> keywords;

  /// Screens opened from its screen, with their own settings.
  final List<_SettingsEntry> deeper;

  /// What a long press explains (a function: the texts aren't constants).
  final FeatureInfo Function()? info;
}

FeatureInfo _serverInfo() => FeatureInfos.server;

FeatureInfo _outboxInfo() => FeatureInfos.outbox;

/// The entries under their section headers.
List<(String, List<_SettingsEntry>)> get _sections => [
  (
    'MusicDatabase',
    [
      _SettingsEntry(
        Icons.account_circle_outlined,
        l10n.settingsScreenAccount,
        l10n.settingsScreenAccountSubtitle,
        _openAccount,
        keywords: [
          l10n.settingsScreenKwMusicDatabaseAccount,
          l10n.settingsScreenKwLogIn,
          l10n.settingsScreenKwLogOut,
          l10n.settingsScreenKwGoogleAccount,
        ],
      ),
      _SettingsEntry(
        Icons.sync,
        l10n.settingsScreenSync,
        l10n.settingsScreenSyncSubtitle,
        _openSync,
        keywords: [
          l10n.settingsScreenKwSyncEverything,
          l10n.settingsScreenKwLastSync,
          l10n.settingsScreenKwSyncSources,
          l10n.settingsScreenKwSourceOrder,
          l10n.settingsScreenKwLeinaServer,
          l10n.settingsScreenPrivateServer,
          l10n.settingsScreenKwPhone,
          l10n.settingsScreenKwPhoneData,
        ],
        deeper: [
          _SettingsEntry(
            Icons.storage,
            l10n.settingsScreenDatabase,
            l10n.settingsScreenDatabaseSubtitle,
            _openSyncDatabase,
            keywords: [
              l10n.settingsScreenKwDownloadFromGitHub,
              l10n.settingsScreenKwMusicCatalog,
              l10n.settingsScreenKwDownloadDatabase,
              l10n.settingsScreenKwEmptyServerDatabase,
            ],
            deeper: [
              _SettingsEntry(
                Icons.public,
                'GitHub',
                l10n.settingsScreenGitHubSubtitle,
                _openGitHub,
                keywords: [
                  l10n.settingsScreenKwGitHubRepository,
                  l10n.settingsScreenKwPublicDatabaseCopy,
                ],
              ),
              _SettingsEntry(
                Icons.dns_outlined,
                l10n.settingsScreenPrivateServer,
                l10n.settingsScreenPrivateServerSubtitle,
                _openPrivateServer,
                info: _serverInfo,
                keywords: [
                  l10n.settingsScreenKwServer,
                  l10n.settingsScreenKwMusicDatabaseServer,
                  l10n.settingsScreenKwRemoteAddress,
                  l10n.settingsScreenKwLocalAddress,
                  l10n.settingsScreenKwServerCertificate,
                  l10n.settingsScreenKwUseCurrentConnection,
                ],
              ),
            ],
          ),
          _SettingsEntry(
            Icons.library_music_outlined,
            l10n.settingsScreenUserLibrary,
            l10n.settingsScreenSyncSourcesSubtitle,
            _openSyncLibrary,
            keywords: [
              l10n.settingsScreenKwSyncAccount,
              l10n.settingsScreenKwListeningStats,
              l10n.settingsScreenKwPlaylistSync,
              l10n.settingsScreenKwMoodSync,
              l10n.settingsScreenKwListeningStatsSync,
            ],
          ),
          _SettingsEntry(
            Icons.forward_to_inbox_outlined,
            l10n.settingsScreenRequests,
            l10n.settingsScreenSyncSourcesSubtitle,
            _openSyncRequests,
            info: _outboxInfo,
            deeper: [
              _SettingsEntry(
                Icons.forward_to_inbox_outlined,
                l10n.settingsScreenOutbox,
                l10n.settingsScreenOutboxSubtitle,
                _openOutbox,
                info: _outboxInfo,
                keywords: [
                  l10n.settingsScreenKwSendAutomatically,
                  l10n.settingsScreenKwLastSend,
                  l10n.settingsScreenKwSendPackage,
                ],
              ),
            ],
          ),
          _SettingsEntry(
            Icons.bug_report_outlined,
            l10n.settingsScreenErrorReports,
            l10n.settingsScreenSyncSourcesSubtitle,
            _openSyncErrorReports,
            deeper: [
              _SettingsEntry(
                Icons.bug_report_outlined,
                l10n.settingsScreenProblems,
                l10n.settingsScreenProblemsSubtitle,
                _openProblems,
                keywords: [
                  l10n.settingsScreenKwProblemReport,
                  l10n.settingsScreenKwErrors,
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  (
    l10n.settingsScreenSectionListening,
    [
      _SettingsEntry(
        Icons.volume_up_outlined,
        l10n.settingsScreenPlayback,
        l10n.settingsScreenPlaybackSubtitle,
        _openPlayback,
        keywords: [
          l10n.settingsScreenKwHiddenSongs,
          l10n.settingsScreenKwTransitions,
          l10n.settingsScreenKwCrossfade,
          l10n.settingsScreenKwVolumeLeveling,
          l10n.settingsScreenKwVolumeNormalization,
          l10n.settingsScreenKwMeasureLoudness,
          l10n.settingsScreenKwSwipeRight,
        ],
        deeper: [
          _SettingsEntry(
            Icons.low_priority,
            l10n.settingsScreenPlaybackSources,
            l10n.settingsScreenPlaybackSourcesSubtitle,
            _openPlaybackSources,
            keywords: [
              l10n.settingsScreenKwPlaybackOrder,
              l10n.settingsScreenKwSourceOrder,
              l10n.settingsScreenKwEnableSource,
            ],
            deeper: [
              _SettingsEntry(
                Icons.folder_outlined,
                l10n.settingsScreenLocalMusic,
                l10n.settingsScreenLocalMusicSubtitle,
                _openLocalMusic,
                keywords: [
                  l10n.settingsScreenKwScanFolders,
                  l10n.settingsScreenKwNewSongsOutsideDatabase,
                  l10n.settingsScreenKwLastScan,
                ],
              ),
              _SettingsEntry(
                Icons.smart_display_outlined,
                l10n.settingsScreenYouTubePlayback,
                l10n.settingsScreenYouTubePlaybackSubtitle,
                _openYouTubePlayback,
                keywords: [l10n.settingsScreenKwOpenInYouTubeApp],
              ),
            ],
          ),
        ],
      ),
      _SettingsEntry(
        Icons.history,
        l10n.settingsScreenHistory,
        l10n.settingsScreenHistorySubtitle,
        _openHistory,
        keywords: [l10n.settingsScreenKwKeepHistory],
      ),
    ],
  ),
  (
    l10n.settingsScreenSectionSearchImport,
    [
      _SettingsEntry(
        Icons.smart_display_outlined,
        'YouTube',
        l10n.settingsScreenYouTubeSubtitle,
        _openYouTube,
        keywords: [
          l10n.settingsScreenKwEnableYouTubeSearch,
          l10n.settingsScreenKwSearchYouTubePlaylists,
        ],
      ),
      _SettingsEntry(
        Icons.graphic_eq,
        'Spotify',
        l10n.settingsScreenSpotifySubtitle,
        _openSpotify,
        keywords: [
          l10n.settingsScreenKwPlaylistImport,
          l10n.settingsScreenKwSearchSpotifyPlaylists,
        ],
      ),
    ],
  ),
  (
    l10n.settingsScreenSectionDisplay,
    [
      _SettingsEntry(
        Icons.palette_outlined,
        l10n.settingsScreenAppearance,
        l10n.settingsScreenAppearanceSubtitle,
        _openAppearance,
        keywords: [
          l10n.settingsScreenKwLightTheme,
          l10n.settingsScreenKwDarkTheme,
          l10n.settingsScreenKwSystemDarkMode,
          l10n.settingsScreenKwLatinNames,
          l10n.settingsScreenKwLyricsTransliteration,
          l10n.settingsScreenKwCoverFilters,
        ],
      ),
      _SettingsEntry(
        Icons.album_outlined,
        l10n.settingsScreenCoverSources,
        l10n.settingsScreenCoverSourcesSubtitle,
        _openCoverSources,
        keywords: [l10n.settingsScreenKwCoverSources],
      ),
    ],
  ),
  (
    l10n.settingsScreenSectionData,
    [
      _SettingsEntry(
        Icons.download_for_offline_outlined,
        l10n.settingsScreenDataSaver,
        l10n.settingsScreenDataSaverSubtitle,
        _openDataSaver,
        deeper: [
          _SettingsEntry(
            Icons.sd_storage_outlined,
            l10n.settingsScreenCache,
            l10n.settingsScreenCacheSubtitle,
            _openCache,
            keywords: [
              l10n.settingsScreenKwDownloadedSongs,
              l10n.settingsScreenKwDeleteAllDownloads,
              l10n.settingsScreenKwQueueCacheCount,
              l10n.settingsScreenKwCoverCacheSize,
              l10n.settingsScreenKwClearCovers,
              l10n.settingsScreenKwClearYouTubeSongs,
              l10n.settingsScreenKwClearEverything,
              l10n.settingsScreenKwYouTubeMatches,
              l10n.settingsScreenKwForgetMatchedVideos,
              l10n.settingsScreenKwForgetNotFound,
            ],
          ),
        ],
        keywords: [
          l10n.settingsScreenKwCoversOnlyOnWifi,
          l10n.settingsScreenKwDownloadLyrics,
          l10n.settingsScreenKwDownloadLocation,
          l10n.settingsScreenKwDownloadFolder,
          l10n.settingsScreenKwDownloadAsMp3,
          l10n.settingsScreenKwSdCard,
        ],
      ),
      _SettingsEntry(
        Icons.settings_backup_restore,
        l10n.settingsScreenBackup,
        l10n.settingsScreenBackupSubtitle,
        _openBackup,
        keywords: [
          l10n.settingsScreenKwMakeBackup,
          l10n.settingsScreenKwRestoreFromFile,
          l10n.settingsScreenKwDataExport,
          l10n.settingsScreenKwDataImport,
          l10n.settingsScreenKwNewPhone,
        ],
      ),
    ],
  ),
  (
    l10n.settingsScreenSectionApp,
    [
      _SettingsEntry(
        Icons.link,
        l10n.settingsScreenLinks,
        l10n.settingsScreenLinksSubtitle,
        _openLinks,
        keywords: [
          l10n.settingsScreenKwYouTubeLinks,
          l10n.settingsScreenKwSpotifyLinks,
          l10n.settingsScreenKwOpenLinksIn(appName),
        ],
      ),
      _SettingsEntry(
        Icons.privacy_tip_outlined,
        l10n.settingsScreenPrivacy,
        l10n.settingsScreenPrivacySubtitle,
        _openPrivacy,
        keywords: [
          l10n.settingsScreenKwPrivacy,
          l10n.settingsScreenKwInternetConnections,
          l10n.settingsScreenKwWhoSeesMyData,
          'NewPipe',
          'LRCLIB',
        ],
      ),
      _SettingsEntry(
        Icons.info_outline,
        l10n.settingsScreenAbout,
        l10n.settingsScreenAboutSubtitle,
        _openAbout,
        keywords: [
          l10n.settingsScreenKwAppVersion,
          l10n.settingsScreenKwUpdates,
          l10n.settingsScreenKwCheckUpdatesAutomatically,
          l10n.settingsScreenKwLibraryLicenses,
          l10n.settingsScreenKwPrivateUseOnly,
        ],
      ),
    ],
  ),
];

Widget _openAccount(BuildContext context) => const AccountScreen();

Widget _openSync(BuildContext context) => const SyncSettingsScreen();

Widget _openSyncDatabase(BuildContext context) =>
    const SyncSourcesScreen(feature: SyncFeature.database);

Widget _openSyncLibrary(BuildContext context) =>
    const SyncSourcesScreen(feature: SyncFeature.library);

Widget _openSyncRequests(BuildContext context) =>
    const SyncSourcesScreen(feature: SyncFeature.requests);

Widget _openSyncErrorReports(BuildContext context) =>
    const SyncSourcesScreen(feature: SyncFeature.errorReports);

Widget _openGitHub(BuildContext context) => const GitHubSourceScreen();

Widget _openPrivateServer(BuildContext context) => const PrivateServerScreen();

Widget _openProblems(BuildContext context) => const ProblemsScreen();

Widget _openOutbox(BuildContext context) => const OutboxSettingsScreen();

Widget _openPlayback(BuildContext context) => const PlaybackSettingsScreen();

Widget _openPlaybackSources(BuildContext context) =>
    const PlaybackSourcesScreen();

Widget _openLocalMusic(BuildContext context) => const LocalMusicScreen();

Widget _openYouTubePlayback(BuildContext context) =>
    const YouTubePlaybackScreen();

Widget _openHistory(BuildContext context) => const HistorySettingsScreen();

Widget _openYouTube(BuildContext context) => const YouTubeSourceScreen();

Widget _openSpotify(BuildContext context) => const SpotifySourceScreen();

Widget _openAppearance(BuildContext context) => const AppearanceScreen();

Widget _openCoverSources(BuildContext context) => const CoverSourcesScreen();

Widget _openDataSaver(BuildContext context) => const DataSaverScreen();

Widget _openCache(BuildContext context) => const CacheSettingsScreen();

Widget _openBackup(BuildContext context) => const BackupScreen();

Widget _openLinks(BuildContext context) => const LinkSettingsScreen();

Widget _openAbout(BuildContext context) => const AboutScreen();

Widget _openPrivacy(BuildContext context) => const PrivacyScreen();

/// "Ustawienia", opened from "Ja".
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.settingsScreenTitle),
        actions: [
          IconButton(
            tooltip: l10n.settingsScreenSearchHint,
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _SettingsSearch()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final (header, entries) in _sections) ...[
            SectionTitle(header),
            for (final entry in entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
                visualDensity: const VisualDensity(vertical: -1),
                leading: Icon(entry.icon, size: 28),
                title: Text(entry.title),
                subtitle: Text(entry.subtitle),
                onLongPress: entry.info == null
                    ? null
                    : () => showFeatureInfo(context, entry.info!()),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: entry.opens)),
              ),
          ],
        ],
      ),
    );
  }
}

/// A setting found by "Wyszukaj ustawienie": its name, where it is, and the screen to open.
typedef _Found = ({String label, String path, _SettingsEntry entry});

List<_Found> _searchSettings(String query) {
  final wanted = normalizeForSearch(query);
  if (wanted.isEmpty) return const [];
  final found = <_Found>[];
  void visit(_SettingsEntry entry, String path) {
    final here = '$path › ${entry.title}';
    final labels = {
      entry.title,
      ...entry.subtitle.split(' • '),
      ...entry.keywords,
    }.difference({for (final inner in entry.deeper) inner.title});
    for (final label in labels) {
      if (normalizeForSearch(label).contains(wanted)) {
        found.add((
          label: label,
          path: label == entry.title ? path : here,
          entry: entry,
        ));
      }
    }
    for (final inner in entry.deeper) {
      visit(inner, here);
    }
  }

  for (final (header, entries) in _sections) {
    for (final entry in entries) {
      visit(entry, l10n.settingsScreenSearchPath(header));
    }
  }
  return found;
}

/// "Wyszukaj ustawienie": every setting whose name has the query, opening its screen.
class _SettingsSearch extends StatefulWidget {
  const _SettingsSearch();

  @override
  State<_SettingsSearch> createState() => _SettingsSearchState();
}

class _SettingsSearchState extends State<_SettingsSearch> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final found = _searchSettings(_query);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: TextField(
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.settingsScreenSearchHint,
            border: InputBorder.none,
          ),
          onChanged: (text) => setState(() => _query = text),
        ),
      ),
      body: _query.trim().isNotEmpty && found.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
              child: Text(
                l10n.settingsScreenNoSetting(_query.trim()),
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
            )
          : ListView(
              children: [
                for (final hit in found)
                  ListTile(
                    leading: Icon(hit.entry.icon),
                    title: Text(hit.label),
                    subtitle: Text(hit.path),
                    onTap: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: hit.entry.opens)),
                  ),
              ],
            ),
    );
  }
}
