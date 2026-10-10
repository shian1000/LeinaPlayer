import 'package:flutter/material.dart';

import '../theme.dart';
import 'database_source_screen.dart';
import 'local_music_screen.dart';

/// "Ustawienia › Źródła muzyki" — where the app gets music from: folders on the device and the
/// MusicDatabase database downloaded from a server.
class MusicSourcesScreen extends StatelessWidget {
  const MusicSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
        ],
      ),
    );
  }
}
