import 'package:flutter/material.dart';

export '../data/song_catalog.dart' show artistNamesOf;

import '../data/saved_songs.dart';
import '../data/combined_search.dart';
import '../data/local_library.dart';
import '../data/hidden_songs.dart';
import '../data/mood_filter.dart';
import '../data/moods.dart';
import '../data/song_radio.dart';
import '../data/song_catalog.dart';
import '../data/source_settings.dart';
import '../data/text_normalizer.dart';
import '../data/youtube_library.dart';
import '../playback/downloads.dart';
import '../playback/playback_queue.dart';
import '../playback/player_controller.dart';
import '../playback/track_player.dart';
import '../theme.dart';
import '../screens/feature_infos.dart';
import 'feature_info.dart';
import 'menu_sheet.dart';
import 'mood_sheet.dart';
import 'playing_bars.dart';
import 'queue_toast.dart';
import '../screens/queue_screen.dart';
import '../screens/song_list_screen.dart';
import 'playlist_picker.dart';
import 'share_sheet.dart';
import 'sleep_timer_sheet.dart';
import 'song_selection.dart';
import '../data/album_covers.dart';
import 'song_cover.dart';
import 'swipe_actions.dart';
import 'song_info.dart';
import 'song_names.dart';

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

/// How a full album (music.db's `songs.kind`) is marked in song rows, the player and menus.
const fullAlbumLabel = 'Cały album';

/// [text] (a song's artist line) with [fullAlbumLabel] first when [hit] is a full album.
String withFullAlbumLabel(SearchHit? hit, String text) =>
    hit?.isFullAlbum ?? false ? '$fullAlbumLabel • $text' : text;

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
    this.moodKey,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selectionKey,
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

  /// The mood ([Mood.key]) the song is played from.
  final String? moodKey;

  /// Replaces the default "artist • album • year".
  final String? subtitle;

  /// Shown after the source icons (e.g. a ⋮ menu).
  final Widget? trailing;

  /// Instead of playing the song (e.g. "Ostatnie" opens the playlist it was played from).
  final VoidCallback? onTap;

  /// Instead of the song's usual menu ([showSongMenu]), e.g. a playlist's own track menu —
  /// only outside a [SongSelectionArea], where a long press starts ticking songs.
  final VoidCallback? onLongPress;

  /// Tells this row apart in a [SongSelection] where the same song may be listed twice (e.g.
  /// its position); [SongSelection.keyOf] otherwise.
  final Object? selectionKey;

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
        moodKey: moodKey,
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
            (videoId != null && current.youtubeVideoId == videoId) ||
            (current.serverFileId != null &&
                current.serverFileId == hit.serverFile?.id));
    final fullAlbum = hit.isFullAlbum;
    final details = [
      if (fullAlbum) fullAlbumLabel,
      subtitle ??
          [
            hit.shownArtist(context),
            // A full album is usually filed under itself: its own title again says nothing.
            if (hit.album != null &&
                hit.album!.isNotEmpty &&
                !(fullAlbum && hit.album == hit.title))
              hit.shownAlbum(context)!,
            if (hit.year != null) '${hit.year}',
          ].join(' • '),
    ].join(' • ');
    final selection = SongSelectionScope.maybeOf(context);
    final key = selectionKey ?? SongSelection.keyOf(hit);
    final selecting = selection != null && selection.active;
    final ticked = selecting && selection.contains(key);
    final trailing = selecting ? null : this.trailing;
    final palette = context.palette;
    final cover = SongCover(
      cover: CoverRequest.of(hit),
      size: SongTile.coverSize,
    );
    final hidden = HiddenSongsScope.maybeOf(context)?.contains(hit) ?? false;
    final row = ListTile(
      contentPadding: trailing == null
          ? null
          : const EdgeInsets.only(left: 16, right: 4),
      selected: ticked,
      selectedTileColor: palette.accent.withValues(alpha: 0.15),
      selectedColor: palette.textPrimary,
      leading: selecting
          ? Stack(
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
            )
          : cover,
      title: CurrentTitle(text: hit.shownTitle(context), isCurrent: isCurrent),
      subtitle: Text.rich(
        TextSpan(
          children: [
            if (fullAlbum) ...[
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.album, size: 14),
              ),
              const TextSpan(text: ' '),
            ],
            TextSpan(text: details),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing == null
          ? SourceIcons(hit: hit)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SourceIcons(hit: hit),
                trailing,
              ],
            ),
      onTap: selecting
          ? () => selection.toggle(key, hit)
          : onTap ?? () => _onTap(context),
      onLongPress: selection != null
          ? () => selecting
                ? selection.toggle(key, hit)
                : startSelection(selection, key, hit)
          : onLongPress ??
                () => showSongMenu(context, hit, idPrefix: menuIdPrefix),
    );
    // "Ukryj utwór": still there to tap, but dimmed like the reference app's hidden songs.
    final tile = hidden ? Opacity(opacity: 0.45, child: row) : row;
    if (selecting) return tile;
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

/// The one icon next to a result, as tall as the cover and half as wide: where tapping it
/// plays from first — the first source in the user's "Kolejność odtwarzania" that has the song
/// (a dimmed YouTube icon when none has it but searching YouTube may find it). A "*" marks a
/// song not in MusicDatabase (it could be sent there one day), and a small pin a song kept on the
/// phone — the user's own file, or its YouTube audio in Pamięć podręczna — so it plays offline.
class SourceIcons extends StatelessWidget {
  const SourceIcons({super.key, required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = SourceSettingsScope.maybeOf(context);
    final order = settings?.activePlaybackOrder ?? PlaybackSource.values;
    final source = order.where(hit.playableFrom).firstOrNull;
    final videoId = hit.youtubeVideoId;
    final cached =
        videoId != null &&
        (YouTubeLibraryScope.maybeOf(context)?.isCached(videoId) ?? false);
    final downloaded =
        !hit.onPhone &&
        (DownloadsScope.maybeOf(context)?.isDownloaded(hit) ?? false);
    final offline = hit.onPhone || cached || downloaded;
    final searchable =
        source == null &&
        order.contains(PlaybackSource.youtube) &&
        hit.youTube == YouTubeLink.unknown;

    final (IconData? icon, String tooltip) = switch (source) {
      PlaybackSource.phone => (Icons.smartphone, 'Na telefonie'),
      PlaybackSource.server => (Icons.dns, 'Na serwerze'),
      PlaybackSource.youtube => (
        Icons.smart_display,
        hit.phoneMatch != null
            ? 'Na YouTube (znalezione przez telefon)'
            : 'Na YouTube',
      ),
      null when searchable => (Icons.smart_display, 'Do wyszukania na YouTube'),
      null => (null, ''),
    };
    final color = source == null
        ? palette.textSecondary.withValues(alpha: 0.35)
        : palette.textSecondary;

    return SizedBox(
      width: SongTile.coverSize / 2,
      height: SongTile.coverSize,
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox.square(
              dimension: 16,
              child: icon == null
                  ? null
                  : Tooltip(
                      message: tooltip,
                      child: Icon(icon, size: 16, color: color),
                    ),
            ),
            if (!hit.inMainDatabase)
              Positioned(
                right: -6,
                top: -6,
                child: Tooltip(
                  message: 'Spoza bazy danych',
                  child: Text(
                    '*',
                    style: TextStyle(
                      color: palette.accent,
                      fontSize: AppFontSize.small,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                ),
              ),
            if (offline)
              Positioned(
                right: -5,
                bottom: -5,
                child: Tooltip(
                  message: hit.onPhone
                      ? 'Dostępne offline (plik na telefonie)'
                      : downloaded
                      ? 'Dostępne offline (pobrane)'
                      : 'Dostępne offline (pamięć podręczna)',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.background,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.offline_pin,
                      size: 10,
                      color: palette.accent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The menu of a song — its ⋮, and a long press on its row outside a [SongSelectionArea]:
/// "Dodaj do kolejki", "Odtwórz jako następny", "Dodaj do nastroju", "Dodaj do playlisty",
/// "Zapisz na później", "Przejdź do albumu" (only when the song has one), "Przejdź do
/// wykonawców", "Udostępnij", "Wyświetl informacje o utworze". [extra] entries (e.g. "Usuń z tej
/// playlisty") go after the queue ones.
/// "Przejdź do radia utworu" (music.db songs). "Pobierz utwór", "Wyłącznik czasowy" and
/// "Ukryj utwór" sit in a smaller block above.
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
      title: hit.shownTitle(context),
      subtitle: hit.shownArtist(context),
    ),
    quickEntries: [
      ?downloadEntry(context, hit),
      ?sleepTimerEntry(context),
      ?hideEntry(context, hit),
    ],
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
      ?playlistSubmenuEntry(context, [hit]),
      if (SavedSongsScope.maybeOf(context) case final saved?)
        saved.contains(hit)
            ? MenuSheetEntry(
                Icons.bookmark_remove_outlined,
                'Usuń z „Na później”',
                onTap: () => saved.toggle(hit),
              )
            : MenuSheetEntry(
                Icons.bookmark_border,
                'Zapisz na później',
                onTap: () => saved.toggle(hit),
              ),
      if (hit.album case final album? when album.isNotEmpty)
        MenuSheetEntry(
          Icons.album_outlined,
          'Przejdź do albumu',
          onTap: () => openAlbumSongs(context, album),
        ),
      MenuSheetEntry(
        Icons.person_outline,
        'Przejdź do wykonawców',
        submenu: () => [
          for (final artist in artistNamesOf(hit.artistLabel))
            MenuSheetEntry(
              Icons.person_outline,
              artist,
              onTap: () => openArtistSongs(context, artist),
            ),
        ],
      ),
      if (hit.mainSong case final song?)
        MenuSheetEntry(
          Icons.radio,
          'Przejdź do radia utworu',
          onTap: () => openSongRadio(context, song),
          onLongPress: () => showFeatureInfo(context, FeatureInfos.songRadio),
        ),
      MenuSheetEntry(
        Icons.share_outlined,
        'Udostępnij',
        onTap: () => showSongShareSheet(context, hit, idPrefix: idPrefix),
      ),
      MenuSheetEntry(
        Icons.info_outline,
        'Wyświetl informacje o utworze',
        onTap: () => showSongInfoSheet(context, hit),
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

/// A lite artist page: every song (music.db and the phone) with [artist] among its artists.
Future<void> openArtistSongs(BuildContext context, String artist) =>
    SongListScreen.open(
      context,
      title: artist,
      subtitle: 'Wykonawca',
      songs: (context) {
        final wanted = normalizeForSearch(artist);
        return [
          for (final hit in searchEverywhere(
            artist,
            SongCatalogScope.of(context),
            LocalLibraryScope.of(context),
            youTube: YouTubeLibraryScope.of(context),
            fields: const {SearchField.artist},
          ))
            if (artistNamesOf(hit.artistLabel)
                .any((name) => normalizeForSearch(name) == wanted))
              hit,
        ];
      },
    );

/// The songs of the album called [album] (a lite album page).
/// "Ukryj utwór" / "Przestań ukrywać" in a song's menu; `null` without [HiddenSongs].
MenuSheetEntry? hideEntry(BuildContext context, SearchHit hit) {
  final hidden = HiddenSongsScope.maybeOf(context);
  if (hidden == null) return null;
  final messenger = ScaffoldMessenger.of(context);
  return hidden.contains(hit)
      ? MenuSheetEntry(
          Icons.visibility_outlined,
          'Przestań ukrywać',
          onTap: () => hidden.toggle(hit),
        )
      : MenuSheetEntry(
          Icons.block,
          'Ukryj utwór',
          onTap: () async {
            await hidden.toggle(hit);
            messenger
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  persist: false,
                  content: Text(
                    'Ukryto „${hit.title}” — kolejka, Odkrywaj i radio go pominą.',
                  ),
                  action: SnackBarAction(
                    label: 'Cofnij',
                    onPressed: () => hidden.toggle(hit),
                  ),
                ),
              );
          },
        );
}

/// "Pobierz utwór" in a song's menu — "Pobieram…" while it downloads, "Usuń z pobranych" once
/// it's on the phone; `null` for a file of the phone's own (or without [Downloads]).
MenuSheetEntry? downloadEntry(BuildContext context, SearchHit hit) {
  final downloads = DownloadsScope.maybeOf(context);
  if (downloads == null || hit.onPhone) return null;
  if (downloads.isDownloading(hit)) {
    return MenuSheetEntry(Icons.downloading, 'Pobieram…', onTap: () {});
  }
  if (downloads.isDownloaded(hit)) {
    return MenuSheetEntry(
      Icons.download_done,
      'Usuń z pobranych',
      onTap: () => downloads.remove([hit]),
    );
  }
  final messenger = ScaffoldMessenger.of(context);
  return MenuSheetEntry(
    Icons.download_outlined,
    'Pobierz utwór',
    onTap: () async {
      final failed = await downloads.download([hit]);
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              failed == 0
                  ? 'Pobrano „${hit.title}” — zagra też bez internetu.'
                  : 'Nie udało się pobrać „${hit.title}”.',
            ),
          ),
        );
    },
  );
}

/// "Przejdź do radia utworu": [songRadio] for [seed], worked out once for the screen (it goes
/// through all of music.db) and again only for a new music.db.
Future<void> openSongRadio(BuildContext context, CatalogSong seed) {
  List<CatalogSong>? songs;
  CatalogSong? from;
  return SongListScreen.open(
    context,
    title: 'Radio: ${seed.title}',
    subtitle: 'Radio utworu',
    songs: (context) {
      final catalog = SongCatalogScope.of(context);
      final library = LocalLibraryScope.of(context);
      final youTube = YouTubeLibraryScope.of(context);
      // A new music.db gives the seed a new object.
      final now = catalog.current(seed.id) ?? seed;
      if (songs == null || !identical(from, now)) {
        from = now;
        songs = songRadio(
          now,
          catalog.songs,
          moodsOf: MoodLibraryScope.maybeOf(context)?.moodKeysOf,
        );
      }
      final hidden = HiddenSongsScope.maybeOf(context);
      return [
        for (final (i, song) in songs!.indexed)
          if (withPhoneYouTube(
                SearchHit.main(song, library.filesOf(song.id)),
                youTube,
              )
              case final hit
              // The seed stays: the radio is of it.
              when i == 0 || !(hidden?.contains(hit) ?? false))
            hit,
      ];
    },
  );
}

/// "Przejdź do albumu": the songs carrying [album]'s name — a full album of it first, to
/// listen to it whole.
Future<void> openAlbumSongs(BuildContext context, String album) =>
    SongListScreen.open(
      context,
      title: album,
      subtitle: 'Album',
      songs: (context) {
        final hits = [
          for (final hit in searchEverywhere(
            album,
            SongCatalogScope.of(context),
            LocalLibraryScope.of(context),
            youTube: YouTubeLibraryScope.of(context),
            fields: const {SearchField.album},
          ))
            if (hit.album == album) hit,
        ];
        return [
          ...hits.where((hit) => hit.isFullAlbum),
          ...hits.where((hit) => !hit.isFullAlbum),
        ];
      },
    );
