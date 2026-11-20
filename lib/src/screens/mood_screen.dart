import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/library_folders.dart';
import '../data/local_library.dart';
import '../data/moods.dart';
import '../data/song_catalog.dart';
import '../data/text_normalizer.dart';
import '../data/youtube_library.dart';
import '../l10n.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/collection_cover.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/folder_sheet.dart';
import '../widgets/mood_sheet.dart';
import '../widgets/playlist_picker.dart';
import '../widgets/scrolling_text.dart';
import '../widgets/song_selection.dart';
import '../widgets/song_tile.dart';
import 'song_search_screen.dart';

const _id = 'Nastrój';

/// One mood ("Nastrój", [ADR 0008](../../../docs/decisions/0008-moods.md)): its songs by title,
/// "Odtwórz losowo", and — for the user's own mood, or a global one with the permission —
/// taking songs out.
class MoodScreen extends StatefulWidget {
  const MoodScreen({super.key, required this.mood});

  final Mood mood;

  static Future<void> open(BuildContext context, Mood mood) {
    LibraryFoldersScope.read(context)?.opened(mood.key);
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => MoodScreen(mood: mood)));
  }

  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends State<MoodScreen> {
  /// `null` while the search field is closed.
  String? _query;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final moods = MoodLibraryScope.of(context);
    final mood = moods.current(widget.mood);
    if (mood == null) {
      return Scaffold(
        appBar: AppBar(title: ScrollingText(widget.mood.name)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              l10n.moodScreenGone,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary),
            ),
          ),
        ),
      );
    }
    final catalog = SongCatalogScope.of(context);
    final hits = moodHits(
      mood,
      catalog,
      LocalLibraryScope.of(context),
      YouTubeLibraryScope.of(context),
    );
    final words = normalizeForSearch(_query).split(' ')
      ..removeWhere((w) => w.isEmpty);
    final shown = [
      for (final (i, hit) in hits.indexed)
        if (words.every(
          normalizeForSearch('${hit.title} ${hit.artistLabel}').contains,
        ))
          (i, hit),
    ];
    final editable = !mood.global || moods.canEditGlobal;
    final missing = mood.songIds.where((id) => catalog.byId(id) == null).length;
    return Scaffold(
      appBar: AppBar(
        title: _query == null
            ? ScrollingText(mood.name)
            : TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.moodScreenSearch,
                  border: InputBorder.none,
                ),
                onChanged: (text) => setState(() => _query = text),
              ),
        actions: [
          if (_query?.trim().isNotEmpty ?? false)
            SearchEverywhereButton(query: _query!),
          IconButton(
            tooltip: _query == null
                ? l10n.moodScreenSearch
                : l10n.moodScreenCloseSearch,
            icon: Icon(_query == null ? Icons.search : Icons.close),
            onPressed: () =>
                setState(() => _query = _query == null ? '' : null),
          ),
          IconButton(
            tooltip: l10n.moodScreenMoodMenu,
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showMoodMenu(context, mood, hits),
          ),
        ],
      ),
      body: SongSelectionArea(
        all: () => {for (final hit in hits) SongSelection.keyOf(hit): hit},
        child: ListView(
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
                        ScrollingText(
                          mood.name,
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: AppFontSize.largeTitle,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${mood.global ? l10n.moodScreenGlobalMood : l10n.moodScreenOwnMood} • '
                          '${l10n.songsCount(hits.length)}',
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
                  label: Text(l10n.moodScreenShuffle),
                  onPressed: hits.isEmpty
                      ? null
                      : () {
                          final queue = PlaybackQueueScope.of(context);
                          runQueueAction(
                            context,
                            (onStatus) => queue.startShuffled(
                              hits,
                              playlistName: mood.name,
                              moodKey: mood.key,
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
                  l10n.moodScreenMissing(missing),
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
                  l10n.moodScreenEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textSecondary),
                ),
              ),
            for (final (i, hit) in shown)
              SongTile(
                key: ValueKey(SongSelection.keyOf(hit)),
                hit: hit,
                queue: hits,
                queueIndex: i,
                playlistName: mood.name,
                moodKey: mood.key,
                trailing: IconButton(
                  tooltip: l10n.moodScreenSongMenu,
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showSongMenu(context, mood, hit, editable),
                ),
                onLongPress: () => _showSongMenu(context, mood, hit, editable),
                onSwipeRemove: editable
                    ? () => _swipeRemove(context, mood, hit)
                    : null,
                swipeRemoveLabel: l10n.moodScreenRemoveFromMood,
              ),
          ],
        ),
      ),
    );
  }

  void _showMoodMenu(BuildContext context, Mood mood, List<SearchHit> hits) {
    final origin = QueueOrigin(playlistName: mood.name, moodKey: mood.key);
    showMenuSheet(
      context,
      idPrefix: '$_id › Menu (⋮)',
      header: MenuSheetHeader(
        cover: MoodCover(mood: mood),
        title: mood.name,
        subtitle: mood.global
            ? l10n.moodScreenGlobalMood
            : l10n.moodScreenOwnMood,
      ),
      entries: [
        if (hits.isNotEmpty) ...[
          MenuSheetEntry(
            Icons.queue_music,
            l10n.moodScreenAddToQueue,
            onTap: () => queueSongs(context, hits, next: false, origin: origin),
          ),
          MenuSheetEntry(
            Icons.playlist_play,
            l10n.moodScreenPlayNext,
            onTap: () => queueSongs(context, hits, next: true, origin: origin),
          ),
          ?moodForAllEntry(context, hits, title: mood.name),
          ?playlistMenuEntry(
            context,
            hits,
            label: l10n.moodScreenAddToPlaylist,
          ),
        ],
        ?moveToFolderEntry(context, mood.key),
        ...customCoverEntries(
          context,
          current: mood.cover,
          onSet: (hash) => MoodLibraryScope.of(context).setCover(mood, hash),
        ),
        if (!mood.global) ...[
          MenuSheetEntry(
            Icons.edit_outlined,
            l10n.moodScreenRename,
            onTap: () => _rename(context, mood),
          ),
          MenuSheetEntry(
            Icons.delete_outline,
            l10n.moodScreenDelete,
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
          l10n.moodScreenRemoveFromMood,
          onTap: () => MoodLibraryScope.of(context).setHits(mood, [hit], false),
        ),
    ],
  );

  /// Dragged left: out of the mood, with "Cofnij".
  void _swipeRemove(BuildContext context, Mood mood, SearchHit hit) {
    final moods = MoodLibraryScope.of(context);
    moods.setHits(mood, [hit], false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.moodScreenRemoved(hit.title)),
          persist: false,
          action: SnackBarAction(
            label: l10n.commonUndo,
            onPressed: () => moods.setHits(mood, [hit], true),
          ),
        ),
      );
  }

  Future<void> _rename(BuildContext context, Mood mood) async {
    final moods = MoodLibraryScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: l10n.moodScreenRenameTitle,
        hint: l10n.moodScreenNameHint,
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
    final folders = LibraryFoldersScope.maybeOf(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.moodScreenDeleteTitle),
        content: Text(
          mood.phoneOnly
              ? l10n.moodScreenDeletePhoneOnly(mood.name)
              : l10n.moodScreenDeleteSynced(mood.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    await moods.delete(mood);
    await folders?.move(mood.key, null);
    navigator.pop();
  }
}
