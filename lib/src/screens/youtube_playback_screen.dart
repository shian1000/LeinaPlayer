import 'package:flutter/material.dart';

import '../data/source_settings.dart';
import '../data/youtube_search.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/feature_info.dart';
import 'feature_infos.dart';

/// Short name of a playback method for lists ("1. Pamięć podręczna, 2. NewPipe, ...").
String shortPlaybackLabel(YouTubePlaybackMethod m) => switch (m) {
  YouTubePlaybackMethod.cache => l10n.youtubePlaybackScreenCache,
  YouTubePlaybackMethod.newPipe => 'NewPipe',
  YouTubePlaybackMethod.explode => 'youtube_explode',
  YouTubePlaybackMethod.ytDlpServer => 'yt-dlp',
  YouTubePlaybackMethod.youtubeApp => l10n.youtubePlaybackScreenYouTubeApp,
};

/// "Ustawienia › Odtwarzanie › Źródła › YouTube": which ways of playing a YouTube
/// video are used, and in what order (drag to reorder). The first switched-on one that works
/// plays the video.
class YouTubePlaybackScreen extends StatelessWidget {
  const YouTubePlaybackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = SourceSettingsScope.of(context);
    final newPipeAvailable = YouTubeScope.audioOf(context).newPipeAvailable;
    final order = settings.playbackMethodOrder;

    String note(YouTubePlaybackMethod m) => switch (m) {
      YouTubePlaybackMethod.cache => l10n.youtubePlaybackScreenCacheNote,
      YouTubePlaybackMethod.newPipe =>
        newPipeAvailable
            ? l10n.youtubePlaybackScreenNewPipeNote
            : l10n.youtubePlaybackScreenAndroidOnly,
      YouTubePlaybackMethod.explode => l10n.youtubePlaybackScreenExplodeNote,
      YouTubePlaybackMethod.ytDlpServer => l10n.youtubePlaybackScreenYtDlpNote,
      YouTubePlaybackMethod.youtubeApp =>
        l10n.youtubePlaybackScreenYouTubeAppNote,
    };
    IconData icon(YouTubePlaybackMethod m) => switch (m) {
      YouTubePlaybackMethod.cache => Icons.offline_pin_outlined,
      YouTubePlaybackMethod.newPipe => Icons.smartphone,
      YouTubePlaybackMethod.explode => Icons.smartphone_outlined,
      YouTubePlaybackMethod.ytDlpServer => Icons.dns_outlined,
      YouTubePlaybackMethod.youtubeApp => Icons.open_in_new,
    };

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.youtubePlaybackScreenTitle),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.youtubePlaybackScreenIntro,
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
                settings.setPlaybackMethodOrder(list);
              },
              children: [
                for (final (i, method) in order.indexed)
                  ListTile(
                    key: ValueKey(method),
                    leading: Icon(icon(method)),
                    title: Text(method.label),
                    subtitle: Text(note(method)),
                    onLongPress: switch (method) {
                      YouTubePlaybackMethod.newPipe => () => showFeatureInfo(
                        context,
                        FeatureInfos.newPipePlayback,
                      ),
                      YouTubePlaybackMethod.explode => () => showFeatureInfo(
                        context,
                        FeatureInfos.explodePlayback,
                      ),
                      _ => null,
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: settings.playbackMethods.contains(method),
                          onChanged:
                              method == YouTubePlaybackMethod.newPipe &&
                                  !newPipeAvailable
                              ? null
                              : (v) => settings.setPlaybackMethod(method, v),
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
