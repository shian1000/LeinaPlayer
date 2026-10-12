import 'package:flutter/material.dart';

import '../data/spotify_playlist.dart';
import '../dummy.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _id = 'Ustawienia › Źródła muzyki › Spotify';

/// "Ustawienia › Źródła muzyki › Spotify": so far only where Spotify playlists come from. Spotify
/// isn't a place to play from — its tracks are found in MusicDatabase, on the phone or on YouTube.
class SpotifySourceScreen extends StatelessWidget {
  const SpotifySourceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Spotify'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SectionTitle('Importowanie playlist'),
          ListTile(
            leading: const Icon(Icons.api),
            title: const Text('Spotify API'),
            subtitle: const Text(
              'Klucz aplikacji Spotify — wczytywanie całych playlist',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDummy(context, '$_id › Spotify API'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Bez klucza playlisty są wczytywane z publicznej strony Spotify, bez logowania '
              '— tylko pierwsze ${SpotifyPlaylists.embedLimit} utworów każdej playlisty.',
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
