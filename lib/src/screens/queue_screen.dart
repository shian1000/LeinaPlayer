import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/youtube_library.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/song_tile.dart';
import '../data/album_covers.dart';
import '../widgets/queue_toast.dart';
import '../widgets/song_cover.dart';
import '../widgets/swipe_actions.dart';

/// "Kolejka", opened from the full player: the song playing, then everything after it, under
/// a heading for each run of songs queued from the same place — songs added one by one, a
/// playlist added as a whole, the playlist / results the queue was filled with. Tapping a song
/// plays it (skipping the ones before it); the handle moves it; dragging a row left takes it out,
/// right makes it play next.
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  static Future<void> open(BuildContext context) {
    QueueToastScope.maybeOf(context)?.hide();
    return Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => const QueueScreen()));
  }

  /// The heading over a run of songs queued from [origin].
  static String heading(PlaybackQueue queue, QueueOrigin? origin) {
    if (origin == null) return 'Następne w kolejce';
    final name = origin.playlistName;
    if (identical(origin, queue.mainOrigin)) {
      final query = origin.searchQuery;
      return name != null
          ? 'Następne z: $name'
          : query != null
          ? 'Następne z: „$query” w wyszukiwarce'
          : 'Następne';
    }
    return name != null ? 'Z playlisty: $name' : 'Następne w kolejce';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final queue = PlaybackQueueScope.of(context);
    final current = queue.current;
    final upcoming = queue.upcoming;

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
          title: const Text('Kolejka'),
        ),
        body: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.only(bottom: 24),
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Heading('Teraz odtwarzane'),
              if (current != null)
                _QueueRow(hit: current, isCurrent: true)
              else
                const _Empty('Nic nie jest odtwarzane'),
              if (upcoming.isEmpty)
                const _Empty(
                  'Po tym utworze nic więcej nie zagra. Dodaj coś przez '
                  '„Dodaj do kolejki” w menu utworu albo przeciągając utwór '
                  'w prawo.',
                ),
            ],
          ),
          itemCount: items.length,
          onReorderItem: reorder,
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
            return _Heading(
              key: ValueKey('heading ${heading.at}'),
              heading.text,
              action: heading.clear
                  ? TextButton(
                      onPressed: queue.clearAdded,
                      child: const Text('Wyczyść kolejkę'),
                    )
                  : null,
            );
          },
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
                    queue.shuffle ? 'Losowo: wł.' : 'Losowo: wył.',
                    style: TextStyle(
                      color: queue.shuffle
                          ? palette.accent
                          : palette.textPrimary,
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
  const _Heading(this.text, {super.key, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
          content: Text('Usunięto z kolejki: „${entry.hit.title}”'),
          // With an action a SnackBar otherwise stays until closed by hand.
          persist: false,
          action: SnackBarAction(
            label: 'Cofnij',
            onPressed: () => queue.reinsert(entry, at),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final queue = PlaybackQueueScope.of(context);
    return SwipeActions(
      right: SwipeAction(
        icon: Icons.playlist_play,
        label: 'Odtwórz jako następny',
        onTriggered: () => queue.move(entry, 0),
      ),
      left: SwipeAction(
        icon: Icons.delete_outline,
        label: 'Usuń z kolejki',
        color: Theme.of(context).colorScheme.error,
        foreground: Theme.of(context).colorScheme.onError,
        onTriggered: () => _remove(context, queue),
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
            label: 'Przeciągnij, aby zmienić kolejność',
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
      title: CurrentTitle(text: hit.title, isCurrent: isCurrent),
      subtitle: Text(
        hit.artistLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SourceIcons(hit: hit),
          trailing ?? const SizedBox(width: 12),
        ],
      ),
      onTap: onTap,
    );
  }
}
