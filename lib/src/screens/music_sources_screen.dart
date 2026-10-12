import 'package:flutter/material.dart';

import '../data/source_settings.dart';
import '../theme.dart';
import 'database_source_screen.dart';
import 'local_music_screen.dart';
import 'playback_order_screen.dart';
import 'spotify_source_screen.dart';
import 'youtube_source_screen.dart';

/// "Ustawienia › Źródła muzyki" — where the app gets music from: folders on the device and the
/// MusicDatabase database downloaded from a server, YouTube, Spotify (playlists only), and which
/// of them plays first.
/// (Caching the queue's next songs is in Oszczędzanie danych › Pamięć podręczna.)
class MusicSourcesScreen extends StatelessWidget {
  const MusicSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SourceSettingsScope.of(context);
    final order = settings.playbackOrder;
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
            subtitle: const Text(
              'Wyszukiwanie utworów i playlist w serwisie YouTube',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const YouTubeSourceScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.graphic_eq),
            title: const Text('Spotify'),
            subtitle: const Text(
              'Wyszukiwanie i importowanie playlist ze Spotify',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SpotifySourceScreen(),
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
        ],
      ),
    );
  }
}
