import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/combined_search.dart';
import '../data/moods.dart';
import '../data/playlist_library.dart';
import '../theme.dart';
import 'mood_sheet.dart';
import 'playlist_picker.dart';
import 'scrolling_text.dart';
import 'song_tile.dart';
import '../l10n.dart';

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

  /// The ticked rows by their keys, in the order they were ticked.
  Map<Object, SearchHit> get ticked => Map.of(_selected);

  bool contains(Object key) => _selected.containsKey(key);

  void toggle(Object key, SearchHit hit) {
    if (_selected.remove(key) == null) _selected[key] = hit;
    notifyListeners();
  }

  void selectAll(Map<Object, SearchHit> all) {
    _selected.addAll(all);
    notifyListeners();
  }

  /// Unticks the rows whose keys fail [test] (they left the list).
  void retainWhere(bool Function(Object key) test) {
    final before = _selected.length;
    _selected.removeWhere((key, _) => !test(key));
    if (_selected.length != before) notifyListeners();
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

/// A button of the bar under a [SongSelectionArea].
class SongSelectionAction {
  const SongSelectionAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onlyOne = false,
  });

  final IconData icon;
  final String label;

  /// Gets the ticked rows (keyed as the list keys them, in the order they were ticked) and a
  /// context that outlives the bar, which goes as soon as the songs are unticked.
  final void Function(BuildContext context, Map<Object, SearchHit> ticked)
  onPressed;

  /// Works on one song: greyed out while more are ticked.
  final bool onlyOne;

  /// What any song list offers: queue, play next, playlist, mood.
  static List<SongSelectionAction> defaults(BuildContext context) => [
    SongSelectionAction(
      icon: Icons.queue_music,
      label: l10n.songSelectionToQueue,
      onPressed: (context, ticked) =>
          queueSongs(context, [...ticked.values], next: false),
    ),
    SongSelectionAction(
      icon: Icons.playlist_play,
      label: l10n.songSelectionPlayNext,
      onPressed: (context, ticked) =>
          queueSongs(context, [...ticked.values], next: true),
    ),
    ?toPlaylist(context),
    ?toMood(context),
  ];

  /// "Do playlisty"; `null` without Biblioteka's playlists.
  static SongSelectionAction? toPlaylist(BuildContext context) =>
      PlaylistLibraryScope.maybeOf(context) == null
      ? null
      : SongSelectionAction(
          icon: Icons.playlist_add,
          label: l10n.songSelectionToPlaylist,
          onPressed: (context, ticked) =>
              showAddToPlaylistSheet(context, [...ticked.values]),
        );

  /// "Do nastroju"; `null` without moods.
  static SongSelectionAction? toMood(BuildContext context) =>
      MoodLibraryScope.maybeOf(context) == null
      ? null
      : SongSelectionAction(
          icon: moodIcon,
          label: l10n.songSelectionToMood,
          onPressed: (context, ticked) => showMoodPickerForAll(context, [
            ...ticked.values,
          ], title: l10n.songsCount(ticked.length)),
        );
}

/// Lets the [SongTile]s in [child] be ticked: a long press on one starts it, and while any is
/// ticked a bar under the list offers what can be done to all of them ([actions]; queue,
/// playlist, mood by default). Back unticks them all before leaving the screen.
class SongSelectionArea extends StatefulWidget {
  const SongSelectionArea({
    super.key,
    required this.child,
    this.all,
    this.actions,
    this.untickGone = false,
  });

  final Widget child;

  /// Every row of the list, keyed like its [SongTile]s, for "Zaznacz wszystkie".
  final Map<Object, SearchHit> Function()? all;

  /// Rows that leave [all] are unticked when the list is built again (Kolejka: a ticked song
  /// that started playing). Not for search, where ticked songs outlive a new query.
  final bool untickGone;

  /// The bar's buttons instead of [SongSelectionAction.defaults].
  final List<SongSelectionAction> Function(BuildContext context)? actions;

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
  void didUpdateWidget(SongSelectionArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    final all = widget.all;
    if (!widget.untickGone || all == null || !_selection.active) return;
    // Not while building: unticking the last one also takes Back's entry off the route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final keys = all().keys.toSet();
      _selection.retainWhere(keys.contains);
    });
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
                    actions: (widget.actions ?? SongSelectionAction.defaults)(
                      context,
                    ),
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
    required this.actions,
    required this.actionContext,
  });

  final SongSelection selection;
  final Map<Object, SearchHit> Function()? all;
  final List<SongSelectionAction> actions;

  /// Outlives the bar, which goes as soon as the songs are unticked.
  final BuildContext actionContext;

  /// Runs [action] on the ticked songs and unticks them.
  VoidCallback? _run(SongSelectionAction action) =>
      action.onlyOne && selection.count != 1
      ? null
      : () {
          final ticked = selection.ticked;
          selection.clear();
          action.onPressed(actionContext, ticked);
        };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final all = this.all?.call();
    final allTicked =
        all != null && all.keys.every((key) => selection.contains(key));
    final count = selection.count;
    Widget button(SongSelectionAction action) {
      final onPressed = _run(action);
      return Expanded(
        child: Opacity(
          opacity: onPressed == null ? 0.38 : 1,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Icon(action.icon, color: palette.textPrimary),
                  const SizedBox(height: 4),
                  ScrollingText(
                    action.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppFontSize.navLabel,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: palette.surfaceHigh,
      // Under a screen of its own (Kolejka) the bar is the bottom of the window.
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: l10n.songSelectionCancelSelection,
                    icon: const Icon(Icons.close),
                    onPressed: selection.clear,
                  ),
                  Expanded(
                    child: Text(
                      l10n.songSelectionSelected(count),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (all != null && all.isNotEmpty)
                    TextButton(
                      onPressed: allTicked
                          ? selection.clear
                          : () => selection.selectAll(all),
                      child: Text(
                        allTicked
                            ? l10n.songSelectionUntick
                            : l10n.songSelectionTickAll,
                      ),
                    ),
                ],
              ),
              Row(children: [for (final action in actions) button(action)]),
            ],
          ),
        ),
      ),
    );
  }
}

/// A song row's cover, ticked or not while songs are being ticked.
class SelectableCover extends StatelessWidget {
  const SelectableCover({
    super.key,
    required this.cover,
    required this.selecting,
    required this.ticked,
  });

  final Widget cover;
  final bool selecting;
  final bool ticked;

  @override
  Widget build(BuildContext context) {
    if (!selecting) return cover;
    final palette = context.palette;
    return Stack(
      children: [
        cover,
        Positioned.fill(
          child: ColoredBox(
            color: ticked
                ? palette.background.withValues(alpha: 0.55)
                : Colors.transparent,
            child: ticked
                ? Icon(Icons.check_circle, color: palette.accent)
                : null,
          ),
        ),
      ],
    );
  }
}

/// Starts ticking with [hit] (a long press), with the usual long-press buzz.
void startSelection(SongSelection selection, Object key, SearchHit hit) {
  HapticFeedback.selectionClick();
  selection.toggle(key, hit);
}
