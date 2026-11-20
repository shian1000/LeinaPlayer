import 'package:flutter/material.dart';

import '../data/database_sync.dart';
import '../theme.dart';
import '../l10n.dart';

/// "Ostatnie pobranie", the last error, "Serwer udostępnia pustą bazę" and "Pobierz teraz" —
/// at the end of Synchronizacja › Baza danych.
class DatabaseDownloadTiles extends StatelessWidget {
  const DatabaseDownloadTiles({super.key});

  static Future<void> _useEmptyServer(
    BuildContext context,
    DatabaseSync sync,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.databaseDownloadTilesEmptyTitle),
        content: Text(l10n.databaseDownloadTilesEmptyText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.databaseDownloadTilesUseEmpty),
          ),
        ],
      ),
    );
    if (sure != true) return;
    if (await sync.syncNow(acceptEmptyServer: true)) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.databaseDownloadTilesEmptyDownloaded)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sync = DatabaseSyncScope.of(context);
    final lastSync = sync.lastSync;
    final error = sync.lastError;
    final canDownload = sync.hasSource && !sync.downloading;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.history),
          title: Text(l10n.databaseDownloadTilesLastDownload),
          subtitle: Text(
            sync.downloading
                ? l10n.databaseDownloadTilesDownloading
                : lastSync == null
                ? l10n.databaseDownloadTilesNever
                : _describeLastSync(lastSync, sync.lastSource),
          ),
          trailing: sync.downloading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        if (error != null && !sync.downloading)
          ListTile(
            leading: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(l10n.databaseDownloadTilesLastAttemptFailed),
            subtitle: Text(error),
          ),
        if (sync.serverEmpty && !sync.downloading)
          ListTile(
            leading: Icon(Icons.info_outline, color: palette.accent),
            title: Text(l10n.databaseDownloadTilesServerEmpty),
            subtitle: Text(
              sync.lastSource == DatabaseSource.github && error == null
                  ? l10n.databaseDownloadTilesEmptyUsedGitHub
                  : l10n.databaseDownloadTilesEmptyKeptOld,
            ),
            trailing: TextButton(
              onPressed: () => _useEmptyServer(context, sync),
              child: Text(l10n.databaseDownloadTilesUseEmpty),
            ),
          ),
        ListTile(
          enabled: canDownload,
          leading: Icon(Icons.download, color: palette.accent),
          title: Text(
            l10n.databaseDownloadTilesDownloadNow,
            style: TextStyle(
              color: canDownload ? palette.accent : palette.textSecondary,
            ),
          ),
          onTap: sync.syncNow,
        ),
      ],
    );
  }
}

String _describeLastSync(DateTime d, DatabaseSource? source) {
  String two(int n) => n.toString().padLeft(2, '0');
  final when =
      '${two(d.day)}.${two(d.month)}.${d.year}, ${two(d.hour)}:${two(d.minute)}';
  return switch (source) {
    DatabaseSource.local => l10n.databaseDownloadTilesWhenLocal(when),
    DatabaseSource.remote => l10n.databaseDownloadTilesWhenRemote(when),
    DatabaseSource.github => '$when (GitHub)',
    null => when,
  };
}
