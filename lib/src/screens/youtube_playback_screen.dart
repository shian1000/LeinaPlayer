import 'package:flutter/material.dart';

import '../data/source_settings.dart';
import '../data/youtube_search.dart';
import '../theme.dart';
import '../widgets/feature_info.dart';
import 'feature_infos.dart';

/// Short name of a playback method for lists ("1. Pamięć podręczna, 2. NewPipe, ...").
String shortPlaybackLabel(YouTubePlaybackMethod m) => switch (m) {
  YouTubePlaybackMethod.cache => 'Pamięć podręczna',
  YouTubePlaybackMethod.newPipe => 'NewPipe',
  YouTubePlaybackMethod.explode => 'youtube_explode',
  YouTubePlaybackMethod.ytDlpServer => 'yt-dlp',
  YouTubePlaybackMethod.youtubeApp => 'Aplikacja YouTube',
};

/// "Ustawienia › Odtwarzanie › Sposoby odtwarzania YouTube": which ways of playing a YouTube
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
      YouTubePlaybackMethod.cache =>
        'Utwory odtworzone wcześniej grają z telefonu, także bez internetu (ustawienia: '
            'Oszczędzanie danych › Pamięć podręczna)',
      YouTubePlaybackMethod.newPipe =>
        newPipeAvailable
            ? 'Dźwięk prosto z YouTube, na telefonie'
            : 'Dostępne tylko na Androidzie',
      YouTubePlaybackMethod.explode =>
        'Obecnie YouTube odrzuca pobieranie tą metodą (błąd 403)',
      YouTubePlaybackMethod.ytDlpServer =>
        'Jeszcze niedostępne — serwer bazy danych tego nie obsługuje',
      YouTubePlaybackMethod.youtubeApp => 'Film otwiera się w aplikacji YouTube (bez niej w przeglądarce), poza tą aplikacją',
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
        title: const Text('Sposoby odtwarzania YouTube'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Utwór z YouTube gra pierwszym włączonym sposobem od góry; kolejne są używane '
              'tylko wtedy, gdy poprzedni zawiedzie. Przeciągnij, aby zmienić kolejność.',
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
