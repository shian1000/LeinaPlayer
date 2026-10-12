import 'package:flutter/material.dart';

import '../dummy.dart';
import '../theme.dart';
import 'about_screen.dart';
import 'appearance_screen.dart';
import 'cover_sources_screen.dart';
import 'data_saver_screen.dart';
import 'history_settings_screen.dart';
import 'music_sources_screen.dart';

const _id = 'Ustawienia';

class _SettingsEntry {
  const _SettingsEntry(this.icon, this.title, this.subtitle, {this.opens});

  final IconData icon;
  final String title;
  final String subtitle;

  /// Sub-screen opened by the entry; null means the entry is still a dummy.
  final WidgetBuilder? opens;
}

const _entries = [
  _SettingsEntry(
    Icons.account_circle_outlined,
    'Konto',
    'Nazwa użytkownika • Zamknięcie konta',
  ),
  _SettingsEntry(
    Icons.library_music_outlined,
    'Źródła muzyki',
    'Muzyka lokalna • YouTube • Kolejność odtwarzania',
    opens: _openMusicSources,
  ),
  _SettingsEntry(
    Icons.album_outlined,
    'Źródła okładek',
    'Plik na telefonie • iTunes • Deezer • YouTube',
    opens: _openCoverSources,
  ),
  _SettingsEntry(
    Icons.palette_outlined,
    'Wygląd',
    'Motyw jasny i ciemny • Tryb ciemny',
    opens: _openAppearance,
  ),
  _SettingsEntry(
    Icons.volume_up_outlined,
    'Odtwarzanie',
    'Odtwarzanie ciągłe • Autoodtwarzanie',
  ),
  _SettingsEntry(
    Icons.history,
    'Historia odtwarzania',
    'Przechowywanie • Wyczyść historię',
    opens: _openHistory,
  ),
  _SettingsEntry(Icons.notifications_none, 'Powiadomienia', 'Push • E-mail'),
  _SettingsEntry(
    Icons.download_for_offline_outlined,
    'Oszczędzanie danych i tryb offline',
    'Tylko przez Wi-Fi • Pamięć podręczna',
    opens: _openDataSaver,
  ),
  _SettingsEntry(
    Icons.equalizer,
    'Jakość zawartości multimedialnej',
    'Jakość odtwarzania przez Wi-Fi • Jakość pobranych plików audio',
  ),
  _SettingsEntry(
    Icons.info_outline,
    'Informacje i pomoc',
    'Użytek prywatny • Licencja • Kod źródłowy',
    opens: _openAbout,
  ),
];

Widget _openAppearance(BuildContext context) => const AppearanceScreen();

Widget _openMusicSources(BuildContext context) => const MusicSourcesScreen();

Widget _openCoverSources(BuildContext context) => const CoverSourcesScreen();

Widget _openAbout(BuildContext context) => const AboutScreen();

Widget _openDataSaver(BuildContext context) => const DataSaverScreen();

Widget _openHistory(BuildContext context) => const HistorySettingsScreen();

/// "Ustawienia", opened from the profile drawer.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void dummy(String label) => showDummy(context, '$_id › $label');
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Ustawienia'),
        actions: [
          IconButton(
            tooltip: 'Wyszukaj ustawienie',
            icon: const Icon(Icons.search),
            onPressed: () => dummy('Wyszukaj ustawienie'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _QuickTile(
                      icon: Icons.signal_cellular_alt,
                      title: 'Tryb oszczędzania danych',
                      value: 'Automatyczne',
                      onTap: () => dummy('Tryb oszczędzania danych (kafelek)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickTile(
                      icon: Icons.visibility_off_outlined,
                      title: 'Sesja prywatna',
                      value: 'Wył.',
                      onTap: () => dummy('Sesja prywatna (kafelek)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in _entries)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 0,
              ),
              visualDensity: const VisualDensity(vertical: -1),
              leading: Icon(entry.icon, size: 28),
              title: Text(entry.title),
              subtitle: Text(entry.subtitle),
              onTap: entry.opens == null
                  ? () => dummy(entry.title)
                  : () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: entry.opens!)),
            ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.textPrimary,
                side: BorderSide(
                  color: palette.outline ?? palette.textSecondary,
                ),
                shape: palette.pillShape,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 8,
                ),
              ),
              onPressed: () => dummy('Wyloguj'),
              child: const Text(
                'Wyloguj',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceHigh,
      shape: palette.boxShape(8),
      child: InkWell(
        customBorder: palette.boxShape(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26),
              const SizedBox(height: 8),
              // Roboto (and Lain's monospace) is wider than the reference font; shrink instead of
              // wrapping to two lines.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  maxLines: 1,
                  style: const TextStyle(fontSize: AppFontSize.caption),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
