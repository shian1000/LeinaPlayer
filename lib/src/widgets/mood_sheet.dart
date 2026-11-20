import 'package:flutter/material.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/mood_filter.dart';
import '../data/moods.dart';
import '../data/text_normalizer.dart';
import '../l10n.dart';
import '../theme.dart';
import 'common.dart';
import 'menu_sheet.dart';
import 'song_cover.dart';
import 'song_names.dart';

/// What stands for a mood (a "Nastrój") everywhere.
const moodIcon = Icons.nightlight;

/// "Utwory bez nastroju" in the mood filter.
const noMoodIcon = Icons.nightlight_outlined;

/// "Dodaj do nastroju" for a song's menu; `null` where there are no moods (widget tests).
MenuSheetEntry? moodMenuEntry(BuildContext context, SearchHit hit) {
  if (MoodLibraryScope.maybeOf(context) == null) return null;
  return MenuSheetEntry(
    moodIcon,
    l10n.moodSheetAddToMood,
    onTap: () => showMoodPicker(context, hit),
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
                title: Text(
                  l10n.moodSheetFilterTitle,
                  style: const TextStyle(
                    fontSize: AppFontSize.emphasis,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  l10n.moodSheetFilterSubtitle,
                  style: TextStyle(color: palette.textSecondary),
                ),
                value: filter.enabled,
                onChanged: filter.setEnabled,
              ),
              const Divider(),
              CheckboxListTile(
                contentPadding: padding,
                secondary: const Icon(noMoodIcon),
                title: Text(l10n.moodSheetUntagged),
                subtitle: Text(
                  l10n.moodSheetUntaggedSubtitle,
                  style: TextStyle(color: palette.textSecondary),
                ),
                value: filter.untagged,
                onChanged: (ticked) => filter.setUntagged(ticked!),
              ),
              if (moods.userMoods.isNotEmpty) ...[
                SectionTitle(l10n.moodSheetYourMoods),
                for (final mood in moods.userMoods) tile(mood),
              ],
              if (moods.globalMoods.isNotEmpty) ...[
                SectionTitle(l10n.moodSheetGlobalMoods),
                for (final mood in moods.globalMoods) tile(mood),
              ],
              SectionTitle(l10n.moodSheetAddedOutside),
              RadioGroup<bool>(
                groupValue: filter.offWhenAdded,
                onChanged: (value) => filter.setOffWhenAdded(value!),
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      contentPadding: padding,
                      value: true,
                      title: Text(l10n.moodSheetTurnOffFilter),
                      subtitle: Text(
                        l10n.moodSheetTurnOffFilterSubtitle,
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ),
                    RadioListTile<bool>(
                      contentPadding: padding,
                      value: false,
                      title: Text(l10n.moodSheetSkipSong),
                      subtitle: Text(
                        l10n.moodSheetSkipSongSubtitle,
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
/// with [hits]; says why when it can't. Returns whether it was made.
Future<bool> createMood(
  BuildContext context, {
  Iterable<SearchHit> hits = const [],
  String name = '',
}) async {
  final moods = MoodLibraryScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final typed = await showDialog<String>(
    context: context,
    builder: (_) => TextInputDialog(
      title: l10n.moodSheetNewMood,
      hint: l10n.moodSheetNewMoodHint,
      initial: name,
    ),
  );
  if (typed == null) return false;
  final problem = await moods.create(typed, hits: hits);
  if (problem != null) {
    messenger.showSnackBar(SnackBar(content: Text(problem)));
  }
  return problem == null;
}

/// The moods [hit] can go into, each ticked when it's in it: the user's own and, with the
/// permission and a song music.db has, the global ones. Ticking changes the mood right away.
Future<void> showMoodPicker(BuildContext context, SearchHit hit) {
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
            Widget tile(Mood mood) => CheckboxListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              secondary: const Icon(moodIcon),
              title: Text(mood.name),
              value: mood.has(hit),
              onChanged: (inMood) => moods.setHits(mood, [hit], inMood!),
            );
            return _MoodPickerBody(
              header: [
                MenuSheetHeader(
                  cover: SongCover(cover: CoverRequest.of(hit)),
                  title: l10n.moodSheetAddToMood,
                  subtitle:
                      '${hit.shownTitle(context)} • ${hit.shownArtist(context)}',
                ),
              ],
              onNewMood: (name) =>
                  createMood(sheetContext, hits: [hit], name: name),
              userMoods: moods.userMoods,
              globalMoods: hit.mainSong != null && moods.canEditGlobal
                  ? moods.globalMoods
                  : const [],
              tile: tile,
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
    l10n.moodSheetMoodForAll,
    onTap: () => showMoodPickerForAll(context, hits, title: title),
  );
}

/// The moods all of [hits] can go into, ticked when all of them are in it (a dash when some
/// are). Tapping one asks first, then puts all of them in — or, when all are in already, takes
/// them all out. A global mood holds only MusicDatabase songs; the rest are left out of it.
Future<void> showMoodPickerForAll(
  BuildContext context,
  List<SearchHit> hits, {
  required String title,
}) {
  final songs = {
    for (final hit in hits) hit.mainSong?.id ?? moodTrackKey(hit): hit,
  }.values.toList();
  final inDatabase = songs.where((hit) => hit.mainSong != null).toList();
  final outside = songs.length - inDatabase.length;
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
              final fitting = mood.global ? inDatabase : songs;
              final inMood = fitting.where(mood.has).length;
              final all = fitting.isNotEmpty && inMood == fitting.length;
              return CheckboxListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                secondary: const Icon(moodIcon),
                title: Text(mood.name),
                subtitle: inMood == 0 || all
                    ? null
                    : Text(
                        l10n.moodSheetSomeInMood(inMood, fitting.length),
                        style: TextStyle(color: palette.textSecondary),
                      ),
                tristate: true,
                value: all ? true : (inMood == 0 ? false : null),
                onChanged: fitting.isEmpty
                    ? null
                    : (_) => _confirmForAll(
                        sheetContext,
                        moods,
                        mood,
                        fitting,
                        add: !all,
                        changed: all ? fitting.length : fitting.length - inMood,
                      ),
              );
            }

            return _MoodPickerBody(
              header: [
                MenuSheetHeader(
                  cover: const Icon(moodIcon, size: 40),
                  title: l10n.moodSheetMoodForAll,
                  subtitle: title,
                ),
                if (outside > 0 &&
                    moods.canEditGlobal &&
                    moods.globalMoods.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      l10n.moodSheetOutsideNotGlobal(outside),
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  ),
              ],
              onNewMood: (name) =>
                  createMood(sheetContext, hits: songs, name: name),
              userMoods: moods.userMoods,
              globalMoods: moods.canEditGlobal ? moods.globalMoods : const [],
              tile: tile,
            );
          },
        ),
      );
    },
  );
}

/// A mood picker's sheet: [header], a search over the moods' names (kept on top while the list
/// scrolls), "Nowy nastrój" — named as searched — and the moods that match, own ones first.
class _MoodPickerBody extends StatefulWidget {
  const _MoodPickerBody({
    required this.header,
    required this.onNewMood,
    required this.userMoods,
    required this.globalMoods,
    required this.tile,
  });

  final List<Widget> header;
  final void Function(String name) onNewMood;
  final List<Mood> userMoods;
  final List<Mood> globalMoods;
  final Widget Function(Mood mood) tile;

  @override
  State<_MoodPickerBody> createState() => _MoodPickerBodyState();
}

class _MoodPickerBodyState extends State<_MoodPickerBody> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final words = normalizeForSearch(_search.text).split(' ')
      ..removeWhere((w) => w.isEmpty);
    List<Mood> matching(List<Mood> moods) => [
      for (final mood in moods)
        if (words.every(normalizeForSearch(mood.name).contains)) mood,
    ];
    final userMoods = matching(widget.userMoods);
    final globalMoods = matching(widget.globalMoods);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...widget.header,
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: l10n.moodSheetSearch,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.moodSheetClearSearch,
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: Icon(Icons.add, color: palette.textSecondary),
                  title: Text(l10n.moodSheetNewMood),
                  onTap: () => widget.onNewMood(_search.text.trim()),
                ),
                if (userMoods.isNotEmpty) ...[
                  SectionTitle(l10n.moodSheetYourMoods),
                  for (final mood in userMoods) widget.tile(mood),
                ],
                if (globalMoods.isNotEmpty) ...[
                  SectionTitle(l10n.moodSheetGlobalMoods),
                  for (final mood in globalMoods) widget.tile(mood),
                ],
                if (words.isNotEmpty &&
                    userMoods.isEmpty &&
                    globalMoods.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Text(
                      l10n.moodSheetNoMatch(_search.text.trim()),
                      style: TextStyle(color: palette.textSecondary),
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

/// "Czy na pewno?" before changing [changed] songs of [mood] at once.
Future<void> _confirmForAll(
  BuildContext context,
  MoodLibrary moods,
  Mood mood,
  List<SearchHit> hits, {
  required bool add,
  required int changed,
}) async {
  final question = add
      ? l10n.moodSheetConfirmAdd(l10n.songsCount(changed), mood.name)
      : l10n.moodSheetConfirmRemove(l10n.songsCount(changed), mood.name);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.moodSheetAreYouSure),
      content: Text(question),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(add ? l10n.commonAdd : l10n.commonDelete),
        ),
      ],
    ),
  );
  if (confirmed ?? false) await moods.setHits(mood, hits, add);
}
