import 'package:flutter/material.dart';

import '../theme.dart';
import '../theme_controller.dart';
import '../widgets/theme_swatch.dart';
import 'cover_filter_screen.dart';
import 'theme_browser_screen.dart';

/// "Ustawienia › Wygląd". A light and a dark theme are chosen separately; the two switches
/// decide which of them is shown — by hand ("Przełącz na tryb ciemny") or following the phone's
/// own dark-mode setting. Everything is applied immediately and saved by [ThemeController].
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  void _open(BuildContext context, {required bool dark}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _ThemeListScreen(dark: dark)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final themes = ThemeScope.of(context);
    final systemIsDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Wygląd'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          ListTile(
            leading: const Icon(Icons.light_mode_outlined),
            title: const Text('Motyw jasny'),
            subtitle: Text(themes.light.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, dark: false),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('Motyw ciemny'),
            subtitle: Text(themes.dark.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, dark: true),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Pobierz motyw'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ThemeBrowserScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.filter_vintage_outlined),
            title: const Text('Filtry do albumów'),
            subtitle: Text(themes.coverFilter.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CoverFilterScreen(),
              ),
            ),
          ),
          const Divider(height: 24),
          SwitchListTile(
            secondary: const Icon(Icons.contrast),
            title: const Text('Przełącz na tryb ciemny'),
            subtitle: themes.followSystem
                ? Text(
                    'Sterowane przez system (teraz: '
                    '${systemIsDark ? 'tryb ciemny' : 'tryb jasny'})',
                  )
                : null,
            value: themes.followSystem ? systemIsDark : themes.darkMode,
            onChanged: themes.followSystem ? null : themes.setDarkMode,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.settings_suggest_outlined),
            title: const Text('Systemowe przełączanie trybu ciemnego'),
            subtitle: const Text(
              'Tryb jasny lub ciemny zgodnie z ustawieniem telefonu',
            ),
            value: themes.followSystem,
            onChanged: themes.setFollowSystem,
          ),
          const Divider(height: 24),
          SwitchListTile(
            secondary: const Icon(Icons.translate),
            title: const Text('Nazwy w alfabecie łacińskim'),
            subtitle: const Text(
              'Tytuł, wykonawca i album zapisane innym alfabetem z wersją '
              'łacińską w nawiasie, np. Кино (Kino)',
            ),
            value: themes.latinNames,
            onChanged: themes.setLatinNames,
          ),
        ],
      ),
    );
  }
}

/// List of themes for one slot: "Motyw jasny" ([dark] false) or "Motyw ciemny".
class _ThemeListScreen extends StatelessWidget {
  const _ThemeListScreen({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final controller = ThemeScope.of(context);
    final themes = dark ? controller.availableDark : controller.availableLight;
    final selected = dark ? controller.dark : controller.light;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(dark ? 'Motyw ciemny' : 'Motyw jasny'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          for (final theme in themes)
            ListTile(
              leading: ThemeSwatch(theme.preview),
              title: Text(theme.name),
              trailing: Icon(
                theme.id == selected.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: theme.id == selected.id
                    ? palette.accent
                    : palette.textSecondary,
              ),
              onTap: () =>
                  dark ? controller.setDark(theme) : controller.setLight(theme),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              dark
                  ? 'Używany, gdy włączony jest tryb ciemny.'
                  : 'Używany, gdy wyłączony jest tryb ciemny.',
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
