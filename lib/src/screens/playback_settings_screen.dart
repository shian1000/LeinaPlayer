import 'package:flutter/material.dart';

import '../data/hidden_songs.dart';
import '../data/source_settings.dart';
import '../l10n.dart';
import '../playback/volume_leveling.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'hidden_songs_screen.dart';
import 'playback_sources_screen.dart';

/// "Ustawienia › Odtwarzanie": which source plays a song (and through it each source's
/// settings), "Przenikanie utworów", "Wyrównywanie głośności", and what dragging a song row to the right
/// does.
class PlaybackSettingsScreen extends StatefulWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  State<PlaybackSettingsScreen> createState() => _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  /// The slider while it's dragged; saved on release.
  int? _dragged;
  int? _draggedLeveling;

  final _levelingSupported = VolumeLeveling.isSupported();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = SourceSettingsScope.of(context);
    final seconds = _dragged ?? settings.crossfadeSeconds;
    final order = settings.activePlaybackOrder;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.playbackSettingsScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: const Icon(Icons.low_priority),
            title: Text(l10n.playbackSettingsScreenSources),
            subtitle: Text(
              order.isEmpty
                  ? l10n.playbackSettingsScreenAllSourcesOff
                  : [
                      for (final (i, source) in order.indexed)
                        '${i + 1}. ${source.label}',
                    ].join(', '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PlaybackSourcesScreen(),
              ),
            ),
          ),
          if (HiddenSongsScope.maybeOf(context) case final hidden?)
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(l10n.playbackSettingsScreenHiddenSongs),
              subtitle: Text(
                hidden.songs.isEmpty
                    ? l10n.playbackSettingsScreenHiddenNone
                    : l10n.playbackSettingsScreenHiddenCount(
                        hidden.songs.length,
                      ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const HiddenSongsScreen(),
                ),
              ),
            ),
          SectionTitle(l10n.playbackSettingsScreenTransitions),
          ListTile(
            leading: const Icon(Icons.join_inner),
            title: Text(l10n.playbackSettingsScreenCrossfade),
            subtitle: Text(crossfadeLabel(seconds)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _Edge(l10n.playbackSettingsScreenCrossfadeOffShort),
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
              l10n.playbackSettingsScreenCrossfadeNote,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: AppFontSize.small,
              ),
            ),
          ),
          SectionTitle(l10n.playbackSettingsScreenVolume),
          FutureBuilder(
            future: _levelingSupported,
            builder: (context, snapshot) =>
                _leveling(settings, supported: snapshot.data ?? true),
          ),
          SectionTitle(l10n.playbackSettingsScreenSwipeRight),
          RadioGroup<bool>(
            groupValue: settings.swipePlaysNext,
            onChanged: (value) {
              if (value != null) settings.setSwipePlaysNext(value);
            },
            child: Column(
              children: [
                RadioListTile<bool>(
                  value: true,
                  secondary: const Icon(Icons.playlist_play),
                  title: Text(l10n.playbackSettingsScreenPlayNext),
                ),
                RadioListTile<bool>(
                  value: false,
                  secondary: const Icon(Icons.queue_music),
                  title: Text(l10n.playbackSettingsScreenAddToQueue),
                  subtitle: Text(l10n.playbackSettingsScreenAddToQueueSubtitle),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              l10n.playbackSettingsScreenSwipeNote,
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

  Widget _leveling(SourceSettings settings, {required bool supported}) {
    final palette = context.palette;
    final percent = _draggedLeveling ?? settings.levelingPercent;
    final on = supported && settings.leveling;
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.equalizer),
          title: Text(l10n.playbackSettingsScreenLeveling),
          subtitle: Text(
            supported
                ? l10n.playbackSettingsScreenLevelingSubtitle
                : l10n.playbackSettingsScreenLevelingUnsupported,
          ),
          value: on,
          onChanged: supported ? settings.setLeveling : null,
        ),
        ListTile(
          enabled: on,
          leading: const Icon(Icons.tune),
          title: Text(l10n.playbackSettingsScreenStrength),
          subtitle: Text('$percent%'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _Edge(l10n.playbackSettingsScreenStrengthGentle),
              Expanded(
                child: Slider(
                  value: percent.toDouble(),
                  min: 10,
                  max: 100,
                  divisions: 9,
                  label: '$percent%',
                  onChanged: on
                      ? (v) => setState(() => _draggedLeveling = v.round())
                      : null,
                  onChangeEnd: (v) async {
                    await settings.setLevelingPercent(v.round());
                    if (mounted) setState(() => _draggedLeveling = null);
                  },
                ),
              ),
              _Edge(l10n.playbackSettingsScreenStrengthStrong),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            l10n.playbackSettingsScreenStrengthNote,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: AppFontSize.small,
            ),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.graphic_eq),
          title: Text(l10n.playbackSettingsScreenMeasure),
          subtitle: Text(l10n.playbackSettingsScreenMeasureSubtitle),
          value: on && settings.levelingMeasure,
          onChanged: on ? settings.setLevelingMeasure : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            l10n.playbackSettingsScreenMeasureNote,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: AppFontSize.small,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Wyłączone", "5 s".
String crossfadeLabel(int seconds) =>
    seconds == 0 ? l10n.playbackSettingsScreenCrossfadeOff : '$seconds s';

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
