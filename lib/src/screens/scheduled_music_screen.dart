import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/local_library.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import '../playback/scheduled_music.dart';
import '../theme.dart';
import '../widgets/scrolling_text.dart';
import '../widgets/song_names.dart';
import '../widgets/song_tile.dart';

const _dayNames = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];
const _onDay = [
  'w poniedziałek',
  'we wtorek',
  'w środę',
  'w czwartek',
  'w piątek',
  'w sobotę',
  'w niedzielę',
];

/// "Jutro o 07:00, jeden raz" / "Pn, Śr • następnie w środę o 07:00" / "Wyłączone".
String scheduledLabel(ScheduledTime time) {
  final at = time.nextAt;
  if (!time.enabled || at == null) return 'Wyłączone';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final inDays =
      DateTime(at.year, at.month, at.day).difference(today).inHours.toDouble() /
      24;
  final day = switch (inDays.round()) {
    0 => 'dzisiaj',
    1 => 'jutro',
    _ => _onDay[at.weekday - 1],
  };
  if (time.days.isEmpty) {
    return '${day[0].toUpperCase()}${day.substring(1)} o ${time.label}, jeden raz';
  }
  final days = time.days.length == 7
      ? 'Codziennie'
      : [
          for (final (i, name) in _dayNames.indexed)
            if (time.days.contains(i + 1)) name,
        ].join(', ');
  return '$days • następnie $day o ${time.label}';
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
        const SnackBar(content: Text('Android nie pozwolił tego zaplanować.')),
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
        const SnackBar(
          content: Text(
            'Bez powiadomień telefon może nie uruchomić aplikacji sam.',
          ),
        ),
      );
    }
  }

  Future<void> _pick(BuildContext context, ScheduledMusic scheduled) async {
    final time = scheduled.timeOf(kind);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: time.hour, minute: time.minute),
      helpText: 'Godzina',
      cancelText: 'Anuluj',
      confirmText: 'Ustaw',
      hourLabelText: 'Godzina',
      minuteLabelText: 'Minuta',
      errorInvalidText: 'Nieprawidłowa godzina',
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

/// Ja › Zaplanowane wyłączenie.
class ScheduledStopScreen extends StatelessWidget {
  const ScheduledStopScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Zaplanowane wyłączenie')),
    body: ListView(
      children: [
        const _TimeTile(kind: ScheduleKind.stop),
        const _DayPicker(kind: ScheduleKind.stop),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'O tej godzinie muzyka ucichnie i się zatrzyma.',
            style: TextStyle(color: context.palette.textSecondary),
          ),
        ),
      ],
    ),
  );
}

/// Ja › Zaplanowane uruchomienie muzyki: when, how loud, and what plays.
class ScheduledStartScreen extends StatefulWidget {
  const ScheduledStartScreen({super.key});

  @override
  State<ScheduledStartScreen> createState() => _ScheduledStartScreenState();
}

class _ScheduledStartScreenState extends State<ScheduledStartScreen> {
  int? _draggedVolume;

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
      appBar: AppBar(title: const Text('Zaplanowane uruchomienie')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _TimeTile(kind: ScheduleKind.start),
          const _DayPicker(kind: ScheduleKind.start),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Głośność: $volume%'),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Co ma zagrać',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          _option(
            icon: Icons.music_note_outlined,
            label: 'Utwór',
            subtitle: source is ScheduledSong
                ? _songLabel(source.song)
                : 'Wybierz utwór',
            selected: source is ScheduledSong,
            onTap: () => _pickSong(scheduled),
          ),
          _option(
            icon: Icons.queue_music,
            label: 'Playlista',
            subtitle: source is ScheduledPlaylist
                ? source.name
                : 'Wybierz playlistę',
            selected: source is ScheduledPlaylist,
            onTap: () => _pickPlaylist(scheduled),
          ),
          _option(
            icon: Icons.replay,
            label: 'Ostatnia kolejka',
            subtitle: 'Gra dalej od miejsca, w którym została przerwana',
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
          decoration: const InputDecoration(
            hintText: 'Wybierz utwór',
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
      appBar: AppBar(title: const Text('Wybierz playlistę')),
      body: playlists.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
              child: Text(
                'Nie masz jeszcze żadnej playlisty.',
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
