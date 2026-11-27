import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/mood_filter.dart';
import '../data/moods.dart';
import '../data/playlist_library.dart';
import '../data/source_settings.dart';
import '../data/youtube_library.dart';
import '../l10n.dart';
import '../playback/mood_recorder.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/scrolling_text.dart';
import '../widgets/song_tile.dart';
import '../data/album_covers.dart';
import '../widgets/common.dart';
import '../widgets/mood_sheet.dart';
import '../widgets/queue_toast.dart';
import '../widgets/song_cover.dart';
import '../widgets/swipe_actions.dart';
import 'mood_screen.dart';
import 'playlist_screen.dart';
import '../widgets/song_names.dart';
import '../widgets/song_selection.dart';

/// "Kolejka", opened from the full player: the last few songs before the current one (above,
/// scrolled to; tapping one goes back to it), the song playing, then everything after it, under
/// a heading for each run of songs queued from the same place — songs added one by one, a
/// playlist added as a whole, the playlist / results the queue was filled with. Tapping a song
/// plays it (skipping the ones before it); the handle moves it; dragging a row left takes it out,
/// right makes it play next or moves it to the end ([SourceSettings.swipePlaysNext]). A long
/// press ticks songs to come, for the bar of what can be done to all of them — the queue's own
/// moves, and "Więcej", the menu a long press opens on the other rows. A tapped heading folds
/// its songs away; a folded group moves as a whole by its handle. The queue that playing
/// something else replaced comes back with "Przywróć poprzednią kolejkę".
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  /// How many of the songs before the current one are shown (user's choice).
  static const previousShown = 5;

  static const _nowPlayingKey = ValueKey('now playing');

  /// A row being moved by its handle, lifted like in [ReorderableListView].
  static Widget _liftedRow(
    Widget child,
    int index,
    Animation<double> animation,
  ) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) => Material(
      elevation: 6 * Curves.easeInOut.transform(animation.value),
      child: child,
    ),
    child: child,
  );

  static Future<void> open(BuildContext context) {
    QueueToastScope.maybeOf(context)?.hide();
    return Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => const QueueScreen()));
  }

  /// The heading over a run of songs queued from [origin].
  static String heading(PlaybackQueue queue, QueueOrigin? origin) {
    if (origin == null) return l10n.queueScreenNextInQueue;
    final name = origin.playlistName;
    if (identical(origin, queue.mainOrigin)) {
      final query = origin.searchQuery;
      return name ??
          (query != null
              ? l10n.queueScreenNextFromSearch(query)
              : l10n.queueScreenNext);
    }
    // Just the playlist's name: "Z playlisty: …" left the long ones no room (user's request).
    return name ?? l10n.queueScreenNextInQueue;
  }

  /// Saves [songs] (every song listed: the shown previous ones, the one playing, what comes
  /// next) as a new Biblioteka playlist, named by the user.
  static Future<void> _saveAsPlaylist(
    BuildContext context,
    List<SearchHit> songs,
  ) async {
    final library = PlaylistLibraryScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = (await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: l10n.queueScreenSaveAsPlaylist,
        hint: l10n.queueScreenPlaylistName,
        initial: '',
      ),
    ))?.trim();
    if (name == null || name.isEmpty) return;
    final playlist = await library.create(name, songs);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            l10n.queueScreenSaved(playlist.name, trackCountLabel(songs.length)),
          ),
          // With an action a SnackBar otherwise stays until closed by hand.
          persist: false,
          action: SnackBarAction(
            label: l10n.queueScreenShow,
            onPressed: () => navigator.push(
              MaterialPageRoute<void>(
                builder: (_) => PlaylistScreen(playlist: playlist),
              ),
            ),
          ),
        ),
      );
  }

  /// Takes [entries] out of the queue, with "Cofnij" in the note.
  static void _remove(
    BuildContext context,
    PlaybackQueue queue,
    List<QueueEntry> entries,
  ) {
    final removed = [
      for (final entry in entries)
        if (queue.remove(entry) case final at when at >= 0) (entry, at),
    ];
    if (removed.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            removed.length == 1
                ? l10n.queueScreenRemoved(removed.single.$1.hit.title)
                : l10n.queueScreenRemovedCount(removed.length),
          ),
          // With an action a SnackBar otherwise stays until closed by hand.
          persist: false,
          action: SnackBarAction(
            label: l10n.commonUndo,
            onPressed: () {
              for (final (entry, at) in removed.reversed) {
                queue.reinsert(entry, at);
              }
            },
          ),
        ),
      );
  }

  /// The bar under ticked songs: moves within the queue instead of queueing them once more.
  static List<SongSelectionAction> _selectionActions(
    BuildContext context,
    PlaybackQueue queue,
  ) {
    // In the queue's order, whatever order they were ticked in.
    List<QueueEntry> entries(Map<Object, SearchHit> ticked) => [
      for (final entry in queue.upcoming)
        if (ticked.containsKey(entry.key)) entry,
    ];
    return [
      SongSelectionAction(
        icon: Icons.playlist_remove,
        label: l10n.queueScreenTickedRemove,
        onPressed: (context, ticked) =>
            _remove(context, queue, entries(ticked)),
      ),
      SongSelectionAction(
        icon: Icons.playlist_play,
        label: l10n.songSelectionPlayNext,
        onPressed: (context, ticked) {
          for (final entry in entries(ticked).reversed) {
            queue.move(entry, 0);
          }
        },
      ),
      SongSelectionAction(
        icon: Icons.low_priority,
        label: l10n.queueScreenTickedToEnd,
        onPressed: (context, ticked) {
          for (final entry in entries(ticked)) {
            queue.move(entry, queue.upcoming.length);
          }
        },
      ),
      ?SongSelectionAction.toPlaylist(context),
      ?SongSelectionAction.toMood(context),
      SongSelectionAction(
        icon: Icons.more_vert,
        label: l10n.queueScreenTickedMore,
        onlyOne: true,
        onPressed: (context, ticked) => showSongMenu(
          context,
          ticked.values.single,
          idPrefix: 'Kolejka › Utwór › Menu (⋮)',
        ),
      ),
    ];
  }

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  // Kept while the app runs, so the queue opens folded as it was left; groups by their origin,
  // songs added one by one (no origin) all as one.
  static final _folded = Expando<bool>();
  static bool _singlesFolded = false;

  bool _isFolded(QueueOrigin? origin) =>
      origin == null ? _singlesFolded : _folded[origin] ?? false;

  void _toggleFolded(QueueOrigin? origin) => setState(() {
    if (origin == null) {
      _singlesFolded = !_singlesFolded;
    } else {
      _folded[origin] = !_isFolded(origin);
    }
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final queue = PlaybackQueueScope.of(context);
    final current = queue.current;
    final upcoming = queue.upcoming;
    final previous = queue.history.reversed
        .take(QueueScreen.previousShown)
        .toList();
    final moodFilter = MoodFilterScope.maybeOf(context);
    final filtering = moodFilter?.active ?? false;

    // Headings and songs, as the list shows them: a folded group only by its heading.
    final items = <Object>[];
    var clearShown = false;
    for (final (i, entry) in upcoming.indexed) {
      if (i == 0 || !identical(upcoming[i - 1].origin, entry.origin)) {
        items.add((
          text: QueueScreen.heading(queue, entry.origin),
          clear: !clearShown && !queue.isMain(entry),
          songs: upcoming
              .skip(i)
              .takeWhile((e) => identical(e.origin, entry.origin))
              .toList(),
        ));
        if (!queue.isMain(entry)) clearShown = true;
      }
      if (!_isFolded(entry.origin)) items.add(entry);
    }

    // How many songs come before [to] in [rest], a folded group's counted too.
    int songsBefore(List<Object> rest, int to) => rest
        .take(to)
        .map(
          (item) => item is QueueEntry
              ? 1
              : item is _Group && _isFolded(item.songs.first.origin)
              ? item.songs.length
              : 0,
        )
        .fold(0, (a, b) => a + b);

    void reorder(int from, int to) {
      final item = items[from];
      final rest = [...items]..removeAt(from);
      if (item is QueueEntry) {
        queue.move(item, songsBefore(rest, to));
      } else if (item is _Group) {
        queue.moveGroup(item.songs, songsBefore(rest, to));
      }
    }

    // Its own messenger: "Usunięto z kolejki" goes when the screen closes, instead of covering
    // the full player's buttons.
    return ScaffoldMessenger(
      child: SongSelectionArea(
        all: () => {for (final entry in queue.upcoming) entry.key: entry.hit},
        untickGone: true,
        actions: (context) => QueueScreen._selectionActions(context, queue),
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: palette.surface,
            title: Text(l10n.queueScreenTitle),
            actions: [
              if (queue.replaced case final replaced?)
                IconButton(
                  tooltip: l10n.queueScreenRestorePrevious(
                    [
                      ?replaced.name,
                      trackCountLabel(replaced.songCount),
                    ].join(', '),
                  ),
                  icon: const Icon(Icons.restore),
                  onPressed: () => runQueueAction(
                    context,
                    (onStatus) => queue.playReplaced(onStatus: onStatus),
                  ),
                ),
              if (current != null &&
                  PlaylistLibraryScope.maybeOf(context) != null)
                // Its context is under the screen's own messenger, which shows the note.
                Builder(
                  builder: (context) => IconButton(
                    tooltip: l10n.queueScreenSaveAsPlaylist,
                    icon: const Icon(Icons.playlist_add),
                    onPressed: () => QueueScreen._saveAsPlaylist(context, [
                      for (final entry in previous.reversed) entry.hit,
                      current,
                      for (final entry in upcoming) entry.hit,
                    ]),
                  ),
                ),
              if (current != null && MoodLibraryScope.maybeOf(context) != null)
                IconButton(
                  tooltip: l10n.queueScreenMoodForAll,
                  icon: const Icon(moodIcon),
                  // The songs listed: the ones the mood filter hides stay out.
                  onPressed: () => showMoodPickerForAll(context, [
                    for (final entry in previous.reversed) entry.hit,
                    current,
                    for (final entry in upcoming) entry.hit,
                  ], title: l10n.queueScreenAllVisibleSongs),
                ),
            ],
          ),
          body: CustomScrollView(
            // Opens at the song playing; the songs before it are above, scrolled to.
            center: QueueScreen._nowPlayingKey,
            slivers: [
              // Before the centre the list grows upwards: the newest song is first.
              SliverList.list(
                children: [
                  for (final entry in previous)
                    _PreviousRow(key: ValueKey(entry.key), entry: entry),
                  if (queue.hasPrevious) _Heading(l10n.queueScreenPrevious),
                ],
              ),
              SliverToBoxAdapter(
                key: QueueScreen._nowPlayingKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Heading(l10n.queueScreenNowPlaying),
                    if (current != null)
                      _QueueRow(hit: current, isCurrent: true)
                    else
                      _Empty(l10n.queueScreenNothingPlaying),
                    if (upcoming.isEmpty && filtering)
                      _Empty(l10n.queueScreenEndFiltered)
                    else if (upcoming.isEmpty)
                      _Empty(l10n.queueScreenEnd),
                  ],
                ),
              ),
              SliverReorderableList(
                itemCount: items.length,
                onReorderItem: reorder,
                proxyDecorator: QueueScreen._liftedRow,
                itemBuilder: (context, i) {
                  final item = items[i];
                  if (item is QueueEntry) {
                    return _UpcomingRow(
                      key: ValueKey(item.key),
                      entry: item,
                      index: i,
                    );
                  }
                  final heading = item as _Group;
                  final group = heading.songs;
                  final origin = group.first.origin;
                  final folded = _isFolded(origin);
                  final playlistGroup = origin?.playlistName != null;
                  final tile = _Heading(
                    heading.text,
                    folded: folded,
                    count: group.length,
                    onTap: () => _toggleFolded(origin),
                    action: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // A playlist's songs as a group of their own: shuffled, played once
                        // more or taken out at once (Juxtopposed's redesign).
                        if (playlistGroup) ...[
                          IconButton(
                            tooltip: l10n.queueScreenShuffleGroup,
                            icon: const Icon(Icons.shuffle, size: 20),
                            onPressed: () => queue.shuffleGroup(group),
                          ),
                          IconButton(
                            tooltip: l10n.queueScreenRepeatGroup,
                            icon: const Icon(Icons.repeat, size: 20),
                            onPressed: () => queue.repeatGroup(group),
                          ),
                          IconButton(
                            tooltip: l10n.queueScreenRemoveGroup,
                            icon: const Icon(Icons.playlist_remove, size: 22),
                            onPressed: () =>
                                QueueScreen._remove(context, queue, group),
                          ),
                        ],
                        if (heading.clear)
                          TextButton(
                            onPressed: queue.clearAdded,
                            child: Text(l10n.queueScreenClear),
                          ),
                        // Only folded: an open group's songs would stay behind while its
                        // heading moved.
                        if (folded)
                          ReorderableDragStartListener(
                            index: i,
                            child: Semantics(
                              label: l10n.queueScreenDragGroup,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Icon(Icons.drag_handle),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                  return KeyedSubtree(
                    key: ValueKey('heading ${group.first.key}'),
                    child: tile,
                  );
                },
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          ),
          // While songs are ticked their bar takes its place.
          bottomNavigationBar: Builder(
            builder: (context) =>
                (SongSelectionScope.maybeOf(context)?.active ?? false)
                ? const SizedBox.shrink()
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () => queue.setShuffle(!queue.shuffle),
                            icon: Icon(
                              Icons.shuffle,
                              color: queue.shuffle ? palette.accent : null,
                            ),
                            label: Text(
                              queue.shuffle
                                  ? l10n.queueScreenShuffleOn
                                  : l10n.queueScreenShuffleOff,
                              style: TextStyle(
                                color: queue.shuffle
                                    ? palette.accent
                                    : palette.textPrimary,
                              ),
                            ),
                          ),
                          if (moodFilter != null)
                            TextButton.icon(
                              onPressed: () => showMoodFilterSheet(context),
                              icon: Icon(
                                Icons.filter_list,
                                color: filtering ? palette.accent : null,
                              ),
                              label: Text(
                                filtering
                                    ? l10n.queueScreenMoodsOn
                                    : l10n.queueScreenMoodsOff,
                                style: TextStyle(
                                  color: filtering
                                      ? palette.accent
                                      : palette.textPrimary,
                                ),
                              ),
                            ),
                          if (MoodRecorderScope.maybeOf(context) != null &&
                              MoodLibraryScope.maybeOf(context) != null)
                            const _RecordMoodButton(),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// "Nagraj nastrój": switches [MoodRecorder] on, into a new mood named by the date (renamed
/// later on the mood's screen), or off, with "Pokaż" opening the mood.
class _RecordMoodButton extends StatelessWidget {
  const _RecordMoodButton();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final recorder = MoodRecorderScope.maybeOf(context)!;
    final moods = MoodLibraryScope.of(context);
    final recording = recorder.recording;
    return TextButton.icon(
      onPressed: () => recording
          ? _stop(context, recorder, moods)
          : _start(context, recorder, moods),
      icon: Icon(
        recording ? Icons.fiber_manual_record : Icons.radio_button_checked,
        color: recording ? Theme.of(context).colorScheme.error : null,
      ),
      label: Text(
        recording ? l10n.queueScreenRecordingMood : l10n.queueScreenRecordMood,
        style: TextStyle(
          color: recording ? palette.accent : palette.textPrimary,
        ),
      ),
    );
  }

  static Future<void> _start(
    BuildContext context,
    MoodRecorder recorder,
    MoodLibrary moods,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final time = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    try {
      await recorder.start(
        l10n.queueScreenRecordedMoodName('${dayMonthLabel(now)}, $time'),
      );
    } catch (e) {
      debugPrint('Starting a mood recording failed: $e');
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    final mood = _recorded(recorder.moodUid, moods);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.queueScreenRecordStarted(mood?.name ?? '')),
        ),
      );
  }

  static Future<void> _stop(
    BuildContext context,
    MoodRecorder recorder,
    MoodLibrary moods,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final mood = _recorded(recorder.moodUid, moods);
    await recorder.stop();
    if (mood == null) return;
    final current = moods.current(mood) ?? mood;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            l10n.queueScreenRecordStopped(
              current.name,
              trackCountLabel(current.songIds.length + current.tracks.length),
            ),
          ),
          // With an action a SnackBar otherwise stays until closed by hand.
          persist: false,
          action: SnackBarAction(
            label: l10n.queueScreenShow,
            onPressed: () => navigator.push(
              MaterialPageRoute<void>(
                builder: (_) => MoodScreen(mood: current),
              ),
            ),
          ),
        ),
      );
  }

  static Mood? _recorded(String? uid, MoodLibrary moods) =>
      moods.userMoods.where((m) => m.uid == uid).firstOrNull;
}

/// A heading over the songs to come and the run of them it names.
typedef _Group = ({String text, bool clear, List<QueueEntry> songs});

class _Heading extends StatelessWidget {
  const _Heading(
    this.text, {
    this.action,
    this.onTap,
    this.folded = false,
    this.count = 0,
  });

  final String text;
  final Widget? action;

  /// Folds the group's songs away or shows them again; `null` for a heading of no group.
  final VoidCallback? onTap;
  final bool folded;

  /// How many songs the folded group holds, shown under its name.
  final int count;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    final title = ScrollingText(
      text,
      style: const TextStyle(
        fontSize: AppFontSize.emphasis,
        fontWeight: FontWeight.bold,
      ),
    );
    final row = Padding(
      padding: EdgeInsets.fromLTRB(onTap == null ? 16 : 8, 20, 8, 4),
      child: Row(
        children: [
          if (onTap != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                folded ? Icons.chevron_right : Icons.expand_more,
                semanticLabel: folded
                    ? l10n.queueScreenExpandGroup
                    : l10n.queueScreenCollapseGroup,
              ),
            ),
          Expanded(
            child: folded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      Text(
                        trackCountLabel(count),
                        style: TextStyle(color: context.palette.textSecondary),
                      ),
                    ],
                  )
                : title,
          ),
          ?action,
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(text, style: TextStyle(color: context.palette.textSecondary)),
  );
}

class _PreviousRow extends StatelessWidget {
  const _PreviousRow({super.key, required this.entry});

  final QueueEntry entry;

  @override
  Widget build(BuildContext context) {
    final queue = PlaybackQueueScope.of(context);
    return Opacity(
      opacity: 0.6,
      child: _QueueRow(
        hit: entry.hit,
        onTap: () => runQueueAction(
          context,
          (onStatus) => queue.jumpBack(entry, onStatus: onStatus),
        ),
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({super.key, required this.entry, required this.index});

  final QueueEntry entry;

  /// Where the row is in the list, for dragging it by the handle.
  final int index;

  @override
  Widget build(BuildContext context) {
    final queue = PlaybackQueueScope.of(context);
    final next = SourceSettingsScope.maybeOf(context)?.swipePlaysNext ?? true;
    final row = _QueueRow(
      hit: entry.hit,
      selectionKey: entry.key,
      onTap: () => runQueueAction(
        context,
        (onStatus) => queue.jumpTo(entry, onStatus: onStatus),
      ),
      trailing: ReorderableDragStartListener(
        index: index,
        // No tooltip: its long press took the drag over when the finger rested first.
        child: Semantics(
          label: l10n.queueScreenDragToReorder,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Icon(Icons.drag_handle),
          ),
        ),
      ),
    );
    // As in other lists: no dragging sideways while songs are ticked.
    if (SongSelectionScope.maybeOf(context)?.active ?? false) return row;
    return SwipeActions(
      right: SwipeAction(
        icon: next ? Icons.playlist_play : Icons.queue_music,
        label: next ? l10n.queueScreenPlayNext : l10n.queueScreenMoveToEnd,
        onTriggered: () => queue.move(entry, next ? 0 : queue.upcoming.length),
      ),
      left: removeSwipe(
        context,
        l10n.queueScreenRemoveFromQueue,
        () => QueueScreen._remove(context, queue, [entry]),
      ),
      child: row,
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.hit,
    this.isCurrent = false,
    this.selectionKey,
    this.onTap,
    this.trailing,
  });

  final SearchHit hit;
  final bool isCurrent;

  /// A song to come, ticked with a long press; the others open the song's menu.
  final Object? selectionKey;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    // The queue holds songs as they were when it was filled; caching ahead finds videos later.
    final hit = withPhoneYouTube(this.hit, YouTubeLibraryScope.of(context));
    final key = selectionKey;
    final selection = key == null ? null : SongSelectionScope.maybeOf(context);
    final selecting = selection?.active ?? false;
    final ticked = selecting && selection!.contains(key!);
    final palette = context.palette;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      selected: ticked,
      selectedTileColor: palette.accent.withValues(alpha: 0.15),
      selectedColor: palette.textPrimary,
      leading: SelectableCover(
        cover: SongCover(cover: CoverRequest.of(hit), size: SongTile.coverSize),
        selecting: selecting,
        ticked: ticked,
      ),
      title: CurrentTitle(text: hit.shownTitle(context), isCurrent: isCurrent),
      subtitle: ScrollingText(hit.shownArtist(context)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SourceIcons(hit: hit),
          trailing ?? const SizedBox(width: 12),
        ],
      ),
      onTap: selection != null && selecting
          ? () => selection.toggle(key!, hit)
          : onTap,
      onLongPress: selection != null
          ? () => selecting
                ? selection.toggle(key!, hit)
                : startSelection(selection, key!, hit)
          : () => showSongMenu(
              context,
              hit,
              idPrefix: 'Kolejka › Utwór › Menu (⋮)',
            ),
    );
  }
}
