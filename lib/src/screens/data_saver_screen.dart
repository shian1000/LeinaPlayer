import 'package:flutter/material.dart';

import '../data/source_settings.dart';
import '../l10n.dart';
import '../theme.dart';
import 'cache_settings_screen.dart';
import 'download_folder.dart';

/// "Ustawienia › Oszczędzanie danych i tryb offline": what may use mobile data, where downloaded
/// songs go ([DownloadFolderTile]) and in what format, and the cache ([CacheSettingsScreen]).
class DataSaverScreen extends StatelessWidget {
  const DataSaverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SourceSettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.palette.surface,
        title: Text(l10n.dataSaverScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: Text(l10n.dataSaverScreenQueueWifiOnly),
            subtitle: Text(l10n.dataSaverScreenQueueWifiOnlySubtitle),
            value: settings.queuePrefetchWifiOnly,
            onChanged: settings.setQueuePrefetchWifiOnly,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.album_outlined),
            title: Text(l10n.dataSaverScreenCoversWifiOnly),
            subtitle: Text(l10n.dataSaverScreenCoversWifiOnlySubtitle),
            value: settings.coverWifiOnly,
            onChanged: settings.setCoverWifiOnly,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lyrics_outlined),
            title: Text(l10n.dataSaverScreenLyrics),
            subtitle: Text(l10n.dataSaverScreenLyricsSubtitle),
            value: settings.lyrics,
            onChanged: settings.setLyrics,
          ),
          const Divider(height: 24),
          const DownloadFolderTile(),
          SwitchListTile(
            secondary: const Icon(Icons.audio_file_outlined),
            title: Text(l10n.dataSaverScreenMp3),
            subtitle: Text(l10n.dataSaverScreenMp3Subtitle),
            value: settings.downloadsAsMp3,
            onChanged: settings.setDownloadsAsMp3,
          ),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: Text(l10n.dataSaverScreenCache),
            subtitle: Text(
              l10n.dataSaverScreenCacheSubtitle(
                (cacheBytesOf(context) / (1024 * 1024)).toStringAsFixed(1),
              ),
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
