import 'package:flutter/material.dart';

import '../data/text_normalizer.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'about_screen.dart';
import 'account_screen.dart';
import 'appearance_screen.dart';
import 'cache_settings_screen.dart';
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

class _SettingsEntry {
  const _SettingsEntry(
    this.icon,
    this.title,
    this.subtitle,
    this.opens, {
    this.keywords = const [],
    this.deeper = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder opens;

  /// Settings on its screen not named in [subtitle], found by "Wyszukaj ustawienie".
  final List<String> keywords;

  /// Screens opened from its screen, with their own settings.
  final List<_SettingsEntry> deeper;
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
        keywords: [
          'Konto MusicDatabase',
          'Zaloguj się',
          'Wyloguj',
          'Konto Google (playlisty na YouTube)',
          'Statystyki słuchania',
        ],
      ),
      _SettingsEntry(
        Icons.storage,
        'Serwer',
        'Adresy serwera • Wi-Fi sieci lokalnej • Pobieranie bazy',
        _openServer,
        keywords: [
          'Adres serwera (połączenie zdalne)',
          'Adres serwera (sieć lokalna)',
          'Pobieranie',
          'Ostatnie pobranie',
        ],
      ),
      _SettingsEntry(
        Icons.forward_to_inbox_outlined,
        'Zgłoszenia poprawek',
        'Wysyłanie automatyczne • Czeka na wysłanie',
        _openOutbox,
        keywords: [
          'Wysyłaj zgłoszenia poprawek automatycznie',
          'Ostatnie wysyłanie',
        ],
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
        keywords: [
          'Kolejność odtwarzania',
          'Źródła',
          'Przejścia między utworami',
          'Przenikanie utworów',
        ],
      ),
      _SettingsEntry(
        Icons.folder_outlined,
        'Muzyka na telefonie',
        'Foldery z muzyką • Skanowanie',
        _openLocalMusic,
        keywords: [
          'Foldery do skanowania',
          'Nowe utwory spoza bazy',
          'Ostatnie skanowanie',
        ],
      ),
      _SettingsEntry(
        Icons.history,
        'Historia odtwarzania',
        'Przechowywanie • Wyczyść historię',
        _openHistory,
        keywords: ['Przechowuj historię'],
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
        keywords: [
          'Włącz szukanie w serwisie YouTube',
          'Wyszukuj playlisty na YouTube',
        ],
      ),
      _SettingsEntry(
        Icons.graphic_eq,
        'Spotify',
        'Szukanie i importowanie playlist • Spotify API',
        _openSpotify,
        keywords: ['Importowanie playlist', 'Wyszukuj playlisty na Spotify'],
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
        keywords: [
          'Motyw jasny',
          'Motyw ciemny',
          'Systemowe przełączanie trybu ciemnego',
          'Nazwy w alfabecie łacińskim',
          'Filtry do albumów',
        ],
      ),
      _SettingsEntry(
        Icons.album_outlined,
        'Okładki albumów',
        'Plik na telefonie • iTunes • Deezer • YouTube',
        _openCoverSources,
        keywords: ['Źródła okładek'],
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
        deeper: [
          _SettingsEntry(
            Icons.sd_storage_outlined,
            'Pamięć podręczna',
            'Pobrane • Kolejka • Utwory z YouTube • Okładki',
            _openCache,
            keywords: [
              'Pobrane utwory',
              'Usuń wszystkie pobrane',
              'Ile następnych utworów z kolejki zapisywać',
              'Rozmiar pamięci podręcznej okładek',
              'Wyczyść okładki',
              'Wyczyść utwory z YouTube',
              'Wyczyść wszystko',
              'Dopasowania z YouTube',
              'Zapomnij filmy dopasowane przez telefon',
              'Zapomnij „nie znaleziono na YouTube”',
            ],
          ),
        ],
        keywords: ['Pobieraj okładki tylko przez Wi-Fi'],
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
        keywords: [
          'Linki YouTube',
          'Linki Spotify',
          'Otwieraj linki w Leina Radio',
        ],
      ),
      _SettingsEntry(
        Icons.info_outline,
        'Informacje i pomoc',
        'Wersja • Użytek prywatny • Licencja • Kod źródłowy',
        _openAbout,
        keywords: [
          'Wersja aplikacji',
          'Licencje bibliotek',
          'Tylko do użytku prywatnego',
        ],
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

Widget _openCache(BuildContext context) => const CacheSettingsScreen();

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
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _SettingsSearch()),
            ),
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

/// A setting found by "Wyszukaj ustawienie": its name, where it is, and the screen to open.
typedef _Found = ({String label, String path, _SettingsEntry entry});

List<_Found> _searchSettings(String query) {
  final wanted = normalizeForSearch(query);
  if (wanted.isEmpty) return const [];
  final found = <_Found>[];
  void visit(_SettingsEntry entry, String path) {
    final here = '$path › ${entry.title}';
    final labels = {
      entry.title,
      ...entry.subtitle.split(' • '),
      ...entry.keywords,
    }.difference({for (final inner in entry.deeper) inner.title});
    for (final label in labels) {
      if (normalizeForSearch(label).contains(wanted)) {
        found.add((
          label: label,
          path: label == entry.title ? path : here,
          entry: entry,
        ));
      }
    }
    for (final inner in entry.deeper) {
      visit(inner, here);
    }
  }

  for (final (header, entries) in _sections) {
    for (final entry in entries) {
      visit(entry, 'Ustawienia › $header');
    }
  }
  return found;
}

/// "Wyszukaj ustawienie": every setting whose name has the query, opening its screen.
class _SettingsSearch extends StatefulWidget {
  const _SettingsSearch();

  @override
  State<_SettingsSearch> createState() => _SettingsSearchState();
}

class _SettingsSearchState extends State<_SettingsSearch> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final found = _searchSettings(_query);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Wyszukaj ustawienie',
            border: InputBorder.none,
          ),
          onChanged: (text) => setState(() => _query = text),
        ),
      ),
      body: _query.trim().isNotEmpty && found.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
              child: Text(
                'Nie ma ustawienia „${_query.trim()}”.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
            )
          : ListView(
              children: [
                for (final hit in found)
                  ListTile(
                    leading: Icon(hit.entry.icon),
                    title: Text(hit.label),
                    subtitle: Text(hit.path),
                    onTap: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: hit.entry.opens)),
                  ),
              ],
            ),
    );
  }
}
