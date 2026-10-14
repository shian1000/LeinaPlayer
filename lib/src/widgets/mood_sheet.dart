import 'package:flutter/material.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/mood_filter.dart';
import '../data/moods.dart';
import '../theme.dart';
import 'common.dart';
import 'menu_sheet.dart';
import 'song_cover.dart';
import 'song_names.dart';

/// What stands for a mood (a "Nastrój") everywhere.
const moodIcon = Icons.nightlight;

/// "Utwory bez nastroju" in the mood filter.
const noMoodIcon = Icons.nightlight_outlined;

/// "Dodaj do nastroju" for a song's menu; `null` where there are no moods (widget tests). Only
/// MusicDatabase songs can be in a mood, so for any other it says so.
MenuSheetEntry? moodMenuEntry(BuildContext context, SearchHit hit) {
  if (MoodLibraryScope.maybeOf(context) == null) return null;
  return MenuSheetEntry(
    moodIcon,
    'Dodaj do nastroju',
    onTap: () => openMoodPicker(context, hit),
  );
}

/// [showMoodPicker] for [hit], or why it can't be in a mood: only MusicDatabase songs can.
void openMoodPicker(BuildContext context, SearchHit hit) {
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
}

/// "Filtr nastrojów": the switch, "Bez nastroju" and every mood shown, each ticked when it's in
/// the filter; changes apply to the queue right away.
Future<void> showMoodFilterSheet(BuildContext context) {
  final filter = MoodFilterScope.maybeOf(context)!;
  final moods = MoodLibraryScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([filter, moods]),
        builder: (sheetContext, _) {
          final palette = sheetContext.palette;
          const padding = EdgeInsets.symmetric(horizontal: 20);
          Widget tile(Mood mood) => CheckboxListTile(
            contentPadding: padding,
            secondary: const Icon(moodIcon),
            title: Text(mood.name),
            value: filter.moods.contains(mood.key),
            onChanged: (ticked) => filter.setMood(mood.key, ticked!),
          );
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              SwitchListTile(
                contentPadding: padding,
                title: const Text(
                  'Filtr nastrojów',
                  style: TextStyle(
                    fontSize: AppFontSize.emphasis,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  'Kolejka pomija i ukrywa utwory spoza zaznaczonych nastrojów.',
                  style: TextStyle(color: palette.textSecondary),
                ),
                value: filter.enabled,
                onChanged: filter.setEnabled,
              ),
              const Divider(),
              CheckboxListTile(
                contentPadding: padding,
                secondary: const Icon(noMoodIcon),
                title: const Text('Utwory bez nastroju'),
                subtitle: Text(
                  'Też utwory spoza bazy danych MusicDatabase',
                  style: TextStyle(color: palette.textSecondary),
                ),
                value: filter.untagged,
                onChanged: (ticked) => filter.setUntagged(ticked!),
              ),
              if (moods.userMoods.isNotEmpty) ...[
                const SectionTitle('Twoje nastroje'),
                for (final mood in moods.userMoods) tile(mood),
              ],
              if (moods.globalMoods.isNotEmpty) ...[
                const SectionTitle('Globalne'),
                for (final mood in moods.globalMoods) tile(mood),
              ],
              const SectionTitle('Utwór dodany spoza filtra'),
              RadioGroup<bool>(
                groupValue: filter.offWhenAdded,
                onChanged: (value) => filter.setOffWhenAdded(value!),
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      contentPadding: padding,
                      value: true,
                      title: const Text('Wyłącz filtr'),
                      subtitle: Text(
                        'Odznacza wszystko — kolejka gra jak bez filtra',
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ),
                    RadioListTile<bool>(
                      contentPadding: padding,
                      value: false,
                      title: const Text('Pomiń utwór'),
                      subtitle: Text(
                        'Trafia do kolejki, ale jest ukryty i pomijany',
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
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
              secondary: const Icon(moodIcon),
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
                  subtitle:
                      '${hit.shownTitle(context)} • ${hit.shownArtist(context)}',
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

/// "Nastrój dla wszystkich" for a list of songs' menu (a playlist, a mood, the queue); `null`
/// where there are no moods (widget tests) or no songs.
MenuSheetEntry? moodForAllEntry(
  BuildContext context,
  List<SearchHit> hits, {
  required String title,
}) {
  if (MoodLibraryScope.maybeOf(context) == null || hits.isEmpty) return null;
  return MenuSheetEntry(
    moodIcon,
    'Nastrój dla wszystkich utworów',
    onTap: () => showMoodPickerForAll(context, hits, title: title),
  );
}

/// The moods all of [hits] can go into, ticked when all of them are in it (a dash when some
/// are). Tapping one asks first, then puts all of them in — or, when all are in already, takes
/// them all out. Only MusicDatabase songs can be in a mood; the rest are left out.
Future<void> showMoodPickerForAll(
  BuildContext context,
  List<SearchHit> hits, {
  required String title,
}) {
  final songIds = {for (final hit in hits) ?hit.mainSong?.id};
  final outside = hits.where((hit) => hit.mainSong == null).length;
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
            Widget tile(Mood mood) {
              final inMood = songIds.where(mood.songIds.contains).length;
              final all = songIds.isNotEmpty && inMood == songIds.length;
              return CheckboxListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                secondary: const Icon(moodIcon),
                title: Text(mood.name),
                subtitle: inMood == 0 || all
                    ? null
                    : Text(
                        '$inMood z ${songIds.length}',
                        style: TextStyle(color: palette.textSecondary),
                      ),
                tristate: true,
                value: all ? true : (inMood == 0 ? false : null),
                onChanged: songIds.isEmpty
                    ? null
                    : (_) => _confirmForAll(
                        sheetContext,
                        moods,
                        mood,
                        songIds,
                        add: !all,
                        changed: all ? songIds.length : songIds.length - inMood,
                      ),
              );
            }

            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                MenuSheetHeader(
                  cover: const Icon(moodIcon, size: 40),
                  title: 'Nastrój dla wszystkich utworów',
                  subtitle: title,
                ),
                if (songIds.isEmpty || outside > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      songIds.isEmpty
                          ? 'Żadnego z tych utworów nie ma w bazie danych '
                                'MusicDatabase — tylko takie mogą być w nastroju.'
                          : 'Utwory spoza bazy danych MusicDatabase ($outside) '
                                'zostaną pominięte.',
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  ),
                const Divider(),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: Icon(Icons.add, color: palette.textSecondary),
                  title: const Text('Nowy nastrój'),
                  enabled: songIds.isNotEmpty,
                  onTap: () => createMood(sheetContext, songIds: songIds),
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

/// "Czy na pewno?" before changing [changed] songs of [mood] at once.
Future<void> _confirmForAll(
  BuildContext context,
  MoodLibrary moods,
  Mood mood,
  Set<int> songIds, {
  required bool add,
  required int changed,
}) async {
  final question = add
      ? 'Dodać $changed ${songsWord(changed)} do nastroju „${mood.name}”?'
      : 'Usunąć $changed ${songsWord(changed)} z nastroju „${mood.name}”?';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Czy na pewno?'),
      content: Text(question),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(add ? 'Dodaj' : 'Usuń'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) await moods.setSongs(mood, songIds, add);
}
