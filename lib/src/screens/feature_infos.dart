import 'package:flutter/material.dart';

import '../data/youtube_account.dart';
import '../l10n.dart';
import '../widgets/feature_info.dart';
import 'account_screen.dart';
import 'privacy_screen.dart';

// The long-press explanations (sharing checklist 5.2), reviewed by the owner before going in.
// Keep them true to the code: a change to how one of these works updates its text here.

void _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

FeatureInfoAction get _privacy => FeatureInfoAction(
  Icons.privacy_tip_outlined,
  l10n.featureInfosActionPrivacy,
  (context) => _push(context, const PrivacyScreen()),
);

FeatureInfoAction get _account => FeatureInfoAction(
  Icons.account_circle_outlined,
  l10n.featureInfosActionAccount,
  (context) => _push(context, const AccountScreen()),
);

FeatureInfoAction get _signOutGoogle => FeatureInfoAction(
  Icons.logout,
  l10n.featureInfosActionSignOutGoogle,
  (context) => YouTubeAccountScope.maybeOf(context)?.signOut(),
);

/// Every element with a long-press explanation, by what it explains.
abstract final class FeatureInfos {
  static FeatureInfo get googleAccount => FeatureInfo(
    title: l10n.featureInfosGoogleAccountTitle,
    what: l10n.featureInfosGoogleAccountWhat,
    why: l10n.featureInfosGoogleAccountWhy,
    how: l10n.featureInfosGoogleAccountHow,
    libraries: l10n.featureInfosGoogleAccountLibraries,
    connects: l10n.featureInfosGoogleAccountConnects,
    actions: [_signOutGoogle, _privacy],
  );

  static FeatureInfo get listeningStats => FeatureInfo(
    title: l10n.featureInfosListeningStatsTitle,
    what: l10n.featureInfosListeningStatsWhat,
    why: l10n.featureInfosListeningStatsWhy,
    how: l10n.featureInfosListeningStatsHow,
    libraries: l10n.featureInfosListeningStatsLibraries,
    connects: l10n.featureInfosListeningStatsConnects,
    actions: [_account, _privacy],
  );

  static FeatureInfo get server => FeatureInfo(
    title: l10n.featureInfosServerTitle,
    what: l10n.featureInfosServerWhat,
    why: l10n.featureInfosServerWhy,
    how: l10n.featureInfosServerHow,
    libraries: 'HttpClient (Dart), network_info_plus, permission_handler',
    connects: l10n.featureInfosServerConnects,
    actions: [_privacy],
  );

  static FeatureInfo get outbox => FeatureInfo(
    title: l10n.featureInfosOutboxTitle,
    what: l10n.featureInfosOutboxWhat,
    why: l10n.featureInfosOutboxWhy,
    how: l10n.featureInfosOutboxHow,
    libraries: l10n.featureInfosOutboxLibraries,
    connects: l10n.featureInfosOutboxConnects,
    actions: [_privacy],
  );

  static FeatureInfo get newPipePlayback => FeatureInfo(
    title: l10n.featureInfosNewPipePlaybackTitle,
    what: l10n.featureInfosNewPipePlaybackWhat,
    why: l10n.featureInfosNewPipePlaybackWhy,
    how: l10n.featureInfosNewPipePlaybackHow,
    libraries: l10n.featureInfosNewPipePlaybackLibraries,
    connects: l10n.featureInfosNewPipePlaybackConnects,
    actions: [_privacy],
  );

  static FeatureInfo get explodePlayback => FeatureInfo(
    title: l10n.featureInfosExplodePlaybackTitle,
    what: l10n.featureInfosExplodePlaybackWhat,
    why: l10n.featureInfosExplodePlaybackWhy,
    how: l10n.featureInfosExplodePlaybackHow,
    libraries: 'youtube_explode_dart',
    connects: l10n.featureInfosExplodePlaybackConnects,
    actions: [_privacy],
  );

  static FeatureInfo get newPipeSearch => FeatureInfo(
    title: l10n.featureInfosNewPipeSearchTitle,
    what: l10n.featureInfosNewPipeSearchWhat,
    why: l10n.featureInfosNewPipeSearchWhy,
    how: l10n.featureInfosNewPipeSearchHow,
    libraries: 'NewPipeExtractor (Java, GPLv3)',
    connects: l10n.featureInfosNewPipeSearchConnects,
    actions: [_privacy],
  );

  static FeatureInfo get explodeSearch => FeatureInfo(
    title: l10n.featureInfosExplodeSearchTitle,
    what: l10n.featureInfosExplodeSearchWhat,
    why: l10n.featureInfosExplodeSearchWhy,
    how: l10n.featureInfosExplodeSearchHow,
    libraries: 'youtube_explode_dart',
    connects: l10n.featureInfosExplodeSearchConnects,
    actions: [_privacy],
  );

  static FeatureInfo get youTubeApi => FeatureInfo(
    title: 'YouTube Data API',
    note: l10n.featureInfosYouTubeApiNote,
    what: l10n.featureInfosYouTubeApiWhat,
    why: l10n.featureInfosYouTubeApiWhy,
    how: l10n.featureInfosYouTubeApiHow,
    libraries: 'YouTube Data API v3 (HTTP)',
    connects: l10n.featureInfosYouTubeApiConnects,
    actions: [_privacy],
  );

  static FeatureInfo get spotifyApi => FeatureInfo(
    title: 'Spotify API',
    note: l10n.featureInfosSpotifyApiNote,
    what: l10n.featureInfosSpotifyApiWhat,
    why: l10n.featureInfosSpotifyApiWhy,
    how: l10n.featureInfosSpotifyApiHow,
    libraries: 'Spotify Web API (HTTP)',
    connects: l10n.featureInfosSpotifyApiConnects,
    actions: [_privacy],
  );

  static FeatureInfo get accountSync => FeatureInfo(
    title: l10n.featureInfosAccountSyncTitle,
    what: l10n.featureInfosAccountSyncWhat,
    why: l10n.featureInfosAccountSyncWhy,
    how: l10n.featureInfosAccountSyncHow,
    connects: l10n.featureInfosAccountSyncConnects,
    actions: [_privacy],
  );

  static FeatureInfo get home => FeatureInfo(
    title: l10n.featureInfosHomeTitle,
    what: l10n.featureInfosHomeWhat,
    why: l10n.featureInfosHomeWhy,
    how: l10n.featureInfosHomeHow,
    actions: [_privacy],
  );

  static FeatureInfo get discover => FeatureInfo(
    title: l10n.featureInfosDiscoverTitle,
    what: l10n.featureInfosDiscoverWhat,
    why: l10n.featureInfosDiscoverWhy,
    how: l10n.featureInfosDiscoverHow,
    actions: [_privacy],
  );

  static FeatureInfo get songRadio => FeatureInfo(
    title: l10n.featureInfosSongRadioTitle,
    what: l10n.featureInfosSongRadioWhat,
    why: l10n.featureInfosSongRadioWhy,
    how: l10n.featureInfosSongRadioHow,
    actions: [_privacy],
  );
}
