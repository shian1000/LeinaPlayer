import 'package:flutter/material.dart';

import '../data/source_settings.dart';
import '../data/spotify_playlist.dart';
import '../theme.dart';
import '../widgets/feature_info.dart';
import 'feature_infos.dart';
import '../widgets/common.dart';

/// "Ustawienia › Spotify": searching for Spotify playlists and where they come
/// from. Spotify isn't a place to play from — its tracks are found in MusicDatabase, on the phone
/// or on YouTube.
class SpotifySourceScreen extends StatelessWidget {
  const SpotifySourceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = SourceSettingsScope.of(context);
    final clientId = settings.spotifyClientId;
    final hint = TextStyle(
      fontSize: AppFontSize.listSubtitle,
      color: palette.textSecondary,
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Spotify'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SectionTitle('Wyszukiwanie'),
          SwitchListTile(
            secondary: const Icon(Icons.queue_music),
            title: const Text('Wyszukuj playlisty na Spotify'),
            subtitle: Text(
              settings.playlistSearch
                  ? 'Przyciskiem wyszukiwania w internecie, razem z YouTube'
                  : 'Wyłączone w filtrach wyszukiwania („Wyszukuj playlisty”)',
            ),
            value: settings.spotifyPlaylistSearch,
            onChanged: settings.setSpotifyPlaylistSearch,
          ),
          ListTile(
            leading: const Icon(Icons.api),
            title: const Text('Spotify API'),
            onLongPress: () =>
                showFeatureInfo(context, FeatureInfos.spotifyApi),
            subtitle: Text(
              settings.spotifyApiKey == null
                  ? 'Nie ustawiono — wyszukiwanie bez klucza'
                  : 'Client ID ${_masked(clientId!)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => _ApiKeyDialog(settings: settings),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Z kluczem Twojej aplikacji Spotify (developer.spotify.com) playlisty są '
              'wyszukiwane przez oficjalne Web API. Bez klucza — albo gdy API zawiedzie — '
              'tak jak robi to odtwarzacz na open.spotify.com bez logowania; to nieoficjalne i '
              'może przestać działać.',
              style: hint,
            ),
          ),
          const SectionTitle('Importowanie playlist'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Playlisty są wczytywane z publicznej strony Spotify, bez logowania — tylko '
              'pierwsze ${SpotifyPlaylists.embedLimit} utworów każdej playlisty.',
              style: hint,
            ),
          ),
        ],
      ),
    );
  }
}

/// Only the last characters, so the id isn't shown in full on screen.
String _masked(String key) =>
    key.length <= 4 ? '••••' : '••••${key.substring(key.length - 4)}';

/// Client ID and Client Secret of the user's Spotify app; saving them blank clears the key.
class _ApiKeyDialog extends StatefulWidget {
  const _ApiKeyDialog({required this.settings});

  final SourceSettings settings;

  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<_ApiKeyDialog> {
  late final _id = TextEditingController(
    text: widget.settings.spotifyApiKey?.clientId ?? '',
  );
  late final _secret = TextEditingController(
    text: widget.settings.spotifyApiKey?.clientSecret ?? '',
  );
  bool _showSecret = false;

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _save() {
    widget.settings.setSpotifyApiKey(_id.text, _secret.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Spotify API'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _id,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Client ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secret,
              autocorrect: false,
              enableSuggestions: false,
              obscureText: !_showSecret,
              decoration: InputDecoration(
                labelText: 'Client Secret',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _showSecret ? 'Ukryj' : 'Pokaż',
                  icon: Icon(
                    _showSecret ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _showSecret = !_showSecret),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(onPressed: _save, child: const Text('Zapisz')),
      ],
    );
  }
}
