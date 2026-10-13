import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/custom_covers.dart';
import '../data/local_library.dart';
import '../data/moods.dart';
import '../data/song_catalog.dart';
import '../data/youtube_library.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/collection_cover.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/song_tile.dart';

const _id = 'Nastrój';

/// One mood ("Nastrój", [ADR 0008](../../../docs/decisions/0008-moods.md)): its songs by title,
/// "Odtwórz losowo", and — for the user's own mood, or a global one with the permission —
/// taking songs out.
class MoodScreen extends StatelessWidget {
  const MoodScreen({super.key, required this.mood});

  final Mood mood;

  static Future<void> open(BuildContext context, Mood mood) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => MoodScreen(mood: mood)));

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final moods = MoodLibraryScope.of(context);
    final mood = moods.current(this.mood);
    if (mood == null) {
      return Scaffold(
        appBar: AppBar(title: Text(this.mood.name)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Tego nastroju już nie ma.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary),
            ),
          ),
        ),
      );
    }
    final hits = moodHits(
      mood,
      SongCatalogScope.of(context),
      LocalLibraryScope.of(context),
      YouTubeLibraryScope.of(context),
    );
    final editable = !mood.global || moods.canEditGlobal;
    final missing = mood.songIds.length - hits.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(mood.name),
        actions: [
          IconButton(
            tooltip: 'Menu nastroju (⋮)',
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showMoodMenu(context, mood, hits),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                MoodCover(mood: mood, size: 96),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mood.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppFontSize.largeTitle,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${mood.global ? 'Nastrój globalny' : 'Twój nastrój'} • '
                        '${_songCount(hits.length)}',
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                icon: const Icon(Icons.shuffle),
                label: const Text('Odtwórz losowo'),
                onPressed: hits.isEmpty
                    ? null
                    : () {
                        final queue = PlaybackQueueScope.of(context);
                        runQueueAction(
                          context,
                          (onStatus) => queue.startShuffled(
                            hits,
                            playlistName: mood.name,
                            onStatus: onStatus,
                          ),
                        );
                      },
              ),
            ),
          ),
          if (missing > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Utworów, których nie ma w bazie danych na telefonie: $missing — '
                'pojawią się po pobraniu nowszej.',
                style: TextStyle(
                  fontSize: AppFontSize.small,
                  color: palette.textSecondary,
                ),
              ),
            ),
          if (hits.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
              child: Text(
                'Brak utworów. Dodaj je z menu ⋮ utworu: „Dodaj do nastroju”.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
          for (final (i, hit) in hits.indexed)
            SongTile(
              key: ValueKey(hit.mainSong!.id),
              hit: hit,
              queue: hits,
              queueIndex: i,
              playlistName: mood.name,
              trailing: IconButton(
                tooltip: 'Menu utworu (⋮)',
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showSongMenu(context, mood, hit, editable),
              ),
              onLongPress: () => _showSongMenu(context, mood, hit, editable),
            ),
        ],
      ),
    );
  }

  static String _songCount(int n) => switch (n) {
    1 => '1 utwór',
    _ when n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14) =>
      '$n utwory',
    _ => '$n utworów',
  };

  void _showMoodMenu(BuildContext context, Mood mood, List<SearchHit> hits) {
    final origin = QueueOrigin(playlistName: mood.name);
    showMenuSheet(
      context,
      idPrefix: '$_id › Menu (⋮)',
      header: MenuSheetHeader(
        cover: MoodCover(mood: mood),
        title: mood.name,
        subtitle: mood.global ? 'Nastrój globalny' : 'Twój nastrój',
      ),
      entries: [
        if (hits.isNotEmpty) ...[
          MenuSheetEntry(
            Icons.queue_music,
            'Dodaj do kolejki',
            onTap: () => queueSongs(context, hits, next: false, origin: origin),
          ),
          MenuSheetEntry(
            Icons.playlist_play,
            'Odtwórz jako następny',
            onTap: () => queueSongs(context, hits, next: true, origin: origin),
          ),
        ],
        ...customCoverEntries(context, CustomCovers.moodKey(mood)),
        if (!mood.global) ...[
          MenuSheetEntry(
            Icons.edit_outlined,
            'Zmień nazwę',
            onTap: () => _rename(context, mood),
          ),
          MenuSheetEntry(
            Icons.delete_outline,
            'Usuń nastrój',
            onTap: () => _delete(context, mood),
          ),
        ],
      ],
    );
  }

  void _showSongMenu(
    BuildContext context,
    Mood mood,
    SearchHit hit,
    bool editable,
  ) => showSongMenu(
    context,
    hit,
    idPrefix: '$_id › Utwór › Menu (⋮)',
    extra: [
      if (editable)
        MenuSheetEntry(
          Icons.remove_circle_outline,
          'Usuń z tego nastroju',
          onTap: () =>
              MoodLibraryScope.of(context)
                  .setSong(mood, hit.mainSong!.id, false),
        ),
    ],
  );

  Future<void> _rename(BuildContext context, Mood mood) async {
    final moods = MoodLibraryScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: 'Zmień nazwę nastroju',
        hint: 'Nazwa',
        initial: mood.name,
      ),
    );
    if (name == null) return;
    final problem = await moods.rename(mood, name);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  Future<void> _delete(BuildContext context, Mood mood) async {
    final moods = MoodLibraryScope.of(context);
    final covers = CustomCoversScope.maybeOf(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć nastrój?'),
        content: Text(
          mood.phoneOnly
              ? '„${mood.name}” zniknie z telefonu. Utwory zostają.'
              : '„${mood.name}” zniknie na wszystkich urządzeniach konta i z '
                    'MusicDatabase (zostanie tam kopia w archiwum). Utwory zostają.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    await moods.delete(mood);
    await covers?.remove(CustomCovers.moodKey(mood));
    navigator.pop();
  }
}
