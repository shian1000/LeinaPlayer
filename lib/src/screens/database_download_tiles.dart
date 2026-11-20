import 'package:flutter/material.dart';

import '../data/database_sync.dart';
import '../theme.dart';

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
        title: const Text('Użyć pustej bazy z serwera?'),
        content: const Text(
          'Obecna baza zostanie zastąpiona pustą: wyszukiwanie, radio, Odkrywaj, Przeglądaj '
          'i rekomendacje będą puste, a nastroje globalne znikną. Grane utwory będą '
          'wysyłane jako prośby o dodanie do bazy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Użyj pustej'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    if (await sync.syncNow(acceptEmptyServer: true)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Pobrano pustą bazę z serwera')),
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
          title: const Text('Ostatnie pobranie'),
          subtitle: Text(
            sync.downloading
                ? 'Pobieranie…'
                : lastSync == null
                ? 'Nigdy'
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
            title: const Text('Ostatnia próba się nie udała'),
            subtitle: Text(error),
          ),
        if (sync.serverEmpty && !sync.downloading)
          ListTile(
            leading: Icon(Icons.info_outline, color: palette.accent),
            title: const Text('Serwer udostępnia pustą bazę'),
            subtitle: Text(
              sync.lastSource == DatabaseSource.github && error == null
                  ? 'Jest w niej 0 utworów, więc baza została pobrana z GitHuba.'
                  : 'Jest w niej 0 utworów, więc telefon został przy dotychczasowej bazie.',
            ),
            trailing: TextButton(
              onPressed: () => _useEmptyServer(context, sync),
              child: const Text('Użyj pustej'),
            ),
          ),
        ListTile(
          enabled: canDownload,
          leading: Icon(Icons.download, color: palette.accent),
          title: Text(
            'Pobierz teraz',
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
    DatabaseSource.local => '$when (sieć lokalna)',
    DatabaseSource.remote => '$when (połączenie zdalne)',
    DatabaseSource.github => '$when (GitHub)',
    null => when,
  };
}
