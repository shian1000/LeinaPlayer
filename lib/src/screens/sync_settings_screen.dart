import 'package:flutter/material.dart';

import '../data/account.dart';
import '../data/database_sync.dart';
import '../data/outbox.dart';
import '../data/sync_sources.dart';
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
  SyncFeature.database => 'Baza danych',
  SyncFeature.library => 'Biblioteka użytkownika',
  SyncFeature.requests => 'Prośby do bazy danych',
  SyncFeature.errorReports => 'Raportowanie błędów',
};

String _sourceName(SyncSource source) => switch (source) {
  SyncSource.gitHub => 'GitHub',
  SyncSource.leina => 'Serwer Leina',
  SyncSource.privateServer => 'Prywatny serwer',
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

void _workInProgress(BuildContext context) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(const SnackBar(content: Text('Work in progress :)')));

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
    return names.isEmpty ? 'Tylko telefon' : '${names.join(' → ')} • telefon';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sync = DatabaseSyncScope.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Synchronizacja'),
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
              'Każda funkcja ma własne źródła: włączasz je przełącznikiem, a kolejność, w '
              'jakiej telefon ich próbuje, zmieniasz, przeciągając ≡. Dane na telefonie '
              'zostają zawsze.',
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
    SyncFeature.database =>
      'Skąd telefon pobiera bazę utworów — sam raz dziennie przy uruchomieniu albo przez '
          '„Pobierz teraz” na dole. Włączone źródła są próbowane od góry, aż któreś odpowie; '
          'GitHub daje tylko kopię nie starszą niż ta na telefonie.',
    SyncFeature.library =>
      'Z czym synchronizują się playlisty, nastroje, foldery, polubione, „Na później” i '
          'statystyki słuchania zalogowanego konta. Wyłączone — zostają tylko na telefonie.',
    SyncFeature.requests =>
      'Dokąd idą zgłoszenia poprawek i prośby o dodanie utworów. Bez włączonego serwera '
          'czekają na telefonie na „Wyślij paczkę…”.',
    SyncFeature.errorReports => 'Dokąd idą raporty o problemach. Na razie tylko z telefonu, przez „Udostępnij”.',
  };

  String _subtitle(BuildContext context, DatabaseSync sync, SyncSource source) {
    if (!SyncSources.works(feature, source)) return 'Jeszcze nie działa';
    return switch (source) {
      SyncSource.gitHub => sync.gitHubRepo,
      SyncSource.privateServer when !sync.hasServer => 'Nie ustawiono adresu',
      SyncSource.privateServer
          when feature == SyncFeature.library &&
              AccountScope.maybeOf(context)?.loggedIn == false =>
        'Adres ustawiony • niezalogowano (Ustawienia › Konto)',
      SyncSource.privateServer => 'Adres ustawiony',
      SyncSource.leina => 'Jeszcze nie działa',
    };
  }

  void _open(BuildContext context, SyncSource source) {
    if (!SyncSources.works(feature, source)) return _workInProgress(context);
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
    if (!SyncSources.works(feature, source)) return _workInProgress(context);
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
        subtitle: 'Kopia bazy na telefonie',
        onTap: () => _workInProgress(context),
        info: null,
      ),
      SyncFeature.library => (
        subtitle: 'Biblioteka zapisana na telefonie',
        onTap: () => _workInProgress(context),
        info: null,
      ),
      SyncFeature.requests => (
        subtitle: waiting == 0
            ? 'Zgłoszenia poprawek • nic nie czeka'
            : 'Zgłoszenia poprawek • czeka '
                  '${OutboxSettingsScreen.requestsLabel(waiting)}',
        onTap: () => push(const OutboxSettingsScreen()),
        info: FeatureInfos.outbox,
      ),
      SyncFeature.errorReports => (
        subtitle: 'Problemy • Zgłoś problem • Dziennik błędów',
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
                title: const Text('Nie zalogowano'),
                subtitle: const Text(
                  'Biblioteka synchronizuje się z kontem MusicDatabase po zalogowaniu',
                ),
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
                const SectionTitle('Źródła'),
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
                          semanticLabel: 'Przesuń',
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
                const SectionTitle('Dane na telefonie'),
                ListTile(
                  leading: const Icon(Icons.smartphone),
                  title: const Text('Telefon'),
                  subtitle: Text(phone.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: phone.onTap,
                  onLongPress: phone.info == null
                      ? null
                      : () => showFeatureInfo(context, phone.info!),
                ),
                if (lastSync.isNotEmpty) ...[
                  const SectionTitle('Ostatnia synchronizacja'),
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
