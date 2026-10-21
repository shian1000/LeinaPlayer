import 'package:flutter/material.dart';

import '../data/source_settings.dart';
import '../theme.dart';
import 'cache_settings_screen.dart';

/// "Ustawienia › Oszczędzanie danych i tryb offline": what may use mobile data, and the cache
/// ([CacheSettingsScreen]).
class DataSaverScreen extends StatelessWidget {
  const DataSaverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SourceSettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.palette.surface,
        title: const Text('Oszczędzanie danych i tryb offline'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: const Text(
              'Zapisuj następne utwory z kolejki tylko przez Wi-Fi',
            ),
            subtitle: const Text(
              'Przez sieć komórkową utwory z kolejki nie są pobierane z wyprzedzeniem',
            ),
            value: settings.queuePrefetchWifiOnly,
            onChanged: settings.setQueuePrefetchWifiOnly,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.album_outlined),
            title: const Text('Pobieraj okładki tylko przez Wi-Fi'),
            subtitle: const Text(
              'Przez sieć komórkową widać tylko okładki zapisane już na telefonie i te z '
              'plików muzycznych',
            ),
            value: settings.coverWifiOnly,
            onChanged: settings.setCoverWifiOnly,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lyrics_outlined),
            title: const Text('Pobieraj teksty piosenek'),
            subtitle: const Text(
              'Z serwisu LRCLIB, gdy otwarty jest odtwarzacz. Wyłączone: bez karty z tekstem '
              'i bez połączeń z LRCLIB',
            ),
            value: settings.lyrics,
            onChanged: settings.setLyrics,
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: const Text('Pamięć podręczna'),
            subtitle: Text(
              'Utwory z YouTube, kolejka, okładki • zajęte '
              '${(cacheBytesOf(context) / (1024 * 1024)).toStringAsFixed(1)} MB',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CacheSettingsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
