import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/combined_search.dart';
import '../data/moods.dart';
import '../data/playlist_library.dart';
import '../theme.dart';
import 'common.dart';
import 'mood_sheet.dart';
import 'playlist_picker.dart';
import 'song_tile.dart';

/// Songs ticked in a list after a long press on one of them, for doing the same to all of them.
/// Keys tell rows apart ([SongSelection.keyOf], or a row's position where one song may be listed
/// twice, as in a playlist).
class SongSelection extends ChangeNotifier {
  final _selected = <Object, SearchHit>{};

  /// Ticking songs: rows tick on tap instead of playing.
  bool get active => _selected.isNotEmpty;
  int get count => _selected.length;

  /// In the order they were ticked.
  List<SearchHit> get hits => [..._selected.values];

  bool contains(Object key) => _selected.containsKey(key);

  void toggle(Object key, SearchHit hit) {
    if (_selected.remove(key) == null) _selected[key] = hit;
    notifyListeners();
  }

  void selectAll(Map<Object, SearchHit> all) {
    _selected.addAll(all);
    notifyListeners();
  }

  void clear() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// The same song gets the same key in any list.
  static Object keyOf(SearchHit hit) =>
      hit.mainSong?.id ??
      hit.youtubeVideoId ??
      (hit.onPhone ? hit.phoneFiles.first.filePath : null) ??
      '${hit.title}\u0000${hit.artistLabel}';
}

class SongSelectionScope extends InheritedNotifier<SongSelection> {
  const SongSelectionScope({
    super.key,
    required SongSelection super.notifier,
    required super.child,
  });

  /// `null` outside a [SongSelectionArea]: a long press opens the song's menu there.
  static SongSelection? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SongSelectionScope>()
      ?.notifier;
}

/// Lets the [SongTile]s in [child] be ticked: a long press on one starts it, and while any is
/// ticked a bar under the list offers what can be done to all of them (queue, playlist, mood).
/// Back unticks them all before leaving the screen.
class SongSelectionArea extends StatefulWidget {
  const SongSelectionArea({super.key, required this.child, this.all});

  final Widget child;

  /// Every row of the list, keyed like its [SongTile]s, for "Zaznacz wszystkie".
  final Map<Object, SearchHit> Function()? all;

  @override
  State<SongSelectionArea> createState() => _SongSelectionAreaState();
}

class _SongSelectionAreaState extends State<SongSelectionArea> {
  final _selection = SongSelection();

  /// Back (the system one too, which `AppShell` turns into a plain `pop`) unticks first.
  LocalHistoryEntry? _backEntry;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onChanged);
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_selection.active && _backEntry == null) {
      final entry = _backEntry = LocalHistoryEntry(
        onRemove: () {
          _backEntry = null;
          _selection.clear();
        },
      );
      ModalRoute.of(context)?.addLocalHistoryEntry(entry);
    } else if (!_selection.active && _backEntry != null) {
      final entry = _backEntry!;
      _backEntry = null;
      entry.remove();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SongSelectionScope(
      notifier: _selection,
      child: Column(
        children: [
          Expanded(child: widget.child),
          ListenableBuilder(
            listenable: _selection,
            builder: (context, _) => _selection.active
                ? _SelectionBar(
                    selection: _selection,
                    all: widget.all,
                    actionContext: this.context,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selection,
    required this.all,
    required this.actionContext,
  });

  final SongSelection selection;
  final Map<Object, SearchHit> Function()? all;

  /// Outlives the bar, which goes as soon as the songs are unticked.
  final BuildContext actionContext;

  /// Runs [action] on the ticked songs and unticks them.
  VoidCallback _forAll(Future<void> Function(List<SearchHit> hits) action) =>
      () {
        final hits = selection.hits;
        selection.clear();
        action(hits);
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final all = this.all?.call();
    final allTicked =
        all != null && all.keys.every((key) => selection.contains(key));
    final count = selection.count;
    Widget action(IconData icon, String label, VoidCallback onPressed) =>
        Expanded(
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Icon(icon, color: palette.textPrimary),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.navLabel,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    return Material(
      color: palette.surfaceHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Anuluj zaznaczanie',
                  icon: const Icon(Icons.close),
                  onPressed: selection.clear,
                ),
                Expanded(
                  child: Text(
                    'Zaznaczono: $count',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (all != null && all.isNotEmpty)
                  TextButton(
                    onPressed: allTicked
                        ? selection.clear
                        : () => selection.selectAll(all),
                    child: Text(allTicked ? 'Odznacz' : 'Wszystkie'),
                  ),
              ],
            ),
            Row(
              children: [
                action(
                  Icons.queue_music,
                  'Do kolejki',
                  _forAll(
                    (hits) => queueSongs(actionContext, hits, next: false),
                  ),
                ),
                action(
                  Icons.playlist_play,
                  'Jako następne',
                  _forAll(
                    (hits) => queueSongs(actionContext, hits, next: true),
                  ),
                ),
                if (PlaylistLibraryScope.maybeOf(context) != null)
                  action(
                    Icons.playlist_add,
                    'Do playlisty',
                    _forAll(
                      (hits) => showAddToPlaylistSheet(actionContext, hits),
                    ),
                  ),
                if (MoodLibraryScope.maybeOf(context) != null)
                  action(
                    moodIcon,
                    'Do nastroju',
                    _forAll(
                      (hits) => showMoodPickerForAll(
                        actionContext,
                        hits,
                        title: '${hits.length} ${songsWord(hits.length)}',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Starts ticking with [hit] (a long press), with the usual long-press buzz.
void startSelection(SongSelection selection, Object key, SearchHit hit) {
  HapticFeedback.selectionClick();
  selection.toggle(key, hit);
}
