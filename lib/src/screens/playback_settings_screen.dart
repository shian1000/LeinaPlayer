import 'package:flutter/material.dart';

import '../data/source_settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'playback_order_screen.dart';
import 'youtube_playback_screen.dart';

/// "Ustawienia › Odtwarzanie": which source plays a song, the ways of playing YouTube, and
/// "Przenikanie utworów".
class PlaybackSettingsScreen extends StatefulWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  State<PlaybackSettingsScreen> createState() => _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  /// The slider while it's dragged; saved on release.
  int? _dragged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = SourceSettingsScope.of(context);
    final seconds = _dragged ?? settings.crossfadeSeconds;
    final order = settings.activePlaybackOrder;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Odtwarzanie'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SectionTitle('Źródła'),
          ListTile(
            leading: const Icon(Icons.low_priority),
            title: const Text('Kolejność odtwarzania'),
            subtitle: Text(
              order.isEmpty
                  ? 'Wszystkie źródła wyłączone'
                  : [
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
          ListTile(
            leading: const Icon(Icons.smart_display_outlined),
            title: const Text('Sposoby odtwarzania YouTube'),
            subtitle: Text(
              [
                for (final (i, m) in settings.activePlaybackMethods.indexed)
                  '${i + 1}. ${shortPlaybackLabel(m)}',
              ].join(', '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const YouTubePlaybackScreen(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Utwór gra z pierwszego źródła w kolejności, które go ma; z YouTube — '
              'pierwszym włączonym sposobem, który zadziała. Zapisane utwory: Oszczędzanie '
              'danych i tryb offline › Pamięć podręczna.',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: AppFontSize.small,
              ),
            ),
          ),
          const SectionTitle('Przejścia między utworami'),
          ListTile(
            leading: const Icon(Icons.join_inner),
            title: const Text('Przenikanie utworów'),
            subtitle: Text(crossfadeLabel(seconds)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _Edge('Wył.'),
                Expanded(
                  child: Slider(
                    value: seconds.toDouble(),
                    max: SourceSettings.maxCrossfadeSeconds.toDouble(),
                    divisions: SourceSettings.maxCrossfadeSeconds,
                    label: crossfadeLabel(seconds),
                    onChanged: (v) => setState(() => _dragged = v.round()),
                    onChangeEnd: (v) async {
                      await settings.setCrossfadeSeconds(v.round());
                      if (mounted) setState(() => _dragged = null);
                    },
                  ),
                ),
                _Edge('${SourceSettings.maxCrossfadeSeconds} s'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Gdy utwór dobiega końca, następny z kolejki zaczyna się tyle sekund wcześniej: '
              'jeden cichnie, a drugi narasta. Tylko gdy kolejka przechodzi dalej sama — '
              '„Następny” i wybrany utwór włączają się od razu. Utwór z YouTube, który trzeba '
              'jeszcze wyszukać lub połączyć, przenika krócej (albo wcale), więc najlepiej '
              'działa z zapisanymi z wyprzedzeniem następnymi utworami (Pamięć podręczna).',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: AppFontSize.small,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Wyłączone", "5 s".
String crossfadeLabel(int seconds) => seconds == 0 ? 'Wyłączone' : '$seconds s';

class _Edge extends StatelessWidget {
  const _Edge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Text(
      text,
      style: TextStyle(
        color: context.palette.textSecondary,
        fontSize: AppFontSize.small,
      ),
    ),
  );
}
