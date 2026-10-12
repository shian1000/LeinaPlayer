import 'package:flutter/material.dart';

import '../theme.dart';
import '../theme_controller.dart';
import 'cover_filter_screen.dart';

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
            subtitle: Text(
              themes.followSystem
                  ? 'Sterowane przez system (teraz: '
                        '${systemIsDark ? 'tryb ciemny' : 'tryb jasny'})'
                  : 'Wyłączone: tryb jasny • Włączone: tryb ciemny',
            ),
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
    final themes = dark ? darkThemes : lightThemes;
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
              leading: _PaletteSwatch(theme.palette),
              title: Text(theme.name),
              trailing: Icon(
                identical(theme, selected)
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: identical(theme, selected)
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

/// Small preview of a theme: background with accent, text and two artwork colours.
class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch(this.preview);

  final AppPalette preview;

  @override
  Widget build(BuildContext context) {
    final colors = [
      preview.accent,
      preview.textPrimary,
      preview.coverColors[0],
      preview.coverColors[1],
    ];
    return Container(
      width: 56,
      height: 40,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: preview.background,
        border: Border.all(color: preview.outline ?? preview.divider),
        borderRadius: preview.radius(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final color in colors)
            Container(
              width: 9,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: preview.radius(2),
              ),
            ),
        ],
      ),
    );
  }
}
