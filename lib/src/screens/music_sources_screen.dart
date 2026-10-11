import 'package:flutter/material.dart';

import '../data/source_settings.dart';
import '../theme.dart';
import 'database_source_screen.dart';
import 'local_music_screen.dart';
import 'playback_order_screen.dart';
import 'youtube_source_screen.dart';

/// "Ustawienia › Źródła muzyki" — where the app gets music from: folders on the device and the
/// MusicDatabase database downloaded from a server, YouTube, and which of them plays first.
class MusicSourcesScreen extends StatelessWidget {
  const MusicSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SourceSettingsScope.of(context);
    final order = settings.playbackOrder;
    final cacheOn = settings.playbackMethods.contains(
      YouTubePlaybackMethod.cache,
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.palette.surface,
        title: const Text('Źródła muzyki'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Muzyka lokalna'),
            subtitle: const Text('Foldery z muzyką na tym urządzeniu'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LocalMusicScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Baza danych'),
            subtitle: const Text('Baza MusicDatabase pobierana z serwera'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DatabaseSourceScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.smart_display_outlined),
            title: const Text('YouTube'),
            subtitle: const Text('Wyszukiwanie utworów w serwisie YouTube'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const YouTubeSourceScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.low_priority),
            title: const Text('Kolejność odtwarzania'),
            subtitle: Text(
              [
                for (final (i, source) in order.indexed)
                  '${i + 1}. ${source.label}',
              ].join(', '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PlaybackOrderScreen(),
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.download_outlined),
            title: const Text('Twórz cache dla przyszłych utworów w kolejce'),
            subtitle: Text(
              cacheOn
                  ? 'Następne utwory z YouTube są pobierane na telefon z wyprzedzeniem'
                  : 'Wymaga pamięci podręcznej (YouTube › Sposoby odtwarzania)',
            ),
            value: settings.queuePrefetchEnabled,
            onChanged: settings.setQueuePrefetchEnabled,
          ),
          ListTile(
            enabled: settings.queuePrefetchEnabled,
            leading: const Icon(Icons.queue_music),
            title: const Text('Cachowanie kolejki'),
            subtitle: Text(_songCount(settings.queuePrefetch)),
            onTap: () => _pickQueuePrefetch(context, settings),
          ),
        ],
      ),
    );
  }

  Future<void> _pickQueuePrefetch(
    BuildContext context,
    SourceSettings settings,
  ) async {
    final count = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Ile następnych utworów z kolejki pobierać?'),
        children: [
          for (var n = 1; n <= SourceSettings.maxQueuePrefetch; n++)
            ListTile(
              title: Text(_songCount(n)),
              trailing: n == settings.queuePrefetch
                  ? Icon(Icons.check, color: context.palette.accent)
                  : null,
              onTap: () => Navigator.of(dialogContext).pop(n),
            ),
        ],
      ),
    );
    if (count != null) await settings.setQueuePrefetch(count);
  }
}

/// "1 następny utwór", "3 następne utwory", "5 następnych utworów".
String _songCount(int n) {
  if (n == 1) return '1 następny utwór';
  final few = n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14);
  return few ? '$n następne utwory' : '$n następnych utworów';
}
