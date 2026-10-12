import 'package:flutter/material.dart';

import '../playback/player_controller.dart';
import '../theme.dart';
import '../theme_controller.dart';
import '../widgets/color_picker.dart';
import '../widgets/song_cover.dart';

/// "Ustawienia › Wygląd › Filtry do albumów": a look laid over every album cover, how strong it
/// is, previewed on the song in the player.
class CoverFilterScreen extends StatefulWidget {
  const CoverFilterScreen({super.key});

  @override
  State<CoverFilterScreen> createState() => _CoverFilterScreenState();
}

class _CoverFilterScreenState extends State<CoverFilterScreen> {
  static const _presets = [
    (ThemeController.defaultMonochromeColor, 'Fosfor'),
    (Color(0xFF33FF66), 'Zielony'),
    (Color(0xFFFFB000), 'Bursztyn'),
    (Color(0xFF5FF5E8), 'Cyjan'),
    (Color(0xFFE8E8E8), 'Biały'),
    (Color(0xFFFF6EC7), 'Róż'),
  ];

  /// The slider while it's dragged: only the preview follows it, and it's saved on release —
  /// every cover on every screen is filtered again when it's saved.
  double? _dragged;

  static String _note(CoverFilter f) => switch (f) {
    CoverFilter.none => 'Okładki bez zmian',
    CoverFilter.lain => 'Błękit i zieleń, ziarno i linie jak w anime Serial Experiments Lain (1996)',
    CoverFilter.monochrome => 'Jeden kolor: odcienie z gęstości zapalonych punktów, jak na starych ekranach',
  };

  /// Unlit dots: a dark screen, Game Boy greens, paper.
  static const _backgrounds = [
    (Color(0xFF000000), 'Czarny'),
    (Color(0xFF0F380F), 'Ciemna zieleń'),
    (Color(0xFF9BBC0F), 'Jasna zieleń (Game Boy)'),
    (Color(0xFFE8E2D0), 'Papier'),
  ];

  /// A colour from the palette; one that isn't a preset is remembered among "your colours".
  Future<void> _pickCustom(
    ThemeController themes, {
    required Color initial,
    required String title,
    required Future<void> Function(Color) apply,
  }) async {
    final color = await showColorPicker(
      context,
      initial: initial,
      title: title,
      swatches: themes.savedColors,
    );
    if (color == null) return;
    await apply(color);
    final preset = [
      ..._presets,
      ..._backgrounds,
    ].any((p) => p.$1.toARGB32() == color.toARGB32());
    if (!preset) await themes.saveColor(color);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final themes = ThemeScope.of(context);
    final track = PlayerScope.of(context).current;
    final selected = themes.coverFilter;
    final color = themes.monochromeColor;
    final strength = _dragged ?? themes.coverFilterStrength;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Filtry do albumów'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 16, bottom: 24),
        children: [
          Center(
            child: track == null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Włącz utwór, aby zobaczyć tu podgląd na jego okładce.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  )
                : SongCover(
                    cover: track.cover,
                    size: 200,
                    filterStrength: strength,
                  ),
          ),
          const SizedBox(height: 12),
          for (final filter in CoverFilter.values)
            ListTile(
              title: Text(filter.label),
              subtitle: Text(_note(filter)),
              trailing: Icon(
                filter == selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: filter == selected
                    ? palette.accent
                    : palette.textSecondary,
              ),
              onTap: () => themes.setCoverFilter(filter),
            ),
          if (selected != CoverFilter.none) ...[
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(
                children: [
                  Text(
                    'Intensywność',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: palette.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(strength * 100).round()}%',
                    style: TextStyle(color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            Slider(
              value: strength,
              // Steps of 5 %: each one is a new filtered image.
              divisions: 20,
              label: '${(strength * 100).round()}%',
              onChanged: (v) => setState(() => _dragged = v),
              onChangeEnd: (v) async {
                await themes.setFilterStrength(selected, v);
                if (mounted) setState(() => _dragged = null);
              },
            ),
          ],
          if (selected == CoverFilter.monochrome) ...[
            const Divider(height: 24),
            _ColorRow(
              title: 'Kolor punktów',
              presets: _presets,
              selected: color,
              saved: themes.savedColors,
              onSelect: themes.setMonochromeColor,
              onForget: themes.forgetColor,
              onCustom: () => _pickCustom(
                themes,
                initial: color,
                title: 'Kolor punktów',
                apply: themes.setMonochromeColor,
              ),
            ),
            _ColorRow(
              title: 'Kolor tła',
              presets: _backgrounds,
              selected: themes.monochromeBackground,
              saved: themes.savedColors,
              onSelect: themes.setMonochromeBackground,
              onForget: themes.forgetColor,
              onAuto: () => themes.setMonochromeBackground(null),
              onCustom: () => _pickCustom(
                themes,
                initial: themes.monochromeBackground ?? Colors.black,
                title: 'Kolor tła',
                apply: themes.setMonochromeBackground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One colour setting: a title, then round swatches — an "Auto" one when [onAuto] is given, the
/// presets, the user's saved colours (long press forgets one) and "+" for the palette.
class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.title,
    required this.presets,
    required this.selected,
    required this.saved,
    required this.onSelect,
    required this.onForget,
    required this.onCustom,
    this.onAuto,
  });

  final String title;
  final List<(Color, String)> presets;

  /// `null`: "Auto".
  final Color? selected;
  final List<Color> saved;
  final ValueChanged<Color> onSelect;
  final ValueChanged<Color> onForget;
  final VoidCallback onCustom;
  final VoidCallback? onAuto;

  bool _isSelected(Color c) => selected?.toARGB32() == c.toARGB32();

  Widget _swatch(Color c, {String? tooltip, VoidCallback? onLongPress}) =>
      Tooltip(
        message: tooltip ?? '#${colorHex(c)}',
        child: InkResponse(
          onTap: () => onSelect(c),
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: c,
              child: _isSelected(c)
                  ? Icon(Icons.check, color: contrastOn(c))
                  : null,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final presetValues = {for (final (c, _) in presets) c.toARGB32()};
    final own = [
      for (final c in saved)
        if (!presetValues.contains(c.toARGB32())) c,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: palette.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  selected == null ? 'Auto' : '#${colorHex(selected!)}',
                  style: TextStyle(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (onAuto != null)
                Tooltip(
                  message: 'Automatyczny: przyciemniony kolor punktów',
                  child: InkResponse(
                    onTap: onAuto,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: palette.surface,
                        child: selected == null
                            ? Icon(Icons.check, color: palette.accent)
                            : Text(
                                'A',
                                style: TextStyle(color: palette.textSecondary),
                              ),
                      ),
                    ),
                  ),
                ),
              for (final (c, name) in presets) _swatch(c, tooltip: name),
              for (final c in own)
                _swatch(
                  c,
                  tooltip:
                      'Twój kolor #${colorHex(c)} • przytrzymaj, aby usunąć',
                  onLongPress: () => onForget(c),
                ),
              Tooltip(
                message: 'Wybierz z palety',
                child: InkResponse(
                  onTap: onCustom,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: palette.surface,
                      child: Icon(Icons.add, color: palette.textPrimary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
