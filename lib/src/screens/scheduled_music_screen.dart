import 'package:flutter/material.dart';

import '../app_name.dart';
import '../data/combined_search.dart';
import '../data/local_library.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import '../l10n.dart';
import '../playback/scheduled_music.dart';
import '../theme.dart';
import '../widgets/scrolling_text.dart';
import '../widgets/song_names.dart';
import '../widgets/song_tile.dart';

List<String> get _dayNames => [
  l10n.scheduledMusicScreenMon,
  l10n.scheduledMusicScreenTue,
  l10n.scheduledMusicScreenWed,
  l10n.scheduledMusicScreenThu,
  l10n.scheduledMusicScreenFri,
  l10n.scheduledMusicScreenSat,
  l10n.scheduledMusicScreenSun,
];
List<String> get _onDay => [
  l10n.scheduledMusicScreenOnMonday,
  l10n.scheduledMusicScreenOnTuesday,
  l10n.scheduledMusicScreenOnWednesday,
  l10n.scheduledMusicScreenOnThursday,
  l10n.scheduledMusicScreenOnFriday,
  l10n.scheduledMusicScreenOnSaturday,
  l10n.scheduledMusicScreenOnSunday,
];

String _capitalized(String text) =>
    '${text[0].toUpperCase()}${text.substring(1)}';

/// "Jutro o 07:00, jeden raz" / "Pn, Śr • następnie w środę o 07:00" / "Wyłączone".
String scheduledLabel(ScheduledTime time) {
  final at = time.nextAt;
  if (!time.enabled || at == null) return l10n.scheduledMusicScreenOff;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final inDays =
      DateTime(at.year, at.month, at.day).difference(today).inHours.toDouble() /
      24;
  final day = switch (inDays.round()) {
    0 => l10n.scheduledMusicScreenToday,
    1 => l10n.scheduledMusicScreenTomorrow,
    _ => _onDay[at.weekday - 1],
  };
  if (time.days.isEmpty) {
    return _capitalized(l10n.scheduledMusicScreenOnce(day, time.label));
  }
  final days = time.days.length == 7
      ? l10n.scheduledMusicScreenEveryDay
      : [
          for (final (i, name) in _dayNames.indexed)
            if (time.days.contains(i + 1)) name,
        ].join(', ');
  return l10n.scheduledMusicScreenRepeating(days, day, time.label);
}

/// Ja's "Zaplanowana muzyka" row: "Uruchomienie o 07:00 • wyłączenie o 23:00" / "Wyłączone".
String scheduledSummary(ScheduledMusic scheduled) {
  bool on(ScheduledTime time) => time.enabled && time.nextAt != null;
  final start = scheduled.timeOf(ScheduleKind.start);
  final stop = scheduled.timeOf(ScheduleKind.stop);
  final parts = [
    if (on(start)) l10n.scheduledMusicScreenStartAt(start.label),
    if (on(stop)) l10n.scheduledMusicScreenStopAt(stop.label),
  ];
  if (parts.isEmpty) return l10n.scheduledMusicScreenOff;
  return _capitalized(parts.join(' • '));
}

/// Ja › Zaplanowana muzyka: the scheduled start and stop.
class ScheduledMusicScreen extends StatelessWidget {
  const ScheduledMusicScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheduled = ScheduledMusicScope.of(context);
    void push(Widget screen) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scheduledMusicScreenTitle)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.alarm, size: 26),
            title: Text(l10n.scheduledMusicScreenStart),
            subtitle: Text(
              scheduledLabel(scheduled.timeOf(ScheduleKind.start)),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const ScheduledStartScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.alarm_off, size: 26),
            title: Text(l10n.scheduledMusicScreenStop),
            subtitle: Text(scheduledLabel(scheduled.timeOf(ScheduleKind.stop))),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const ScheduledStopScreen()),
          ),
        ],
      ),
    );
  }
}

/// Which weekdays a scheduled start or stop repeats on; none ticked: once.
class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.kind});

  final ScheduleKind kind;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheduled = ScheduledMusicScope.of(context);
    final days = scheduled.timeOf(kind).days;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          for (final (i, name) in _dayNames.indexed)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Material(
                  color: days.contains(i + 1)
                      ? palette.accent
                      : palette.surfaceHigh,
                  shape: palette.boxShape(8),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => scheduled.setDays(
                      kind,
                      days.contains(i + 1)
                          ? ({...days}..remove(i + 1))
                          : {...days, i + 1},
                    ),
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: AppFontSize.small,
                            color: days.contains(i + 1)
                                ? palette.background
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<bool> _mayStartApp(ScheduledMusic scheduled) async {
  try {
    return await scheduled.canStartApp();
  } catch (e) {
    debugPrint('Checking the full-screen notification permission failed: $e');
    return true;
  }
}

/// Android 14+ lets only alarm and calling apps open themselves from a full-screen notification
/// unless the user allows it; without it the scheduled music never starts.
Future<void> _askToAllowStartingApp(
  BuildContext context,
  ScheduledMusic scheduled,
) async {
  final open =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.scheduledMusicScreenAllowTitle),
          content: Text(l10n.scheduledMusicScreenAllowBody(appName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.scheduledMusicScreenNotNow),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.scheduledMusicScreenOpenSettings),
            ),
          ],
        ),
      ) ??
      false;
  if (open) await _openStartAppSettings(scheduled);
}

Future<void> _openStartAppSettings(ScheduledMusic scheduled) async {
  try {
    await scheduled.openStartAppSettings();
  } catch (e) {
    debugPrint('Opening the full-screen notification settings failed: $e');
  }
}

/// The time of a scheduled start or stop: tapping picks it and switches it on.
class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.kind});

  final ScheduleKind kind;

  Future<void> _switchedOn(
    BuildContext context,
    ScheduledMusic scheduled,
    bool accepted,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!accepted) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.scheduledMusicScreenNotAllowed)),
      );
      return;
    }
    if (kind != ScheduleKind.start) return;
    var allowed = false;
    try {
      allowed = await scheduled.requestNotifications();
    } catch (e) {
      debugPrint('Asking for the notification permission failed: $e');
    }
    if (!allowed) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.scheduledMusicScreenNoNotifications)),
      );
      return;
    }
    if (!await _mayStartApp(scheduled) && context.mounted) {
      await _askToAllowStartingApp(context, scheduled);
    }
  }

  Future<void> _pick(BuildContext context, ScheduledMusic scheduled) async {
    final time = scheduled.timeOf(kind);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: time.hour, minute: time.minute),
      helpText: l10n.scheduledMusicScreenHour,
      cancelText: l10n.commonCancel,
      confirmText: l10n.scheduledMusicScreenSet,
      hourLabelText: l10n.scheduledMusicScreenHour,
      minuteLabelText: l10n.scheduledMusicScreenMinute,
      errorInvalidText: l10n.scheduledMusicScreenInvalidTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final accepted = await scheduled.setTime(kind, picked.hour, picked.minute);
    if (context.mounted) await _switchedOn(context, scheduled, accepted);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheduled = ScheduledMusicScope.of(context);
    final time = scheduled.timeOf(kind);
    return ListTile(
      title: Text(
        time.label,
        style: TextStyle(
          fontSize: AppFontSize.hero,
          fontWeight: FontWeight.bold,
          color: time.enabled ? palette.accent : palette.textSecondary,
        ),
      ),
      subtitle: Text(scheduledLabel(time)),
      trailing: Switch(
        value: time.enabled,
        onChanged: (on) async {
          final done = await scheduled.setEnabled(kind, on);
          if (on && context.mounted) {
            await _switchedOn(context, scheduled, done);
          }
        },
      ),
      onTap: () => _pick(context, scheduled),
    );
  }
}

/// Ja › Zaplanowana muzyka › Zaplanowane wyłączenie.
class ScheduledStopScreen extends StatelessWidget {
  const ScheduledStopScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(l10n.scheduledMusicScreenStop)),
    body: ListView(
      children: [
        const _TimeTile(kind: ScheduleKind.stop),
        const _DayPicker(kind: ScheduleKind.stop),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.scheduledMusicScreenStopNote,
            style: TextStyle(color: context.palette.textSecondary),
          ),
        ),
      ],
    ),
  );
}

/// Ja › Zaplanowana muzyka › Zaplanowane uruchomienie: when, how loud, and what plays.
class ScheduledStartScreen extends StatefulWidget {
  const ScheduledStartScreen({super.key});

  @override
  State<ScheduledStartScreen> createState() => _ScheduledStartScreenState();
}

class _ScheduledStartScreenState extends State<ScheduledStartScreen> {
  int? _draggedVolume;
  bool _canStartApp = true;

  /// The permission is given on Android's own screen: checked again on coming back.
  late final _lifecycle = AppLifecycleListener(onResume: _checkCanStartApp);

  @override
  void initState() {
    super.initState();
    _lifecycle;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkCanStartApp());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _checkCanStartApp() async {
    if (!mounted) return;
    final can = await _mayStartApp(ScheduledMusicScope.of(context));
    if (mounted && can != _canStartApp) setState(() => _canStartApp = can);
  }

  Future<void> _pickSong(ScheduledMusic scheduled) async {
    final hit = await Navigator.of(
      context,
    ).push<SearchHit>(MaterialPageRoute(builder: (_) => const _SongPicker()));
    if (hit != null) await scheduled.setSource(ScheduledSong(TrackRef.of(hit)));
  }

  Future<void> _pickPlaylist(ScheduledMusic scheduled) async {
    final playlist = await Navigator.of(context).push<PlaylistSummary>(
      MaterialPageRoute(builder: (_) => const _PlaylistPicker()),
    );
    if (playlist != null) {
      await scheduled.setSource(ScheduledPlaylist(playlist.id, playlist.name));
    }
  }

  String _songLabel(TrackRef ref) {
    final hit = resolveTrack(
      ref,
      SongCatalogScope.of(context),
      LocalLibraryScope.of(context),
      YouTubeLibraryScope.of(context),
    );
    return '${hit.shownArtist(context)} – ${hit.shownTitle(context)}';
  }

  Widget _option({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = context.palette;
    return ListTile(
      leading: Icon(icon, color: selected ? palette.accent : null),
      title: Text(label),
      subtitle: ScrollingText(
        subtitle,
        style: TextStyle(color: palette.textSecondary),
      ),
      trailing: selected ? Icon(Icons.check, color: palette.accent) : null,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheduled = ScheduledMusicScope.of(context);
    final source = scheduled.source;
    final volume = _draggedVolume ?? scheduled.volume;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scheduledMusicScreenStart)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _TimeTile(kind: ScheduleKind.start),
          if (scheduled.timeOf(ScheduleKind.start).enabled && !_canStartApp)
            ListTile(
              leading: Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(l10n.scheduledMusicScreenWontStart),
              subtitle: Text(l10n.scheduledMusicScreenWontStartHint(appName)),
              onTap: () => _openStartAppSettings(scheduled),
            ),
          const _DayPicker(kind: ScheduleKind.start),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(l10n.scheduledMusicScreenVolume(volume)),
          ),
          Slider(
            value: volume.toDouble(),
            min: ScheduledMusic.minVolume.toDouble(),
            max: 100,
            divisions: 19,
            label: '$volume%',
            onChanged: (v) => setState(() => _draggedVolume = v.round()),
            onChangeEnd: (v) async {
              await scheduled.setVolume(v.round());
              if (mounted) setState(() => _draggedVolume = null);
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              l10n.scheduledMusicScreenWhatPlays,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          _option(
            icon: Icons.music_note_outlined,
            label: l10n.scheduledMusicScreenSong,
            subtitle: source is ScheduledSong
                ? _songLabel(source.song)
                : l10n.scheduledMusicScreenPickSong,
            selected: source is ScheduledSong,
            onTap: () => _pickSong(scheduled),
          ),
          _option(
            icon: Icons.queue_music,
            label: l10n.scheduledMusicScreenPlaylist,
            subtitle: source is ScheduledPlaylist
                ? source.name
                : l10n.scheduledMusicScreenPickPlaylist,
            selected: source is ScheduledPlaylist,
            onTap: () => _pickPlaylist(scheduled),
          ),
          _option(
            icon: Icons.replay,
            label: l10n.scheduledMusicScreenLastQueue,
            subtitle: l10n.scheduledMusicScreenLastQueueSubtitle,
            selected: source is ScheduledLastQueue,
            onTap: () => scheduled.setSource(const ScheduledLastQueue()),
          ),
        ],
      ),
    );
  }
}

class _SongPicker extends StatefulWidget {
  const _SongPicker();

  @override
  State<_SongPicker> createState() => _SongPickerState();
}

class _SongPickerState extends State<_SongPicker> {
  final _query = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SongCatalogScope.of(context).ensureLoaded();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hits = searchEverywhere(
      _query.text,
      SongCatalogScope.of(context),
      LocalLibraryScope.of(context),
      youTube: YouTubeLibraryScope.of(context),
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.palette.background,
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: l10n.scheduledMusicScreenPickSong,
            border: InputBorder.none,
          ),
        ),
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final hit in hits)
            SongTile(hit: hit, onTap: () => Navigator.of(context).pop(hit)),
        ],
      ),
    );
  }
}

class _PlaylistPicker extends StatelessWidget {
  const _PlaylistPicker();

  @override
  Widget build(BuildContext context) {
    final playlists = PlaylistLibraryScope.of(context).playlists;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scheduledMusicScreenPickPlaylist)),
      body: playlists.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
              child: Text(
                l10n.scheduledMusicScreenNoPlaylists,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.palette.textSecondary),
              ),
            )
          : ListView(
              children: [
                for (final playlist in playlists)
                  ListTile(
                    leading: const Icon(Icons.queue_music),
                    title: ScrollingText(playlist.name),
                    onTap: () => Navigator.of(context).pop(playlist),
                  ),
              ],
            ),
    );
  }
}
