import 'package:flutter/material.dart';

import '../data/account.dart';
import '../data/app_updates.dart';
import '../data/database_sync.dart';
import '../data/source_settings.dart';
import '../data/sync_sources.dart';
import '../data/youtube_account.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'about_screen.dart';
import 'account_screen.dart';
import 'cache_settings_screen.dart';
import 'cover_sources_screen.dart';
import 'data_saver_screen.dart';
import 'private_server_screen.dart';
import 'sync_settings_screen.dart';
import 'playback_sources_screen.dart';
import 'spotify_source_screen.dart';
import 'youtube_source_screen.dart';
import '../l10n.dart';

/// "Ustawienia › Prywatność i połączenia": who the app talks to, why, when and what they get,
/// each with a way to the switch that stops it — or a note that it only happens when the user
/// does it. Mirrors the connections the code makes (no analytics, ads or crash reports).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sync = DatabaseSyncScope.maybeOf(context);
    final account = AccountScope.maybeOf(context);
    final settings = SourceSettingsScope.maybeOf(context);
    final updates = AppUpdatesScope.maybeOf(context);
    final google = YouTubeAccountScope.maybeOf(context);
    final userName = account?.userName;

    Widget text(String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        value,
        style: TextStyle(
          fontSize: AppFontSize.body,
          color: strong ? palette.textPrimary : palette.textSecondary,
        ),
      ),
    );
    // The accent while the service is reached, the theme's error red while it isn't.
    Widget status(bool connects, String value) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Text(
        l10n.privacyScreenNow(value),
        style: TextStyle(
          fontSize: AppFontSize.small,
          color: connects
              ? palette.accent
              : Theme.of(context).colorScheme.error,
        ),
      ),
    );
    Widget statusOf(List<String> what) => what.isEmpty
        ? status(false, l10n.privacyScreenNotConnecting)
        : status(true, l10n.privacyScreenConnectsInternet(what.join(', ')));
    Widget onlyWhenUsed([String? what]) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 18,
            color: palette.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              what ?? l10n.privacyScreenOnlyWhenUsed,
              style: TextStyle(
                fontSize: AppFontSize.small,
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
    Widget goTo(String label, Widget Function() screen) => ListTile(
      dense: true,
      leading: Icon(Icons.tune, color: palette.accent),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => screen())),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.privacyScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          text(l10n.privacyScreenIntro, strong: true),
          text(l10n.privacyScreenLocalOnly),

          SectionTitle(l10n.privacyScreenServerSection),
          text(l10n.privacyScreenServerText),
          if (sync != null)
            sync.hasServer
                ? status(
                    true,
                    userName != null
                        ? l10n.privacyScreenServerSignedIn(userName)
                        : l10n.privacyScreenServerAnonymous,
                  )
                : status(false, l10n.privacyScreenServerNone),
          goTo(
            l10n.privacyScreenGoServerAddresses,
            () => const PrivateServerScreen(),
          ),
          goTo(l10n.privacyScreenGoSync, () => const SyncSettingsScreen()),
          goTo(l10n.privacyScreenGoAccount, () => const AccountScreen()),

          const SectionTitle('GitHub'),
          text(l10n.privacyScreenGitHubText),
          if (sync != null)
            statusOf([
              if (sync.gitHubOn) l10n.privacyScreenStatusDatabase,
              if (updates != null && updates.configured && updates.autoCheck)
                l10n.privacyScreenStatusUpdates,
            ]),
          goTo(
            l10n.privacyScreenGoGitHub,
            () => const SyncSourcesScreen(feature: SyncFeature.database),
          ),
          if (updates != null && updates.configured)
            goTo(l10n.privacyScreenGoUpdates, () => const AboutScreen()),

          const SectionTitle('YouTube'),
          text(l10n.privacyScreenYouTubeText),
          if (settings != null)
            statusOf([
              if (settings.enabledSources.contains(PlaybackSource.youtube))
                l10n.privacyScreenStatusPlayback,
              if (settings.youTubeSearchEnabled) l10n.privacyScreenStatusSearch,
            ]),
          goTo(
            l10n.privacyScreenGoPlaybackSources,
            () => const PlaybackSourcesScreen(),
          ),
          goTo(l10n.privacyScreenGoYouTube, () => const YouTubeSourceScreen()),
          goTo(l10n.privacyScreenGoCache, () => const CacheSettingsScreen()),

          SectionTitle(l10n.privacyScreenGoogleSection),
          text(l10n.privacyScreenGoogleText),
          if (google?.email case final email?) ...[
            status(true, l10n.privacyScreenGoogleSignedIn(email)),
            goTo(
              l10n.privacyScreenGoGoogleSignOut,
              () => const AccountScreen(),
            ),
          ] else if (google != null && !google.supported)
            status(false, l10n.privacyScreenGoogleUnsupported)
          else ...[
            status(false, l10n.privacyScreenGoogleSignedOut),
            onlyWhenUsed(l10n.privacyScreenGoogleOnlyWhenUsed),
          ],

          const SectionTitle('Spotify'),
          text(l10n.privacyScreenSpotifyText),
          if (settings != null)
            statusOf([
              if (settings.spotifyPlaylistSearch)
                l10n.privacyScreenStatusPlaylistSearch,
            ]),
          goTo(l10n.privacyScreenGoSpotify, () => const SpotifySourceScreen()),
          onlyWhenUsed(l10n.privacyScreenSpotifyOnlyWhenUsed),

          SectionTitle(l10n.privacyScreenCoversSection),
          text(l10n.privacyScreenCoversText),
          if (settings != null)
            statusOf([
              for (final source in settings.activeCoverSources)
                if (source == CoverSource.itunes ||
                    source == CoverSource.deezer ||
                    source == CoverSource.youtube)
                  source.label,
              if (settings.coverWifiOnly &&
                  settings.activeCoverSources.any(
                    (s) => s != CoverSource.file && s != CoverSource.server,
                  ))
                l10n.privacyScreenStatusWifiOnly,
            ]),
          goTo(
            l10n.privacyScreenGoCoverSources,
            () => const CoverSourcesScreen(),
          ),
          goTo(l10n.privacyScreenGoCoversWifi, () => const DataSaverScreen()),

          SectionTitle(l10n.privacyScreenLyricsSection),
          text(l10n.privacyScreenLyricsText),
          if (settings != null) statusOf([if (settings.lyrics) 'LRCLIB']),
          goTo(l10n.privacyScreenGoLyrics, () => const DataSaverScreen()),

          SectionTitle(l10n.privacyScreenBrowserSection),
          text(l10n.privacyScreenBrowserText),
          status(false, l10n.privacyScreenBrowserNotConnecting),
          onlyWhenUsed(),

          SectionTitle(l10n.privacyScreenSyncSection),
          text(l10n.privacyScreenSyncText),
        ],
      ),
    );
  }
}
