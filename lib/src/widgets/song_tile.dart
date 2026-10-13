import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/mood_filter.dart';
import '../data/song_catalog.dart';
import '../playback/playback_queue.dart';
import '../playback/player_controller.dart';
import '../playback/track_player.dart';
import '../theme.dart';
import 'menu_sheet.dart';
import 'mood_sheet.dart';
import 'playing_bars.dart';
import 'queue_toast.dart';
import '../screens/queue_screen.dart';
import 'share_sheet.dart';
import '../data/album_covers.dart';
import 'song_cover.dart';
import 'swipe_actions.dart';

/// Result title; the song in the player is highlighted like in the reference app.
class CurrentTitle extends StatelessWidget {
  const CurrentTitle({super.key, required this.text, required this.isCurrent});

  final String text;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        if (isCurrent) ...[
          PlayingBars(
            playing: PlayerScope.of(context).playing,
            color: palette.accent,
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: isCurrent ? TextStyle(color: palette.accent) : null,
          ),
        ),
      ],
    );
  }
}

/// "3:05", or "1:02:03" for an hour or more.
String formatDuration(Duration d) {
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$seconds'
      : '${d.inMinutes}:$seconds';
}

/// Runs a queue action started by a tap ([PlaybackQueue.start], next, previous) and tells the
/// user how it went: progress while YouTube is contacted, then what was found or why it failed.
Future<void> runQueueAction(
  BuildContext context,
  Future<PlayOutcome?> Function(void Function(String status) onStatus) action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  // Clearing the queue too: a fast answer would otherwise wait behind "Szukam…".
  void say(String text, {Duration duration = const Duration(seconds: 4)}) =>
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(text), duration: duration));

  var announced = false;
  final outcome = await action((status) {
    announced = true;
    say(status, duration: const Duration(seconds: 30));
  });
  final message = outcome?.message;
  if (message != null) {
    say(message);
  } else if (announced) {
    messenger.clearSnackBars();
  }
}

/// "Dodaj do kolejki" from a song's ⋮ menu: plays after the current song and the ones added
/// before it (right away when nothing plays).
Future<void> addToQueue(BuildContext context, SearchHit hit) =>
    queueSongs(context, [hit], next: false);

/// "Odtwórz jako następny" from a song's ⋮ menu: plays right after the current song.
Future<void> playNextInQueue(BuildContext context, SearchHit hit) =>
    queueSongs(context, [hit], next: true);

/// Adds [hits] to the queue — right after the current song ([next]) or after the songs added
/// before them — saying so; [origin] is the playlist they're added from as a whole.
Future<void> queueSongs(
  BuildContext context,
  List<SearchHit> hits, {
  required bool next,
  QueueOrigin? origin,
}) async {
  if (hits.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final queue = PlaybackQueueScope.of(context);
  final toast = QueueToastScope.maybeOf(context);
  final filter = MoodFilterScope.maybeOf(context);
  // With nothing playing the first song starts right away, filter or not.
  final waiting = queue.current == null ? hits.skip(1) : hits;
  final outside = filter == null
      ? 0
      : waiting.where((hit) => !filter.allows(hit)).length;
  String? filterNote;
  if (outside > 0) {
    final turnOff = filter!.offWhenAdded;
    if (turnOff) await filter.reset();
    filterNote = hits.length == 1
        ? 'Utwór dodany do kolejki jest poza filtrami nastroju: '
              '${turnOff ? 'wyłączam filtr' : 'będzie pominięty'}'
        : outside == waiting.length
        ? 'Utwory dodane do kolejki są poza filtrami nastroju: '
              '${turnOff ? 'wyłączam filtr' : 'będą pominięte'}'
        : 'Część utworów dodanych do kolejki jest poza filtrami nastroju: '
              '${turnOff ? 'wyłączam filtr' : 'będą pominięte'}';
  }
  if (!context.mounted) return;
  await runQueueAction(context, (onStatus) async {
    final outcome = next
        ? await queue.playNext(hits, origin: origin, onStatus: onStatus)
        : await queue.add(hits, origin: origin, onStatus: onStatus);
    if (outcome == null || filterNote != null) {
      // Short like the reference app's; the sheet or row just touched says what it was.
      final text =
          filterNote ??
          (!next
              ? 'Dodano do kolejki'
              : origin == null
              ? 'Zagra jako następny'
              : 'Zagra jako następna');
      if (toast != null && context.mounted) {
        messenger.clearSnackBars();
        toast.show(
          text,
          shownFor: filterNote == null ? null : const Duration(seconds: 5),
          actionLabel: 'Otwórz',
          onAction: () {
            if (context.mounted) QueueScreen.open(context);
          },
        );
      } else {
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              duration: Duration(seconds: filterNote == null ? 2 : 4),
              content: Text(text),
            ),
          );
      }
    }
    return outcome;
  });
}

/// A song row — search results, playlists: cover, title (highlighted while it plays), details,
/// the source icons, and tapping plays it from the user's preferred source.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.hit,
    this.queue,
    this.queueIndex = 0,
    this.searchQuery,
    this.playlistId,
    this.youTubeListId,
    this.playlistName,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.menuIdPrefix = 'Utwór › Menu (⋮)',
  });

  final SearchHit hit;

  /// What the play queue becomes when this song is tapped (e.g. its whole playlist), with this
  /// song at [queueIndex]; `null` queues just this song.
  final List<SearchHit>? queue;
  final int queueIndex;

  /// Where the song is played from, shown in the full player: a search, or a playlist.
  final String? searchQuery;
  final String? playlistName;

  /// The playlist (`playlists.id`) the song is played from, for the history.
  final int? playlistId;

  /// The YouTube playlist the song is played from ([PlaylistSummary.youTubeId]).
  final String? youTubeListId;

  /// Replaces the default "artist • album • year".
  final String? subtitle;

  /// Shown after the source icons (e.g. a ⋮ menu).
  final Widget? trailing;

  /// Instead of playing the song (e.g. "Ostatnie" opens the playlist it was played from).
  final VoidCallback? onTap;

  /// Instead of the song's usual menu ([showSongMenu]), e.g. a playlist's own track menu.
  final VoidCallback? onLongPress;

  /// What the menu's dummy entries report, as `<menuIdPrefix> › <label>`.
  final String menuIdPrefix;

  static const coverSize = 48.0;

  void _onTap(BuildContext context) {
    FocusScope.of(context).unfocus();
    final queue = PlaybackQueueScope.of(context);
    runQueueAction(
      context,
      (onStatus) => queue.start(
        this.queue ?? [hit],
        this.queue == null ? 0 : queueIndex,
        playlistId: playlistId,
        youTubeListId: youTubeListId,
        playlistName: playlistName,
        searchQuery: searchQuery,
        onStatus: onStatus,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = PlayerScope.of(context).current;
    final videoId = hit.youtubeVideoId;
    final isCurrent =
        current != null &&
        (hit.phoneFiles.any((f) => f.filePath == current.source) ||
            (videoId != null && current.youtubeVideoId == videoId));
    final details =
        subtitle ??
        [
          hit.artistLabel,
          if (hit.album != null && hit.album!.isNotEmpty) hit.album!,
          if (hit.year != null) '${hit.year}',
        ].join(' • ');
    final trailing = this.trailing;
    final tile = ListTile(
      contentPadding: trailing == null
          ? null
          : const EdgeInsets.only(left: 16, right: 4),
      leading: SongCover(cover: CoverRequest.of(hit), size: SongTile.coverSize),
      title: CurrentTitle(text: hit.title, isCurrent: isCurrent),
      subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing == null
          ? SourceIcons(hit: hit)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SourceIcons(hit: hit),
                trailing,
              ],
            ),
      onTap: onTap ?? () => _onTap(context),
      onLongPress:
          onLongPress ??
          () => showSongMenu(context, hit, idPrefix: menuIdPrefix),
    );
    // Like the reference app: dragging a song to the right queues it.
    return SwipeActions(
      right: SwipeAction(
        icon: Icons.queue_music,
        label: 'Dodaj do kolejki',
        onTriggered: () => addToQueue(context, hit),
      ),
      child: tile,
    );
  }
}

/// Column of three small icons next to a result, as tall as the cover and half as wide:
/// in MusicDatabase, on the phone (with "*" when not in MusicDatabase yet), and on YouTube.
/// Each icon keeps its slot even when hidden, so they line up from row to row.
class SourceIcons extends StatelessWidget {
  const SourceIcons({super.key, required this.hit});

  final SearchHit hit;

  static const _slot = SongTile.coverSize / 3;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget slot({
      required bool visible,
      required String tooltip,
      required Widget child,
    }) => SizedBox.square(
      dimension: _slot,
      child: visible
          ? Tooltip(
              message: tooltip,
              child: Center(child: child),
            )
          : null,
    );

    return SizedBox(
      width: SongTile.coverSize / 2,
      height: SongTile.coverSize,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          slot(
            visible: hit.inMainDatabase,
            tooltip: 'W bazie danych',
            child: Icon(Icons.storage, size: 14, color: palette.textSecondary),
          ),
          slot(
            visible: hit.onPhone,
            tooltip: hit.pending
                ? 'Na telefonie, spoza bazy danych'
                : 'Na telefonie',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.smartphone, size: 14, color: palette.textSecondary),
                if (hit.pending)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Text(
                      '*',
                      style: TextStyle(
                        color: palette.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Full: MusicDatabase (or the phone) has the video. Dimmed: it doesn't, but searching
          // YouTube may find it. None: marked in MusicDatabase as not on YouTube, or the phone
          // searched lately and found nothing.
          slot(
            visible:
                hit.youTube != YouTubeLink.notOnYouTube &&
                hit.youTube != YouTubeLink.notFound,
            tooltip: hit.youTube != YouTubeLink.linked
                ? 'Do wyszukania na YouTube'
                : hit.phoneMatch != null
                ? 'Na YouTube (znalezione przez telefon)'
                : 'Na YouTube',
            child: Icon(
              Icons.smart_display,
              size: 16,
              color: hit.youTube == YouTubeLink.linked
                  ? palette.textSecondary
                  : palette.textSecondary.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// The menu of a song — its ⋮, and a long press on its row anywhere: "Dodaj do kolejki",
/// "Odtwórz jako następny", "Dodaj do nastroju", "Udostępnij"; the rest are dummies like in the
/// reference app. [extra] entries (e.g. "Usuń z tej playlisty") go after the queue ones.
Future<void> showSongMenu(
  BuildContext context,
  SearchHit hit, {
  required String idPrefix,
  List<MenuSheetEntry> extra = const [],
}) {
  FocusScope.of(context).unfocus();
  return showMenuSheet(
    context,
    idPrefix: idPrefix,
    header: MenuSheetHeader(
      cover: SongCover(cover: CoverRequest.of(hit)),
      title: hit.title,
      subtitle: hit.artistLabel,
    ),
    entries: [
      MenuSheetEntry(
        Icons.queue_music,
        'Dodaj do kolejki',
        onTap: () => addToQueue(context, hit),
      ),
      MenuSheetEntry(
        Icons.playlist_play,
        'Odtwórz jako następny',
        onTap: () => playNextInQueue(context, hit),
      ),
      ?moodMenuEntry(context, hit),
      ...extra,
      const MenuSheetEntry(Icons.playlist_add, 'Dodaj do playlisty'),
      const MenuSheetEntry(Icons.album_outlined, 'Przejdź do albumu'),
      const MenuSheetEntry(Icons.person_outline, 'Przejdź do wykonawców'),
      MenuSheetEntry(
        Icons.share_outlined,
        'Udostępnij',
        onTap: () => showSongShareSheet(context, hit, idPrefix: idPrefix),
      ),
    ],
  );
}

/// A song's ⋮ button opening [showSongMenu].
class SongMenuButton extends StatelessWidget {
  const SongMenuButton({super.key, required this.hit, required this.idPrefix});

  final SearchHit hit;

  /// Dummy entries report `<idPrefix> › <label>`.
  final String idPrefix;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Menu utworu (⋮)',
    icon: const Icon(Icons.more_vert),
    onPressed: () => showSongMenu(context, hit, idPrefix: idPrefix),
  );
}
