import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/mood_filter.dart';
import '../data/moods.dart';
import '../data/playlist_library.dart';
import '../data/source_settings.dart';
import '../data/youtube_library.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
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
      builder: (_) => const TextInputDialog(
        title: 'Zapisz kolejkę jako playlistę',
        hint: 'Nazwa playlisty',
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
            'Zapisano w Bibliotece: „${playlist.name}” '
            '(${trackCountLabel(songs.length)})',
          ),
          // With an action a SnackBar otherwise stays until closed by hand.
          persist: false,
          action: SnackBarAction(
            label: 'Pokaż',
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
          title: const Text('Kolejka'),
          actions: [
            if (queue.replaced case final replaced?)
              IconButton(
                tooltip:
                    'Przywróć poprzednią kolejkę: '
                    '${[?replaced.name, trackCountLabel(replaced.songCount)].join(', ')}',
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
                  tooltip: 'Zapisz kolejkę jako playlistę',
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
                tooltip: 'Nastrój dla wszystkich utworów w kolejce',
                icon: const Icon(moodIcon),
                // The songs listed: the ones the mood filter hides stay out.
                onPressed: () => showMoodPickerForAll(context, [
                  for (final entry in previous.reversed) entry.hit,
                  current,
                  for (final entry in upcoming) entry.hit,
                ], title: 'Kolejka: wszystkie widoczne utwory'),
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
                if (queue.hasPrevious) const _Heading('Poprzednie'),
              ],
            ),
            SliverToBoxAdapter(
              key: _nowPlayingKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Heading('Teraz odtwarzane'),
                  if (current != null)
                    _QueueRow(hit: current, isCurrent: true)
                  else
                    const _Empty('Nic nie jest odtwarzane'),
                  if (upcoming.isEmpty && filtering)
                    const _Empty(
                      'Po tym utworze nic więcej nie zagra: filtr nastrojów '
                      'pomija resztę kolejki.',
                    )
                  else if (upcoming.isEmpty)
                    const _Empty(
                      'Po tym utworze nic więcej nie zagra. Dodaj coś przez '
                      '„Dodaj do kolejki” w menu utworu albo przeciągając utwór '
                      'w prawo.',
                    ),
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
                          'Usunięto z kolejki: ${removed.length} utw.',
                        ),
                        persist: false,
                        action: SnackBarAction(
                          label: 'Cofnij',
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
                          tooltip: 'Losowo w tej grupie',
                          icon: const Icon(Icons.shuffle, size: 20),
                          onPressed: () => queue.shuffleGroup(group),
                        ),
                        IconButton(
                          tooltip: 'Powtórz tę grupę',
                          icon: const Icon(Icons.repeat, size: 20),
                          onPressed: () => queue.repeatGroup(group),
                        ),
                        IconButton(
                          tooltip: 'Usuń tę grupę z kolejki',
                          icon: const Icon(Icons.playlist_remove, size: 22),
                          onPressed: removeGroup,
                        ),
                      ],
                      if (heading.clear)
                        TextButton(
                          onPressed: queue.clearAdded,
                          child: const Text('Wyczyść kolejkę'),
                        ),
                    ],
                  ),
                );
                final key = ValueKey('heading ${heading.at}');
                if (!playlistGroup) return KeyedSubtree(key: key, child: tile);
                // Dragged left, the whole group goes, like a single row.
                return Dismissible(
                  key: key,
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Theme.of(context).colorScheme.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(
                      Icons.playlist_remove,
                      color: Theme.of(context).colorScheme.onError,
                    ),
                  ),
                  onDismissed: (_) => removeGroup(),
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
                    queue.shuffle ? 'Losowo: wł.' : 'Losowo: wył.',
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
                      filtering ? 'Nastroje: wł.' : 'Nastroje: wył.',
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
    final next = SourceSettingsScope.maybeOf(context)?.swipePlaysNext ?? true;
    return SwipeActions(
      right: SwipeAction(
        icon: next ? Icons.playlist_play : Icons.queue_music,
        label: next ? 'Odtwórz jako następny' : 'Przenieś na koniec kolejki',
        onTriggered: () => queue.move(entry, next ? 0 : queue.upcoming.length),
      ),
      left: removeSwipe(
        context,
        'Usuń z kolejki',
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
      title: CurrentTitle(text: hit.shownTitle(context), isCurrent: isCurrent),
      subtitle: Text(
        hit.shownArtist(context),
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
      onLongPress: () =>
          showSongMenu(context, hit, idPrefix: 'Kolejka › Utwór › Menu (⋮)'),
    );
  }
}
