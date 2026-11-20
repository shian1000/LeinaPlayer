import 'package:flutter/material.dart';

import '../data/account.dart';
import '../data/app_updates.dart';
import '../data/database_sync.dart';
import '../data/later_links.dart';
import '../data/library_folders.dart';
import '../data/listening_log.dart';
import '../data/moods.dart';
import '../data/outbox.dart';
import '../data/playlist_library.dart';
import '../data/playlist_sync.dart';
import '../data/saved_songs.dart';
import '../data/sync_sources.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/feature_info.dart';
import 'feature_infos.dart';

/// One part of the account that syncs with MusicDatabase.
typedef _SyncPart = ({
  String name,
  bool syncing,
  PlaylistSyncResult? Function() last,
  Future<void> Function() sync,
});

/// Every part of the account that syncs with MusicDatabase, for [AccountSyncTile] and
/// [SyncEverythingTile].
List<_SyncPart> _accountSyncParts(BuildContext context) {
  // Read here, not in servers(): the parts sync one after another, and once the user has
  // left the screen the context can no longer look scopes up (Pixel, 2026-10-30).
  final databaseSync = DatabaseSyncScope.of(context);
  final account = AccountScope.of(context);
  Future<List<Uri>> servers() =>
      databaseSync.serverAddressesFor(SyncFeature.library);
  final playlists = PlaylistLibraryScope.maybeOf(context);
  final moods = MoodLibraryScope.maybeOf(context);
  final folders = LibraryFoldersScope.maybeOf(context);
  final listens = ListeningLogScope.maybeOf(context);
  final songs = SavedSongsSyncScope.maybeOf(context);
  final links = LaterLinksScope.maybeOf(context);
  return <_SyncPart>[
    if (playlists != null)
      (
        name: l10n.syncTilesPlaylists,
        syncing: playlists.syncing,
        last: () => playlists.lastSync,
        sync: () async => playlists.sync(await servers()),
      ),
    if (moods != null)
      (
        name: l10n.syncTilesMoods,
        syncing: moods.syncing,
        last: () => moods.lastSync,
        sync: () async {
          final addresses = await servers();
          await account.refreshPermissions(addresses);
          await moods.sync(addresses);
        },
      ),
    if (folders != null)
      (
        name: l10n.syncTilesFolders,
        syncing: folders.syncing,
        last: () => folders.lastSync,
        sync: () async => folders.sync(await servers()),
      ),
    if (listens != null)
      (
        name: l10n.syncTilesListeningStats,
        syncing: listens.syncing,
        last: () => listens.lastSync,
        sync: () async => listens.sync(await servers()),
      ),
    if (songs != null)
      (
        name: l10n.syncTilesSavedSongs,
        syncing: songs.syncing,
        last: () => songs.lastSync,
        sync: () async => songs.sync(await servers()),
      ),
    if (links != null)
      (
        name: l10n.syncTilesLaterLinks,
        syncing: links.syncing,
        last: () => links.lastSync,
        sync: () async => links.sync(await servers()),
      ),
  ];
}

/// "Synchronizuj konto": every part of the account that syncs with MusicDatabase (playlists, moods,
/// folders, plays, liked and saved songs, links saved for later) in one row — how it last went
/// and ⟳ to sync it all now; a long press explains what syncs where.
class AccountSyncTile extends StatelessWidget {
  const AccountSyncTile({super.key});

  @override
  Widget build(BuildContext context) {
    final parts = _accountSyncParts(context);
    if (parts.isEmpty) return const SizedBox.shrink();

    final error = Theme.of(context).colorScheme.error;
    String two(int n) => n.toString().padLeft(2, '0');
    final syncing = parts.any((p) => p.syncing);
    final failed = [
      for (final p in parts)
        if (p.last()?.problem != null) p,
    ];
    final done = [for (final p in parts) p.last()?.at].nonNulls.toList()
      ..sort();
    final String subtitle;
    if (syncing) {
      subtitle = l10n.syncTilesSyncing;
    } else if (failed.isNotEmpty) {
      subtitle = l10n.syncTilesPartsFailed(
        failed.map((p) => p.name).join(', '),
        failed.first.last()!.problem!,
      );
    } else if (done.isEmpty) {
      subtitle = l10n.syncTilesNeverSynced;
    } else {
      // The oldest one: everything has synced at least since then.
      final at = done.first;
      subtitle = l10n.syncTilesAllSynced('${two(at.hour)}:${two(at.minute)}');
    }

    return ListTile(
      leading: Icon(
        failed.isEmpty ? Icons.sync : Icons.sync_problem,
        color: failed.isEmpty ? null : error,
      ),
      title: Text(l10n.syncTilesSyncAccount),
      subtitle: Text(subtitle),
      onLongPress: () => showFeatureInfo(context, FeatureInfos.accountSync),
      trailing: IconButton(
        tooltip: l10n.syncTilesSyncNow,
        icon: const Icon(Icons.refresh),
        onPressed: syncing
            ? null
            : () async {
                for (final part in parts) {
                  await part.sync();
                }
              },
      ),
    );
  }
}

/// "Synchronizuj wszystko", on top of Synchronizacja: the account's library, the catalog,
/// sending the waiting requests and the update check, one after another — each as its own tile
/// at the end of its function's screen does it, from the sources switched on there.
class SyncEverythingTile extends StatefulWidget {
  const SyncEverythingTile({super.key});

  @override
  State<SyncEverythingTile> createState() => SyncEverythingTileState();
}

class SyncEverythingTileState extends State<SyncEverythingTile> {
  bool _running = false;
  List<String>? _failed;
  DateTime? _finishedAt;

  Future<void> _syncEverything() async {
    // Everything is looked up before the first await (see [_accountSyncParts]).
    final loggedIn = AccountScope.maybeOf(context)?.loggedIn ?? false;
    final catalog = DatabaseSyncScope.of(context);
    final parts = loggedIn && catalog.usesServer(SyncFeature.library)
        ? _accountSyncParts(context)
        : <_SyncPart>[];
    final outbox = OutboxScope.maybeOf(context);
    final updates = AppUpdatesScope.maybeOf(context);
    setState(() {
      _running = true;
      _failed = null;
    });
    final failed = <String>[];
    try {
      for (final part in parts) {
        await part.sync();
      }
      if (parts.any((p) => p.last()?.problem != null)) {
        failed.add(l10n.syncTilesFailedLibrary);
      }
      if (catalog.hasSource && !await catalog.syncNow()) {
        failed.add(l10n.syncTilesFailedDatabase);
      }
      if (outbox != null &&
          outbox.waiting > 0 &&
          catalog.usesServer(SyncFeature.requests)) {
        final sent = await outbox.send(
          await catalog.serverAddresses(),
          manual: true,
        );
        if (sent.problem != null) failed.add(l10n.syncTilesFailedRequests);
      }
      if (updates != null && updates.configured) {
        await updates.check();
        if (updates.problem != null) failed.add(l10n.syncTilesFailedUpdates);
      }
    } catch (e) {
      debugPrint('Syncing everything failed: $e');
      failed.add(l10n.syncTilesError('$e'));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _failed = failed;
          _finishedAt = DateTime.now();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final error = Theme.of(context).colorScheme.error;
    final failed = _failed;
    final at = _finishedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final sync = DatabaseSyncScope.of(context);
    final parts = [
      if ((AccountScope.maybeOf(context)?.loggedIn ?? false) &&
          sync.usesServer(SyncFeature.library))
        l10n.syncTilesPartLibrary,
      if (sync.hasSource) l10n.syncTilesPartDatabase,
      if (OutboxScope.maybeOf(context) != null &&
          sync.usesServer(SyncFeature.requests))
        l10n.syncTilesPartRequests,
      if (AppUpdatesScope.maybeOf(context)?.configured ?? false)
        l10n.syncTilesPartUpdates,
    ];
    final covers = parts.isEmpty
        ? l10n.syncTilesNothing
        : parts.length == 1
        ? parts.single
        : l10n.syncTilesListAnd(
            parts.sublist(0, parts.length - 1).join(', '),
            parts.last,
          );
    final String subtitle;
    if (_running) {
      subtitle = l10n.syncTilesSyncing;
    } else if (failed != null && failed.isNotEmpty) {
      subtitle = l10n.syncTilesEverythingFailed(failed.join(', '));
    } else if (failed != null && at != null) {
      subtitle = l10n.syncTilesSyncedAt('${two(at.hour)}:${two(at.minute)}');
    } else {
      subtitle = '${covers[0].toUpperCase()}${covers.substring(1)}';
    }
    final problem = failed != null && failed.isNotEmpty && !_running;
    return ListTile(
      enabled: !_running,
      leading: Icon(
        problem ? Icons.sync_problem : Icons.cloud_sync_outlined,
        color: problem ? error : palette.accent,
      ),
      title: Text(
        l10n.syncTilesSyncEverything,
        style: TextStyle(color: palette.accent, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(subtitle, style: problem ? TextStyle(color: error) : null),
      trailing: _running
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _running ? null : _syncEverything,
    );
  }
}

/// "Playlisty / Nastroje / Foldery tylko na tym telefonie: N": made before logging in (or
/// before they synced), added to the account when tapped.
class PhoneOnlyRows extends StatelessWidget {
  const PhoneOnlyRows({super.key});

  @override
  Widget build(BuildContext context) {
    final playlists = PlaylistLibraryScope.maybeOf(context);
    final moods = MoodLibraryScope.maybeOf(context);
    final folders = LibraryFoldersScope.maybeOf(context);
    final playlistCount =
        playlists?.playlists.where((p) => p.account == null).length ?? 0;
    final moodCount = moods?.phoneOnlyCount ?? 0;
    final folderCount = folders?.phoneOnlyCount ?? 0;
    Widget row(String title, VoidCallback onTap) => ListTile(
      leading: const Icon(Icons.phone_android),
      title: Text(title),
      subtitle: Text(l10n.syncTilesPhoneOnlyTap),
      onTap: onTap,
    );
    return Column(
      children: [
        if (playlistCount > 0)
          row(
            l10n.syncTilesPhoneOnlyPlaylists(playlistCount),
            playlists!.addPhoneOnlyToAccount,
          ),
        if (moodCount > 0)
          row(
            l10n.syncTilesPhoneOnlyMoods(moodCount),
            moods!.addPhoneOnlyToAccount,
          ),
        if (folderCount > 0)
          row(
            l10n.syncTilesPhoneOnlyFolders(folderCount),
            folders!.addPhoneOnlyToAccount,
          ),
      ],
    );
  }
}
