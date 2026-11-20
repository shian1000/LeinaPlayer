import 'package:flutter/material.dart';

import '../data/source_settings.dart';
import '../data/youtube_search.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/feature_info.dart';
import 'feature_infos.dart';

/// "Ustawienia › YouTube": searching YouTube ([YouTubeMethod]s, tried top to bottom). Playing it
/// is in Ustawienia › Odtwarzanie.
class YouTubeSourceScreen extends StatelessWidget {
  const YouTubeSourceScreen({super.key});

  Future<void> _editApiKey(
    BuildContext context,
    SourceSettings settings,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: l10n.youtubeSourceScreenApiKey,
        hint: l10n.youtubeSourceScreenApiKeyHint,
        initial: settings.apiKey ?? '',
      ),
    );
    if (result != null) await settings.setApiKey(result);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = SourceSettingsScope.of(context);
    final enabled = settings.youTubeSearchEnabled;
    final apiKey = settings.apiKey;

    final newPipeSearch = YouTubeScope.searchOf(context).newPipeAvailable;
    String methodNote(YouTubeMethod m) => switch (m) {
      YouTubeMethod.newPipe =>
        newPipeSearch
            ? l10n.youtubeSourceScreenNewPipeNote
            : l10n.youtubeSourceScreenAndroidOnly,
      YouTubeMethod.explode => l10n.youtubeSourceScreenExplodeNote,
      YouTubeMethod.ytDlpServer => l10n.youtubeSourceScreenServerNote,
      YouTubeMethod.api =>
        apiKey == null
            ? l10n.youtubeSourceScreenApiNeedsKey
            : 'YouTube Data API',
    };
    final hint = TextStyle(
      fontSize: AppFontSize.listSubtitle,
      color: palette.textSecondary,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('YouTube'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionTitle(l10n.youtubeSourceScreenSearchSection),
          SwitchListTile(
            secondary: const Icon(Icons.travel_explore),
            title: Text(l10n.youtubeSourceScreenSearchSwitch),
            value: enabled,
            onChanged: settings.setYouTubeSearchEnabled,
          ),
          for (final method in YouTubeMethod.values)
            _LongPressInfo(
              info: switch (method) {
                YouTubeMethod.newPipe => FeatureInfos.newPipeSearch,
                YouTubeMethod.explode => FeatureInfos.explodeSearch,
                YouTubeMethod.api => FeatureInfos.youTubeApi,
                YouTubeMethod.ytDlpServer => null,
              },
              child: SwitchListTile(
                secondary: Icon(switch (method) {
                  YouTubeMethod.newPipe => Icons.smartphone,
                  YouTubeMethod.explode => Icons.smartphone_outlined,
                  YouTubeMethod.ytDlpServer => Icons.dns_outlined,
                  YouTubeMethod.api => Icons.api,
                }),
                title: Text(method.label),
                subtitle: Text(methodNote(method)),
                value: settings.methods.contains(method),
                onChanged:
                    enabled &&
                        (method != YouTubeMethod.newPipe || newPipeSearch)
                    ? (v) => settings.setMethod(method, v)
                    : null,
              ),
            ),
          ListTile(
            leading: const Icon(Icons.key),
            title: Text(l10n.youtubeSourceScreenApiKey),
            subtitle: Text(
              apiKey == null ? l10n.youtubeSourceScreenNotSet : _masked(apiKey),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editApiKey(context, settings),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(l10n.youtubeSourceScreenOrderNote, style: hint),
          ),
          SectionTitle(l10n.youtubeSourceScreenPlaylistsSection),
          SwitchListTile(
            secondary: const Icon(Icons.playlist_play),
            title: Text(l10n.youtubeSourceScreenPlaylistSearch),
            subtitle: Text(
              settings.playlistSearch
                  ? l10n.youtubeSourceScreenPlaylistSearchOn
                  : l10n.youtubeSourceScreenPlaylistSearchOff,
            ),
            value: settings.youTubePlaylistSearch,
            onChanged: enabled ? settings.setYouTubePlaylistSearch : null,
          ),
        ],
      ),
    );
  }
}

/// Only the last characters, so the key isn't shown in full on screen.
String _masked(String key) =>
    key.length <= 4 ? '••••' : '••••${key.substring(key.length - 4)}';

/// A long press on [child] explains it ([info]); switch rows have no onLongPress of their own.
class _LongPressInfo extends StatelessWidget {
  const _LongPressInfo({required this.info, required this.child});

  final FeatureInfo? info;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final info = this.info;
    if (info == null) return child;
    return GestureDetector(
      onLongPress: () => showFeatureInfo(context, info),
      child: child,
    );
  }
}
