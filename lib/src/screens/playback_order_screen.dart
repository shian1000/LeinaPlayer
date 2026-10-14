import 'package:flutter/material.dart';

import '../data/source_settings.dart';
import '../theme.dart';

/// "Ustawienia › Źródła muzyki › Kolejność odtwarzania": which source plays a song that more
/// than one source has, and which sources are used at all (switches). Rows are reordered by
/// dragging.
class PlaybackOrderScreen extends StatelessWidget {
  const PlaybackOrderScreen({super.key});

  static IconData iconOf(PlaybackSource source) => switch (source) {
    PlaybackSource.phone => Icons.smartphone,
    PlaybackSource.server => Icons.dns_outlined,
    PlaybackSource.youtube => Icons.smart_display_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = SourceSettingsScope.of(context);
    final order = settings.playbackOrder;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Kolejność odtwarzania'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Gdy utwór jest dostępny w kilku miejscach, odtwarzany jest z pierwszego '
              'włączonego na liście. Wyłączone źródła nie są używane. Przeciągnij, aby zmienić '
              'kolejność.',
              style: TextStyle(
                fontSize: AppFontSize.listSubtitle,
                color: palette.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView(
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) {
                final list = [...order];
                list.insert(to, list.removeAt(from));
                settings.setPlaybackOrder(list);
              },
              children: [
                for (final (i, source) in order.indexed)
                  ListTile(
                    key: ValueKey(source),
                    leading: Icon(iconOf(source)),
                    title: Text('${i + 1}. ${source.label}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: settings.enabledSources.contains(source),
                          onChanged: (v) =>
                              settings.setSourceEnabled(source, v),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
