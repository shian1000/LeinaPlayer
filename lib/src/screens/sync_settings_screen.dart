import 'package:flutter/material.dart';

import '../data/account.dart';
import '../data/database_sync.dart';
import '../data/outbox.dart';
import '../data/sync_sources.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/feature_info.dart';
import 'account_screen.dart';
import 'database_download_tiles.dart';
import 'feature_infos.dart';
import 'github_source_screen.dart';
import 'outbox_settings_screen.dart';
import 'private_server_screen.dart';
import 'problems_screen.dart';
import 'sync_tiles.dart';

/// The name of each synced function, as Synchronizacja lists it.
String syncFeatureName(SyncFeature feature) => switch (feature) {
  SyncFeature.database => l10n.syncSettingsScreenDatabase,
  SyncFeature.library => l10n.syncSettingsScreenLibrary,
  SyncFeature.requests => l10n.syncSettingsScreenRequests,
  SyncFeature.errorReports => l10n.syncSettingsScreenErrorReports,
};

String _sourceName(SyncSource source) => switch (source) {
  SyncSource.gitHub => 'GitHub',
  SyncSource.leina => l10n.syncSettingsScreenLeinaServer,
  SyncSource.privateServer => l10n.syncSettingsScreenPrivateServer,
};

IconData _featureIcon(SyncFeature feature) => switch (feature) {
  SyncFeature.database => Icons.storage,
  SyncFeature.library => Icons.library_music_outlined,
  SyncFeature.requests => Icons.forward_to_inbox_outlined,
  SyncFeature.errorReports => Icons.bug_report_outlined,
};

IconData _sourceIcon(SyncSource source) => switch (source) {
  SyncSource.gitHub => Icons.public,
  SyncSource.leina => Icons.cloud_outlined,
  SyncSource.privateServer => Icons.dns_outlined,
};

/// "Ustawienia › Synchronizacja": every function the phone syncs, each opening its own sources.
class SyncSettingsScreen extends StatelessWidget {
  const SyncSettingsScreen({super.key});

  /// "Prywatny serwer → GitHub": the sources [feature] tries now, in order.
  static String summary(DatabaseSync sync, SyncFeature feature) {
    final names = [
      for (final source in sync.sources.enabled(feature))
        if (source != SyncSource.privateServer || sync.hasServer)
          _sourceName(source),
    ];
    return names.isEmpty
        ? l10n.syncSettingsScreenPhoneOnly
        : l10n.syncSettingsScreenSourcesAndPhone(names.join(' → '));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sync = DatabaseSyncScope.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.syncSettingsScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SyncEverythingTile(),
          for (final feature in SyncFeature.values)
            ListTile(
              leading: Icon(_featureIcon(feature), size: 28),
              title: Text(syncFeatureName(feature)),
              subtitle: Text(summary(sync, feature)),
              trailing: const Icon(Icons.chevron_right),
              onLongPress: feature == SyncFeature.requests
                  ? () => showFeatureInfo(context, FeatureInfos.outbox)
                  : null,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SyncSourcesScreen(feature: feature),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              l10n.syncSettingsScreenIntro,
              style: TextStyle(
                fontSize: AppFontSize.listSubtitle,
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One synced function's sources: switched on or off and moved in the order they are tried,
/// then the phone's own data ("Dane na telefonie"), and at the end how its last sync went
/// ("Ostatnia synchronizacja", the tiles Konto had).
class SyncSourcesScreen extends StatelessWidget {
  const SyncSourcesScreen({super.key, required this.feature});

  final SyncFeature feature;

  static Key rowKey(SyncSource source) =>
      ValueKey('sync.source.${source.name}');

  String get _intro => switch (feature) {
    SyncFeature.database => l10n.syncSettingsScreenDatabaseIntro,
    SyncFeature.library => l10n.syncSettingsScreenLibraryIntro,
    SyncFeature.requests => l10n.syncSettingsScreenRequestsIntro,
    SyncFeature.errorReports => l10n.syncSettingsScreenErrorReportsIntro,
  };

  String _subtitle(BuildContext context, DatabaseSync sync, SyncSource source) {
    if (!SyncSources.works(feature, source)) {
      return l10n.syncSettingsScreenNotWorkingYet;
    }
    return switch (source) {
      SyncSource.gitHub => sync.gitHubRepo,
      SyncSource.privateServer when !sync.hasServer =>
        l10n.syncSettingsScreenNoAddress,
      SyncSource.privateServer
          when feature == SyncFeature.library &&
              AccountScope.maybeOf(context)?.loggedIn == false =>
        l10n.syncSettingsScreenAddressSetLoggedOut,
      SyncSource.privateServer => l10n.syncSettingsScreenAddressSet,
      SyncSource.leina => l10n.syncSettingsScreenNotWorkingYet,
    };
  }

  void _open(BuildContext context, SyncSource source) {
    if (!SyncSources.works(feature, source)) return showWorkInProgress(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => switch (source) {
          SyncSource.gitHub => const GitHubSourceScreen(),
          _ => const PrivateServerScreen(),
        },
      ),
    );
  }

  Future<void> _switch(
    BuildContext context,
    DatabaseSync sync,
    SyncSource source,
    bool on,
  ) async {
    if (!SyncSources.works(feature, source)) return showWorkInProgress(context);
    if (feature == SyncFeature.database && source == SyncSource.gitHub) {
      await sync.setGitHubOn(on);
    } else {
      await sync.sources.setOn(feature, source, on);
    }
  }

  ({String subtitle, VoidCallback onTap, FeatureInfo? info}) _phone(
    BuildContext context,
  ) {
    void push(Widget screen) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen));
    final waiting = OutboxScope.maybeOf(context)?.waiting ?? 0;
    return switch (feature) {
      SyncFeature.database => (
        subtitle: l10n.syncSettingsScreenPhoneDatabase,
        onTap: () => showWorkInProgress(context),
        info: null,
      ),
      SyncFeature.library => (
        subtitle: l10n.syncSettingsScreenPhoneLibrary,
        onTap: () => showWorkInProgress(context),
        info: null,
      ),
      SyncFeature.requests => (
        subtitle: waiting == 0
            ? l10n.syncSettingsScreenPhoneRequestsNone
            : l10n.syncSettingsScreenPhoneRequestsWaiting(waiting),
        onTap: () => push(const OutboxSettingsScreen()),
        info: FeatureInfos.outbox,
      ),
      SyncFeature.errorReports => (
        subtitle: l10n.syncSettingsScreenPhoneProblems,
        onTap: () => push(const ProblemsScreen()),
        info: null,
      ),
    };
  }

  /// "Ostatnia synchronizacja": the same tiles as the function's own screens.
  List<Widget> _lastSync(BuildContext context) => switch (feature) {
    SyncFeature.database => const [DatabaseDownloadTiles()],
    SyncFeature.library =>
      AccountScope.maybeOf(context)?.loggedIn ?? false
          ? const [AccountSyncTile(), PhoneOnlyRows()]
          : [
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(l10n.syncSettingsScreenNotLoggedIn),
                subtitle: Text(l10n.syncSettingsScreenLibraryAfterLogin),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AccountScreen(),
                  ),
                ),
              ),
            ],
    SyncFeature.requests => [
      if (OutboxScope.maybeOf(context) != null) const OutboxSendTiles(),
    ],
    SyncFeature.errorReports => const [],
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sync = DatabaseSyncScope.of(context);
    final order = sync.sources.order(feature);
    final lastSync = _lastSync(context);
    final phone = _phone(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(syncFeatureName(feature)),
      ),
      // One scrollable for the page and the order, so dragging a row's handle isn't taken
      // for scrolling the page.
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    _intro,
                    style: TextStyle(
                      fontSize: AppFontSize.listSubtitle,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                SectionTitle(l10n.syncSettingsScreenSources),
              ],
            ),
          ),
          SliverReorderableList(
            itemCount: order.length,
            onReorderItem: (from, to) => sync.sources.move(feature, from, to),
            proxyDecorator: (child, _, _) =>
                Material(color: palette.surface, elevation: 4, child: child),
            itemBuilder: (context, index) {
              final source = order[index];
              return ListTile(
                key: rowKey(source),
                leading: Icon(_sourceIcon(source)),
                title: Text(_sourceName(source)),
                subtitle: Text(_subtitle(context, sync, source)),
                onTap: () => _open(context, source),
                onLongPress: source == SyncSource.privateServer
                    ? () => showFeatureInfo(context, FeatureInfos.server)
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: sync.sources.isOn(feature, source),
                      onChanged:
                          sync.downloading && feature == SyncFeature.database
                          ? null
                          : (on) => _switch(context, sync, source, on),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.drag_handle,
                          semanticLabel: l10n.syncSettingsScreenMove,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 24),
            sliver: SliverList.list(
              children: [
                SectionTitle(l10n.syncSettingsScreenPhoneData),
                ListTile(
                  leading: const Icon(Icons.smartphone),
                  title: Text(l10n.syncSettingsScreenPhone),
                  subtitle: Text(phone.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: phone.onTap,
                  onLongPress: phone.info == null
                      ? null
                      : () => showFeatureInfo(context, phone.info!),
                ),
                if (lastSync.isNotEmpty) ...[
                  SectionTitle(l10n.syncSettingsScreenLastSync),
                  ...lastSync,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
