import 'dart:math';

import 'package:flutter/material.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/local_library.dart';
import '../data/moods.dart';
import '../data/hidden_songs.dart';
import '../data/saved_songs.dart';
import '../data/song_catalog.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import '../playback/playback_queue.dart';
import '../playback/player_controller.dart';
import '../theme.dart';
import '../widgets/playlist_picker.dart';
import '../widgets/share_sheet.dart';
import '../widgets/song_cover.dart';
import '../widgets/song_names.dart';
import '../widgets/song_tile.dart';

const _id = 'Odkrywaj';
const _deckSize = 30;

/// "Odkrywaj": one song at a time, swiped up for the next, from a category picked at the top —
/// songs from all of MusicDatabase, or a mood's. Beside each: save it for later (apart
/// from playlists and liked songs), add to a playlist, share (Juxtopposed's Spotify redesign,
/// which moved the reference app's autoplaying Home feed here). Nothing plays until ▶ is tapped.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  /// `null`: everything ("Wszystko"); else a mood's key.
  String? _category;
  final _decks = <String?, List<SearchHit>>{};

  /// The catalog's size the decks were drawn from; a new download draws them again.
  int _drawnFrom = -1;
  int _seed = DateTime.now().millisecondsSinceEpoch;

  List<SearchHit> _deck(
    BuildContext context,
    SongCatalog catalog,
    LocalLibrary library,
    YouTubeLibrary youTube,
    List<Mood> moods,
  ) {
    if (catalog.songCount != _drawnFrom) {
      _drawnFrom = catalog.songCount;
      _decks.clear();
    }
    return _decks[_category] ??= _draw(catalog, library, youTube, moods);
  }

  List<SearchHit> _draw(
    SongCatalog catalog,
    LocalLibrary library,
    YouTubeLibrary youTube,
    List<Mood> moods,
  ) {
    final random = Random(_seed ^ (_category?.hashCode ?? 0));
    final mood = moods.where((m) => m.key == _category).firstOrNull;
    if (mood != null) {
      return (moodHits(
        mood,
        catalog,
        library,
        youTube,
      )..shuffle(random)).take(_deckSize).toList();
    }
    final songs = [
      for (final song in catalog.songs)
        if (!song.isFullAlbum) song,
    ];
    if (songs.isEmpty) return <SearchHit>[];
    final picked = <int>{};
    while (picked.length < min(_deckSize, songs.length)) {
      picked.add(random.nextInt(songs.length));
    }
    return [
      for (final i in picked)
        withPhoneYouTube(
          SearchHit.main(songs[i], library.filesOf(songs[i].id)),
          youTube,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final moodLibrary = MoodLibraryScope.maybeOf(context);
    final moods = [...?moodLibrary?.globalMoods, ...?moodLibrary?.userMoods];
    final hidden = HiddenSongsScope.maybeOf(context);
    final deck = [
      for (final hit in _deck(context, catalog, library, youTube, moods))
        if (!(hidden?.contains(hit) ?? false)) hit,
    ];
    final categories = <(String?, String)>[
      (null, 'Wszystko'),
      for (final mood in moods) (mood.key, mood.name),
    ];
    return SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final (key, name) in categories)
                  _CategoryTab(
                    label: name,
                    selected: key == _category,
                    onTap: () => setState(() => _category = key),
                  ),
                IconButton(
                  tooltip: 'Wylosuj inne',
                  icon: const Icon(Icons.casino_outlined),
                  onPressed: () => setState(() {
                    _seed++;
                    _decks.clear();
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: deck.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        catalog.songCount == 0
                            ? 'Nie ma jeszcze bazy danych MusicDatabase na telefonie '
                                  '(Ustawienia › Serwer).'
                            : 'Brak utworów w tej kategorii.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ),
                  )
                : PageView.builder(
                    key: ValueKey('$_category $_seed'),
                    scrollDirection: Axis.vertical,
                    itemCount: deck.length,
                    itemBuilder: (context, i) => _DiscoverCard(
                      hit: deck[i],
                      onPlay: ({required bool fragment}) {
                        final queue = PlaybackQueueScope.of(context);
                        final player = PlayerScope.of(context);
                        final mood = moods
                            .where((m) => m.key == _category)
                            .firstOrNull;
                        runQueueAction(context, (onStatus) async {
                          final outcome = await queue.start(
                            deck,
                            i,
                            playlistName: mood?.name ?? 'Odkrywaj',
                            moodKey: mood?.key,
                            onStatus: onStatus,
                          );
                          if (fragment && outcome.played && !outcome.external) {
                            await _skipIntoSong(player, queue, deck[i]);
                          }
                          return outcome;
                        });
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// "Fragment": the song from about a third in, past the intro, where its best part usually
/// is — once the player knows how long it is (a few seconds at most).
Future<void> _skipIntoSong(
  PlayerController player,
  PlaybackQueue queue,
  SearchHit hit,
) async {
  for (var i = 0; i < 50 && player.duration == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final duration = player.duration;
  final current = queue.current;
  if (duration == null || current == null) return;
  if (TrackRef.of(current).key != TrackRef.of(hit).key) return;
  await player.seek(duration * 0.3);
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? palette.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : null,
            color: selected ? palette.textPrimary : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard({required this.hit, required this.onPlay});

  final SearchHit hit;
  final void Function({required bool fragment}) onPlay;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final saved = SavedSongsScope.maybeOf(context);
    final isSaved = saved?.contains(hit) ?? false;
    final song = hit.mainSong;
    final playing =
        song != null &&
        PlayerScope.of(context).playing &&
        PlaybackQueueScope.maybeOf(context)?.current?.mainSong?.id == song.id;
    final tags = [
      if (song?.year != null) '${song!.year}',
      if (song?.language case final language?
          when language.isNotEmpty && language != 'Unknown')
        language,
      if (song != null)
        ...?MoodLibraryScope.maybeOf(context)?.moodNameListOf(song.id),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final coverSize = min(
          constraints.maxWidth - 116,
          constraints.maxHeight - 200,
        ).clamp(120.0, 360.0);
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: palette.radius(16),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: GestureDetector(
                          onTap: () => onPlay(fragment: true),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SongCover(
                                cover: CoverRequest.of(hit),
                                size: coverSize,
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: palette.background.withValues(
                                    alpha: 0.6,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  playing ? Icons.graphic_eq : Icons.play_arrow,
                                  size: 40,
                                  semanticLabel: 'Odtwórz',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _SideButton(
                          icon: Icons.person_outline,
                          label: 'Artysta',
                          onTap: () => openArtistSongs(
                            context,
                            artistNamesOf(hit.artistLabel).firstOrNull ??
                                hit.artistLabel,
                          ),
                        ),
                        if (saved != null)
                          _SideButton(
                            icon: isSaved
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            label: isSaved ? 'Zapisane' : 'Na później',
                            color: isSaved ? palette.accent : null,
                            onTap: () => saved.toggle(hit),
                          ),
                        if (playlistMenuEntry(context, [hit])?.onTap
                            case final onTap?)
                          _SideButton(
                            icon: Icons.add_circle_outline,
                            label: 'Dodaj',
                            onTap: onTap,
                          ),
                        _SideButton(
                          icon: Icons.share_outlined,
                          label: 'Udostępnij',
                          onTap: () =>
                              showSongShareSheet(context, hit, idPrefix: _id),
                        ),
                        _SideButton(
                          icon: Icons.more_horiz,
                          label: 'Więcej',
                          onTap: () => showSongMenu(
                            context,
                            hit,
                            idPrefix: '$_id › Menu utworu',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    height: 28,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final tag in tags)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: palette.chip,
                              borderRadius: palette.radius(14),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: AppFontSize.small,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.shownTitle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppFontSize.section,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      [
                        hit.shownArtist(context),
                        if (hit.shownAlbum(context) case final album?
                            when album.isNotEmpty)
                          album,
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.graphic_eq),
                    label: const Text('Fragment'),
                    onPressed: () => onPlay(fragment: true),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Od początku'),
                    onPressed: () => onPlay(fragment: false),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Przesuń w górę po następny',
                style: TextStyle(
                  fontSize: AppFontSize.small,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppFontSize.badge, color: color),
            ),
          ],
        ),
      ),
    ),
  );
}
