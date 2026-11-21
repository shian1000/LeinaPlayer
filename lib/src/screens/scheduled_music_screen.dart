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
import '../widgets/swipe_actions.dart';

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

/// Ja's "Zaplanowana muzyka" row: "Uruchomienie o 07:00 • wyłączenie o 23:00" /
/// "Uruchomienia o 07:00, 09:30 • …" / "Wyłączone".
String scheduledSummary(ScheduledMusic scheduled) {
  final starts = [
    for (final start in scheduled.starts)
      if (start.isOn) start.label,
  ];
  final parts = [
    if (starts.length == 1) l10n.scheduledMusicScreenStartAt(starts.single),
    if (starts.length > 1) l10n.scheduledMusicScreenStartsAt(starts.join(', ')),
    if (scheduled.stopTime.isOn)
      l10n.scheduledMusicScreenStopAt(scheduled.stopTime.label),
  ];
  if (parts.isEmpty) return l10n.scheduledMusicScreenOff;
  return _capitalized(parts.join(' • '));
}

/// Zaplanowana muzyka's row for the starts: the one switched on as [scheduledLabel] says, several
/// by their times.
String _startsLabel(ScheduledMusic scheduled) {
  final on = [
    for (final start in scheduled.starts)
      if (start.isOn) start,
  ];
  if (on.isEmpty) return l10n.scheduledMusicScreenOff;
  if (on.length == 1) return scheduledLabel(on.single);
  return on.map((start) => start.label).join(', ');
}

/// What a start plays, in one line.
String _sourceLabel(BuildContext context, ScheduledSource source) =>
    switch (source) {
      ScheduledSong(:final song) => () {
        final hit = resolveTrack(
          song,
          SongCatalogScope.of(context),
          LocalLibraryScope.of(context),
          YouTubeLibraryScope.of(context),
        );
        return '${hit.shownArtist(context)} – ${hit.shownTitle(context)}';
      }(),
      ScheduledPlaylist(:final name) => name,
      ScheduledLastQueue() => l10n.scheduledMusicScreenLastQueue,
    };

/// Ja › Zaplanowana muzyka: the scheduled starts and stop.
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
            subtitle: Text(_startsLabel(scheduled)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const ScheduledStartsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.alarm_off, size: 26),
            title: Text(l10n.scheduledMusicScreenStop),
            subtitle: Text(scheduledLabel(scheduled.stopTime)),
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
  const _DayPicker({required this.time});

  final ScheduledTime time;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheduled = ScheduledMusicScope.of(context);
    final days = time.days;
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
                      time,
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

/// After switching a time on: says when Android refused, and for a start asks for what it needs
/// to bring the app up.
Future<void> _switchedOn(
  BuildContext context,
  ScheduledMusic scheduled,
  ScheduledTime time,
  bool accepted,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!accepted) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.scheduledMusicScreenNotAllowed)),
    );
    return;
  }
  if (time is! ScheduledStart) return;
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

Future<TimeOfDay?> _pickTime(BuildContext context, int hour, int minute) =>
    showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
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

/// The time of a scheduled start or stop: tapping picks it and switches it on.
class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.time, this.subtitle, this.onTap});

  final ScheduledTime time;

  /// Under [scheduledLabel]'s line.
  final String? subtitle;

  /// Instead of picking the time.
  final VoidCallback? onTap;

  Future<void> _pick(BuildContext context, ScheduledMusic scheduled) async {
    final picked = await _pickTime(context, time.hour, time.minute);
    if (picked == null) return;
    final accepted = await scheduled.setTime(time, picked.hour, picked.minute);
    if (context.mounted) await _switchedOn(context, scheduled, time, accepted);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheduled = ScheduledMusicScope.of(context);
    final more = subtitle;
    return ListTile(
      title: Text(
        time.label,
        style: TextStyle(
          fontSize: AppFontSize.hero,
          fontWeight: FontWeight.bold,
          color: time.enabled ? palette.accent : palette.textSecondary,
        ),
      ),
      subtitle: more == null
          ? Text(scheduledLabel(time))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(scheduledLabel(time)), ScrollingText(more)],
            ),
      trailing: Switch(
        value: time.enabled,
        onChanged: (on) async {
          final done = await scheduled.setEnabled(time, on);
          if (on && context.mounted) {
            await _switchedOn(context, scheduled, time, done);
          }
        },
      ),
      onTap: onTap ?? () => _pick(context, scheduled),
    );
  }
}

/// "Muzyka nie włączy się sama" while [shown] and Android 14+ doesn't let the app open itself;
/// a tap opens Android's screen for it.
class _WontStartWarning extends StatefulWidget {
  const _WontStartWarning({required this.shown});

  final bool shown;

  @override
  State<_WontStartWarning> createState() => _WontStartWarningState();
}

class _WontStartWarningState extends State<_WontStartWarning> {
  bool _canStartApp = true;

  /// The permission is given on Android's own screen: checked again on coming back.
  late final _lifecycle = AppLifecycleListener(onResume: _check);

  @override
  void initState() {
    super.initState();
    _lifecycle;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (!mounted) return;
    final can = await _mayStartApp(ScheduledMusicScope.of(context));
    if (mounted && can != _canStartApp) setState(() => _canStartApp = can);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.shown || _canStartApp) return const SizedBox.shrink();
    return ListTile(
      leading: Icon(
        Icons.warning_amber_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(l10n.scheduledMusicScreenWontStart),
      subtitle: Text(l10n.scheduledMusicScreenWontStartHint(appName)),
      onTap: () => _openStartAppSettings(ScheduledMusicScope.of(context)),
    );
  }
}

/// Ja › Zaplanowana muzyka › Zaplanowane wyłączenie.
class ScheduledStopScreen extends StatelessWidget {
  const ScheduledStopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stop = ScheduledMusicScope.of(context).stopTime;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scheduledMusicScreenStop)),
      body: ListView(
        children: [
          _TimeTile(time: stop),
          _DayPicker(time: stop),
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
}

/// Ja › Zaplanowana muzyka › Zaplanowane uruchomienie: every start, like the phone's alarms — each
/// switched on and off here, opened to change it, dragged left to delete it; + adds one.
class ScheduledStartsScreen extends StatelessWidget {
  const ScheduledStartsScreen({super.key});

  Future<void> _add(BuildContext context, ScheduledMusic scheduled) async {
    final picked = await _pickTime(context, 7, 0);
    if (picked == null) return;
    final (:start, :ok) = await scheduled.addStart(picked.hour, picked.minute);
    if (context.mounted) await _switchedOn(context, scheduled, start, ok);
  }

  Future<void> _delete(
    BuildContext context,
    ScheduledMusic scheduled,
    ScheduledStart start,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await scheduled.removeStart(start);
    messenger.showSnackBar(
      SnackBar(
        persist: false,
        content: Text(l10n.scheduledMusicScreenStartDeleted(start.label)),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () => scheduled.restoreStart(start),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheduled = ScheduledMusicScope.of(context);
    final starts = scheduled.starts;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scheduledMusicScreenStart)),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.scheduledMusicScreenAddStart,
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
        shape: palette.buttonShape,
        onPressed: () => _add(context, scheduled),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          _WontStartWarning(shown: starts.any((start) => start.enabled)),
          if (starts.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
              child: Text(
                l10n.scheduledMusicScreenNoStarts,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
          for (final start in starts)
            SwipeActions(
              key: ValueKey(start.id),
              left: SwipeAction(
                icon: Icons.delete_outline,
                label: l10n.scheduledMusicScreenDeleteStart,
                color: Theme.of(context).colorScheme.error,
                onTriggered: () => _delete(context, scheduled, start),
              ),
              child: _TimeTile(
                time: start,
                subtitle: l10n.scheduledMusicScreenStartSummary(
                  start.volume,
                  _sourceLabel(context, start.source),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ScheduledStartScreen(start: start),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One of Zaplanowane uruchomienie's starts: when, how loud, and what plays.
class ScheduledStartScreen extends StatefulWidget {
  const ScheduledStartScreen({super.key, required this.start});

  final ScheduledStart start;

  @override
  State<ScheduledStartScreen> createState() => _ScheduledStartScreenState();
}

class _ScheduledStartScreenState extends State<ScheduledStartScreen> {
  int? _draggedVolume;

  ScheduledStart get _start => widget.start;

  Future<void> _pickSong(ScheduledMusic scheduled) async {
    final hit = await Navigator.of(
      context,
    ).push<SearchHit>(MaterialPageRoute(builder: (_) => const _SongPicker()));
    if (hit != null) {
      await scheduled.setSource(_start, ScheduledSong(TrackRef.of(hit)));
    }
  }

  Future<void> _pickPlaylist(ScheduledMusic scheduled) async {
    final playlist = await Navigator.of(context).push<PlaylistSummary>(
      MaterialPageRoute(builder: (_) => const _PlaylistPicker()),
    );
    if (playlist != null) {
      await scheduled.setSource(
        _start,
        ScheduledPlaylist(playlist.id, playlist.name),
      );
    }
  }

  Future<void> _delete(ScheduledMusic scheduled) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await scheduled.removeStart(_start);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        persist: false,
        content: Text(l10n.scheduledMusicScreenStartDeleted(_start.label)),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () => scheduled.restoreStart(_start),
        ),
      ),
    );
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
    final source = _start.source;
    final volume = _draggedVolume ?? _start.volume;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scheduledMusicScreenStart),
        actions: [
          IconButton(
            tooltip: l10n.scheduledMusicScreenDeleteStart,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(scheduled),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _TimeTile(time: _start),
          _WontStartWarning(shown: _start.enabled),
          _DayPicker(time: _start),
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
              await scheduled.setVolume(_start, v.round());
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
                ? _sourceLabel(context, source)
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
            onTap: () =>
                scheduled.setSource(_start, const ScheduledLastQueue()),
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
