import 'package:flutter/material.dart';

import '../dummy.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'about_screen.dart';
import 'account_screen.dart';
import 'appearance_screen.dart';
import 'cover_sources_screen.dart';
import 'data_saver_screen.dart';
import 'database_source_screen.dart';
import 'history_settings_screen.dart';
import 'link_settings_screen.dart';
import 'local_music_screen.dart';
import 'outbox_settings_screen.dart';
import 'playback_settings_screen.dart';
import 'spotify_source_screen.dart';
import 'youtube_source_screen.dart';

const _id = 'Ustawienia';

class _SettingsEntry {
  const _SettingsEntry(this.icon, this.title, this.subtitle, this.opens);

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder opens;
}

/// The entries under their section headers.
const _sections = <(String, List<_SettingsEntry>)>[
  (
    'MusicDatabase',
    [
      _SettingsEntry(
        Icons.account_circle_outlined,
        'Konto',
        'Logowanie • Synchronizacja playlist i nastrojów • Konto Google',
        _openAccount,
      ),
      _SettingsEntry(
        Icons.storage,
        'Serwer',
        'Adresy serwera • Wi-Fi sieci lokalnej • Pobieranie bazy',
        _openServer,
      ),
      _SettingsEntry(
        Icons.forward_to_inbox_outlined,
        'Zgłoszenia poprawek',
        'Wysyłanie automatyczne • Czeka na wysłanie',
        _openOutbox,
      ),
    ],
  ),
  (
    'Słuchanie',
    [
      _SettingsEntry(
        Icons.volume_up_outlined,
        'Odtwarzanie',
        'Kolejność źródeł • Sposoby odtwarzania YouTube • Przenikanie',
        _openPlayback,
      ),
      _SettingsEntry(
        Icons.folder_outlined,
        'Muzyka na telefonie',
        'Foldery z muzyką • Skanowanie',
        _openLocalMusic,
      ),
      _SettingsEntry(
        Icons.history,
        'Historia odtwarzania',
        'Przechowywanie • Wyczyść historię',
        _openHistory,
      ),
    ],
  ),
  (
    'Wyszukiwanie i import',
    [
      _SettingsEntry(
        Icons.smart_display_outlined,
        'YouTube',
        'Szukanie utworów i playlist • Kod YouTube API',
        _openYouTube,
      ),
      _SettingsEntry(
        Icons.graphic_eq,
        'Spotify',
        'Szukanie i importowanie playlist • Spotify API',
        _openSpotify,
      ),
    ],
  ),
  (
    'Wyświetlanie',
    [
      _SettingsEntry(
        Icons.palette_outlined,
        'Wygląd',
        'Motywy • Tryb ciemny • Nazwy łacińskie • Filtry do albumów',
        _openAppearance,
      ),
      _SettingsEntry(
        Icons.album_outlined,
        'Okładki albumów',
        'Plik na telefonie • iTunes • Deezer • YouTube',
        _openCoverSources,
      ),
    ],
  ),
  (
    'Dane',
    [
      _SettingsEntry(
        Icons.download_for_offline_outlined,
        'Oszczędzanie danych i tryb offline',
        'Tylko przez Wi-Fi • Pamięć podręczna',
        _openDataSaver,
      ),
    ],
  ),
  (
    'Aplikacja',
    [
      _SettingsEntry(
        Icons.link,
        'Otwieranie linków',
        'YouTube • Spotify • Pytaj, czym otworzyć',
        _openLinks,
      ),
      _SettingsEntry(
        Icons.info_outline,
        'Informacje i pomoc',
        'Wersja • Użytek prywatny • Licencja • Kod źródłowy',
        _openAbout,
      ),
    ],
  ),
];

Widget _openAccount(BuildContext context) => const AccountScreen();

Widget _openServer(BuildContext context) => const DatabaseSourceScreen();

Widget _openOutbox(BuildContext context) => const OutboxSettingsScreen();

Widget _openPlayback(BuildContext context) => const PlaybackSettingsScreen();

Widget _openLocalMusic(BuildContext context) => const LocalMusicScreen();

Widget _openHistory(BuildContext context) => const HistorySettingsScreen();

Widget _openYouTube(BuildContext context) => const YouTubeSourceScreen();

Widget _openSpotify(BuildContext context) => const SpotifySourceScreen();

Widget _openAppearance(BuildContext context) => const AppearanceScreen();

Widget _openCoverSources(BuildContext context) => const CoverSourcesScreen();

Widget _openDataSaver(BuildContext context) => const DataSaverScreen();

Widget _openLinks(BuildContext context) => const LinkSettingsScreen();

Widget _openAbout(BuildContext context) => const AboutScreen();

/// "Ustawienia", opened from "Ja".
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Ustawienia'),
        actions: [
          IconButton(
            tooltip: 'Wyszukaj ustawienie',
            icon: const Icon(Icons.search),
            onPressed: () => showDummy(context, '$_id › Wyszukaj ustawienie'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final (header, entries) in _sections) ...[
            SectionTitle(header),
            for (final entry in entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
                visualDensity: const VisualDensity(vertical: -1),
                leading: Icon(entry.icon, size: 28),
                title: Text(entry.title),
                subtitle: Text(entry.subtitle),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: entry.opens)),
              ),
          ],
        ],
      ),
    );
  }
}
