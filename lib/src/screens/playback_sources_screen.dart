import 'package:flutter/material.dart';

import '../data/source_settings.dart';
import '../l10n.dart';
import '../theme.dart';
import 'local_music_screen.dart';
import 'private_server_screen.dart';
import 'youtube_playback_screen.dart';

/// "Ustawienia › Odtwarzanie › Źródła": which source plays a song that more than one source
/// has, and which sources are used at all (switches). Rows are reordered by dragging; a tap
/// opens the source's own settings.
class PlaybackSourcesScreen extends StatelessWidget {
  const PlaybackSourcesScreen({super.key});

  static IconData iconOf(PlaybackSource source) => switch (source) {
    PlaybackSource.phone => Icons.smartphone,
    PlaybackSource.server => Icons.dns_outlined,
    PlaybackSource.youtube => Icons.smart_display_outlined,
  };

  static Widget _settingsOf(PlaybackSource source) => switch (source) {
    PlaybackSource.phone => const LocalMusicScreen(),
    PlaybackSource.server => const PrivateServerScreen(),
    PlaybackSource.youtube => const YouTubePlaybackScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = SourceSettingsScope.of(context);
    final order = settings.playbackOrder;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.playbackSourcesScreenTitle),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.playbackSourcesScreenIntro,
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
              footer: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text(
                  l10n.playbackSourcesScreenCachedSongs,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: AppFontSize.small,
                  ),
                ),
              ),
              children: [
                for (final (i, source) in order.indexed)
                  ListTile(
                    key: ValueKey(source),
                    leading: Icon(iconOf(source)),
                    title: Text('${i + 1}. ${source.label}'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _settingsOf(source),
                      ),
                    ),
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
