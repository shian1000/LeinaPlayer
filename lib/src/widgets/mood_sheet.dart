import 'package:flutter/material.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/moods.dart';
import '../theme.dart';
import 'common.dart';
import 'menu_sheet.dart';
import 'song_cover.dart';

/// "Dodaj do nastroju" for a song's menu; `null` where there are no moods (widget tests). Only
/// MusicDatabase songs can be in a mood, so for any other it says so.
MenuSheetEntry? moodMenuEntry(BuildContext context, SearchHit hit) {
  if (MoodLibraryScope.maybeOf(context) == null) return null;
  return MenuSheetEntry(
    Icons.mood,
    'Dodaj do nastroju',
    onTap: () {
      if (hit.mainSong != null) {
        showMoodPicker(context, hit);
        return;
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Do nastroju można dodać tylko utwory z bazy danych MusicDatabase — '
              'tego jeszcze w niej nie ma.',
            ),
          ),
        );
    },
  );
}

/// Asks for a name and makes a mood of the logged-in user (logged out: only on this phone)
/// with [songIds]; says why when it can't. Returns whether it was made.
Future<bool> createMood(
  BuildContext context, {
  Iterable<int> songIds = const [],
}) async {
  final moods = MoodLibraryScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final name = await showDialog<String>(
    context: context,
    builder: (_) => const TextInputDialog(
      title: 'Nowy nastrój',
      hint: 'Nazwa, np. Siłownia',
      initial: '',
    ),
  );
  if (name == null) return false;
  final problem = await moods.create(name, songIds: songIds);
  if (problem != null) {
    messenger.showSnackBar(SnackBar(content: Text(problem)));
  }
  return problem == null;
}

/// The moods [hit] can go into, each ticked when it's in it: the user's own and, with the
/// permission, the global ones. Ticking changes the mood right away.
Future<void> showMoodPicker(BuildContext context, SearchHit hit) {
  final songId = hit.mainSong!.id;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final moods = MoodLibraryScope.of(context);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
        ),
        child: ListenableBuilder(
          listenable: moods,
          builder: (sheetContext, _) {
            final palette = sheetContext.palette;
            Widget tile(Mood mood) => CheckboxListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              secondary: const Icon(Icons.mood),
              title: Text(mood.name),
              value: mood.songIds.contains(songId),
              onChanged: (inMood) => moods.setSong(mood, songId, inMood!),
            );
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                MenuSheetHeader(
                  cover: SongCover(cover: CoverRequest.of(hit)),
                  title: 'Dodaj do nastroju',
                  subtitle: '${hit.title} • ${hit.artistLabel}',
                ),
                const Divider(),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: Icon(Icons.add, color: palette.textSecondary),
                  title: const Text('Nowy nastrój'),
                  onTap: () => createMood(sheetContext, songIds: [songId]),
                ),
                if (moods.userMoods.isNotEmpty) ...[
                  const SectionTitle('Twoje nastroje'),
                  for (final mood in moods.userMoods) tile(mood),
                ],
                if (moods.canEditGlobal && moods.globalMoods.isNotEmpty) ...[
                  const SectionTitle('Globalne'),
                  for (final mood in moods.globalMoods) tile(mood),
                ],
              ],
            );
          },
        ),
      );
    },
  );
}
