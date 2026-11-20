import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/mood_filter.dart';
import '../data/moods.dart';
import '../data/playlist_library.dart';
import '../data/source_settings.dart';
import '../data/youtube_library.dart';
import '../l10n.dart';
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
import 'playlist_screen.dart';
import '../widgets/song_names.dart';

/// "Kolejka", opened from the full player: the last few songs before the current one (above,
/// scrolled to; tapping one goes back to it), the song playing, then everything after it, under
/// a heading for each run of songs queued from the same place — songs added one by one, a
/// playlist added as a whole, the playlist / results the queue was filled with. Tapping a song
/// plays it (skipping the ones before it); the handle moves it; dragging a row left takes it out,
/// right makes it play next or moves it to the end ([SourceSettings.swipePlaysNext]). The queue
/// that playing something else replaced comes back with "Przywróć poprzednią kolejkę".
class QueueScreen extends StatelessWidget {
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
      return name != null
          ? l10n.queueScreenNextFrom(name)
          : query != null
          ? l10n.queueScreenNextFromSearch(query)
          : l10n.queueScreenNext;
    }
    return name != null
        ? l10n.queueScreenFromPlaylist(name)
        : l10n.queueScreenNextInQueue;
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final queue = PlaybackQueueScope.of(context);
    final current = queue.current;
    final upcoming = queue.upcoming;
    final previous = queue.history.reversed.take(previousShown).toList();
    final moodFilter = MoodFilterScope.maybeOf(context);
    final filtering = moodFilter?.active ?? false;

    // Headings (strings) and songs, as the list shows them.
    final items = <Object>[];
    var clearShown = false;
    for (final (i, entry) in upcoming.indexed) {
      if (i == 0 || !identical(upcoming[i - 1].origin, entry.origin)) {
        items.add((
          text: heading(queue, entry.origin),
          clear: !clearShown && !queue.isMain(entry),
          at: i,
        ));
        if (!queue.isMain(entry)) clearShown = true;
      }
      items.add(entry);
    }

    void reorder(int from, int to) {
      final entry = items[from];
      if (entry is! QueueEntry) return;
      final rest = [...items]..removeAt(from);
      queue.move(entry, rest.take(to).whereType<QueueEntry>().length);
    }

    // Its own messenger: "Usunięto z kolejki" goes when the screen closes, instead of covering
    // the full player's buttons.
    return ScaffoldMessenger(
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
                  onPressed: () => _saveAsPlaylist(context, [
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
          center: _nowPlayingKey,
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
              key: _nowPlayingKey,
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
              proxyDecorator: _liftedRow,
              itemBuilder: (context, i) {
                final item = items[i];
                if (item is QueueEntry) {
                  return _UpcomingRow(
                    key: ValueKey(item.key),
                    entry: item,
                    index: i,
                  );
                }
                final heading = item as ({String text, bool clear, int at});
                final origin = upcoming[heading.at].origin;
                final group = upcoming
                    .skip(heading.at)
                    .takeWhile((entry) => identical(entry.origin, origin))
                    .toList();
                final playlistGroup = origin?.playlistName != null;
                void removeGroup() {
                  final removed = [
                    for (final entry in group) (entry, queue.remove(entry)),
                  ];
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          l10n.queueScreenRemovedCount(removed.length),
                        ),
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

                final tile = _Heading(
                  heading.text,
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
                          onPressed: removeGroup,
                        ),
                      ],
                      if (heading.clear)
                        TextButton(
                          onPressed: queue.clearAdded,
                          child: Text(l10n.queueScreenClear),
                        ),
                    ],
                  ),
                );
                return KeyedSubtree(
                  key: ValueKey('heading ${heading.at}'),
                  child: tile,
                );
              },
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                        color: filtering ? palette.accent : palette.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
    child: Row(
      children: [
        Expanded(
          child: ScrollingText(
            text,
            style: const TextStyle(
              fontSize: AppFontSize.emphasis,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ?action,
      ],
    ),
  );
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

  void _remove(BuildContext context, PlaybackQueue queue) {
    final at = queue.remove(entry);
    if (at < 0) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.queueScreenRemoved(entry.hit.title)),
          // With an action a SnackBar otherwise stays until closed by hand.
          persist: false,
          action: SnackBarAction(
            label: l10n.commonUndo,
            onPressed: () => queue.reinsert(entry, at),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final queue = PlaybackQueueScope.of(context);
    final next = SourceSettingsScope.maybeOf(context)?.swipePlaysNext ?? true;
    return SwipeActions(
      right: SwipeAction(
        icon: next ? Icons.playlist_play : Icons.queue_music,
        label: next ? l10n.queueScreenPlayNext : l10n.queueScreenMoveToEnd,
        onTriggered: () => queue.move(entry, next ? 0 : queue.upcoming.length),
      ),
      left: removeSwipe(
        context,
        l10n.queueScreenRemoveFromQueue,
        () => _remove(context, queue),
      ),
      child: _QueueRow(
        hit: entry.hit,
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
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.hit,
    this.isCurrent = false,
    this.onTap,
    this.trailing,
  });

  final SearchHit hit;
  final bool isCurrent;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    // The queue holds songs as they were when it was filled; caching ahead finds videos later.
    final hit = withPhoneYouTube(this.hit, YouTubeLibraryScope.of(context));
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: SongCover(cover: CoverRequest.of(hit), size: SongTile.coverSize),
      title: CurrentTitle(text: hit.shownTitle(context), isCurrent: isCurrent),
      subtitle: ScrollingText(hit.shownArtist(context)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SourceIcons(hit: hit),
          trailing ?? const SizedBox(width: 12),
        ],
      ),
      onTap: onTap,
      onLongPress: () =>
          showSongMenu(context, hit, idPrefix: 'Kolejka › Utwór › Menu (⋮)'),
    );
  }
}
