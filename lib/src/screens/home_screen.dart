import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/account.dart';
import '../data/home_layout.dart';
import '../data/home_recommendations.dart';
import '../data/latin_names.dart';
import '../data/library_folders.dart';
import '../data/listening_log.dart';
import '../data/listening_stats.dart';
import '../data/local_library.dart';
import '../data/moods.dart';
import '../data/play_history.dart';
import '../data/playlist_library.dart';
import '../data/saved_songs.dart';
import '../data/song_catalog.dart';
import '../data/startup_covers.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/collection_cover.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/mood_sheet.dart';
import '../widgets/scrolling_text.dart';
import '../widgets/song_cover.dart';
import '../widgets/song_names.dart';
import '../widgets/song_tile.dart';
import 'library_screen.dart';
import 'listening_stats_screen.dart';
import 'mood_screen.dart';
import 'playlist_screen.dart';
import 'search_screen.dart';

const _id = 'Home';

/// Home's recommendation rows (Dostosuj stronę główną › Rekomendacje): made on the phone from the
/// listening stats and music.db ([HomeRecommendations]).
const _recommendations = {
  'rec:artists': 'Twoi najczęściej słuchani wykonawcy',
  'rec:albums': 'Albumy, do których wracasz',
  'rec:newest': 'Nowe w bazie',
  'rec:genres': 'Twoje gatunki',
  'rec:forgotten': 'Zapomniane',
};

/// Home's rows made from what's on the phone.
const _librarySections = {
  'lib:recent': 'Ostatnio odtwarzane',
  'lib:liked': 'Polubione utwory',
  'lib:playlists': 'Twoje playlisty',
  'lib:moods': 'Twoje nastroje',
  'lib:saved': 'Na później',
};

/// The chips over Home: which rows show.
enum _HomeFilter {
  all('Wszystko'),
  songs('Utwory'),
  playlists('Playlisty'),
  moods('Nastroje');

  const _HomeFilter(this.label);

  final String label;

  /// Rows of artists, albums and genres show only with "Wszystko".
  bool shows(String id) => switch (this) {
    all => true,
    songs => const {
      'lib:recent',
      'lib:liked',
      'lib:saved',
      'rec:newest',
      'rec:forgotten',
    }.contains(id),
    playlists => id == 'lib:playlists' || id.startsWith('playlist:'),
    moods => id == 'lib:moods' || id.startsWith('mood:'),
  };
}

const _cardWidth = 144.0;
const _rowLimit = 12;

/// Home: rows the user arranges ([HomeLayout]) — pinned ones first, each with "⋯" (pin, move,
/// hide), and "Dostosuj stronę główną" next to the filter chips (Juxtopposed's Spotify
/// redesign).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// [HomeLayout.defaults].
  static final defaultSections = [
    ..._librarySections.keys,
    ..._recommendations.keys,
  ];

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _HomeFilter _filter = _HomeFilter.all;

  /// The recommendations, from the plays read for [_readFor] (the account and the play going on).
  HomeRecommendations? _recommended;
  Object? _readFor;
  int _reading = 0;

  /// The [_readFor] [_recommended] was made for: until it's the current one, the rows wait.
  Object? _recommendedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final log = ListeningLogScope.maybeOf(context);
    final user = AccountScope.maybeOf(context)?.userName;
    final catalog = SongCatalogScope.maybeOf(context);
    final readFor = (user, log?.current?.uid, catalog?.songCount);
    if (log == null || catalog == null || readFor == _readFor) return;
    _readFor = readFor;
    final reading = ++_reading;
    log.listens(account: user).then((listens) {
      if (!mounted || reading != _reading) return;
      setState(() {
        _recommended = HomeRecommendations.of(listens, song: catalog.current);
        _recommendedFor = readFor;
      });
    });
  }

  /// Only for widget tests without [HomeLayoutScope].
  final _fallback = HomeLayout(defaults: HomeScreen.defaultSections);

  @override
  void dispose() {
    _fallback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayoutScope.maybeOf(context) ?? _fallback;
    return ListenableBuilder(
      listenable: layout,
      builder: (context, _) {
        final recommendationsReady = _recommendedFor == _readFor;
        final shown = [
          for (final id in layout.visible)
            if (_filter.shows(id)) id,
        ];
        final sections = [
          for (final id in shown)
            if (_HomeSection.stillReading(context, id, recommendationsReady))
              ?_HomeSection.reading(id, layout.lastShown[id])
            else
              ?_HomeSection.of(context, id, _recommended),
        ];
        if (_filter == _HomeFilter.all &&
            !shown.any(
              (id) =>
                  _HomeSection.stillReading(context, id, recommendationsReady),
            )) {
          final rows = {
            for (final section in sections) section.id: section.title,
          };
          if (!mapEquals(rows, layout.lastShown)) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => layout
                  .rememberShown(rows)
                  .catchError(
                    (Object e) =>
                        debugPrint('Remembering Home rows failed: $e'),
                  ),
            );
          }
        }
        return SafeArea(
          child: Column(
            children: [
              TabHeader(
                content: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in _HomeFilter.values) ...[
                        if (filter.index > 0) const SizedBox(width: 8),
                        PillChip(
                          label: filter.label,
                          selected: filter == _filter,
                          onTap: () => setState(() => _filter = filter),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Dostosuj stronę główną',
                    icon: const Icon(Icons.tune),
                    onPressed: () => CustomizeHomeScreen.open(context, layout),
                  ),
                ],
              ),
              Expanded(
                child: sections.isEmpty
                    ? _NothingShown(layout: layout)
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: sections.length,
                        itemBuilder: (context, i) => _SectionRow(
                          section: sections[i],
                          layout: layout,
                          row: i,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One of Home's rows: its title and what it holds, for a section id.
class _HomeSection {
  const _HomeSection(this.id, this.title, this.height, this.cards);

  final String id;
  final String title;
  final double height;

  /// Built lazily; an empty list shows a note instead.
  final List<Widget> Function(BuildContext context) cards;

  /// The place of a row still being read at start ([stillReading]), titled as it was
  /// [HomeLayout.lastShown]; `null` when it wasn't shown then, as it may well be empty.
  static _HomeSection? reading(String id, String? title) => title == null
      ? null
      : _HomeSection(
          id,
          title,
          id == 'rec:artists' ? 185 : 205,
          (_) => List.filled(4, const _CardPlaceholder()),
        );

  /// Whether what [id] shows is still being read at start: an empty row then isn't empty yet.
  static bool stillReading(
    BuildContext context,
    String id,
    bool recommendationsReady,
  ) {
    final catalogRead = _catalogRead(context);
    if (_recommendations.containsKey(id)) {
      return !catalogRead || !recommendationsReady;
    }
    final playlistsRead = PlaylistLibraryScope.maybeOf(context)?.loaded ?? true;
    final moodsRead = MoodLibraryScope.maybeOf(context)?.loaded ?? true;
    return switch (id) {
      'lib:recent' => !(PlayHistoryScope.maybeOf(context)?.loaded ?? true),
      'lib:liked' => !(LikedSongsScope.maybeOf(context)?.loaded ?? true),
      'lib:saved' => !(SavedSongsScope.maybeOf(context)?.loaded ?? true),
      'lib:playlists' => !playlistsRead,
      'lib:moods' => !moodsRead,
      _ when id.startsWith('playlist:') => !playlistsRead,
      // A global mood's songs are music.db's.
      _ when id.startsWith('mood:') => !moodsRead || !catalogRead,
      _ => false,
    };
  }

  /// `null` when the section's playlist / mood is gone, or a library row has nothing to show.
  static _HomeSection? of(
    BuildContext context,
    String id,
    HomeRecommendations? recommended,
  ) {
    if (_recommendations[id] case final title?) {
      return _recommendation(context, id, title, recommended);
    }
    final catalog = SongCatalogScope.maybeOf(context);
    final library = LocalLibraryScope.maybeOf(context);
    final youTube = YouTubeLibraryScope.maybeOf(context);
    final playlists = PlaylistLibraryScope.maybeOf(context);
    final moods = MoodLibraryScope.maybeOf(context);
    const songHeight = 205.0;
    switch (id) {
      case 'lib:recent':
        final history = PlayHistoryScope.maybeOf(context);
        if (history == null || history.entries.isEmpty) return null;
        if (catalog == null || library == null || youTube == null) return null;
        final seen = <String>{};
        final tracks = [
          for (final played in history.entries)
            if (seen.add(played.track.key)) played.track,
        ].take(_rowLimit).toList();
        final hits = [
          for (final track in tracks)
            resolveTrack(track, catalog, library, youTube),
        ];
        return _HomeSection(
          id,
          _librarySections[id]!,
          songHeight,
          (_) => _songCards(hits, keys: [for (final t in tracks) t.key]),
        );
      case 'lib:saved' || 'lib:liked':
        final StoredSongList? saved = id == 'lib:liked'
            ? LikedSongsScope.maybeOf(context)
            : SavedSongsScope.maybeOf(context);
        if (saved == null || saved.songs.isEmpty) return null;
        if (catalog == null || library == null || youTube == null) return null;
        final refs = saved.songs.take(_rowLimit).toList();
        final hits = [
          for (final ref in refs) resolveTrack(ref, catalog, library, youTube),
        ];
        return _HomeSection(
          id,
          _librarySections[id]!,
          songHeight,
          (_) => _songCards(hits, keys: [for (final r in refs) r.key]),
        );
      case 'lib:playlists':
        if (playlists == null || playlists.playlists.isEmpty) return null;
        return _HomeSection(
          id,
          _librarySections[id]!,
          songHeight,
          (_) => [
            for (final p in playlists.playlists.take(_rowLimit))
              _PlaylistCard(playlist: p),
          ],
        );
      case 'lib:moods':
        if (moods == null) return null;
        final all = [...moods.userMoods, ...moods.globalMoods];
        if (all.isEmpty) return null;
        return _HomeSection(
          id,
          _librarySections[id]!,
          songHeight,
          (_) => [
            for (final mood in all.take(_rowLimit)) _MoodCard(mood: mood),
          ],
        );
    }
    if (id.startsWith('playlist:')) {
      final playlist = playlists?.byId(int.tryParse(id.substring(9)) ?? -1);
      if (playlist == null) return null;
      return _HomeSection(
        id,
        playlist.name,
        songHeight,
        (_) => [_PlaylistSongs(playlist: playlist)],
      );
    }
    if (id.startsWith('mood:')) {
      final key = id.substring(5);
      final mood = [
        ...?moods?.userMoods,
        ...?moods?.globalMoods,
      ].where((m) => m.key == key).firstOrNull;
      if (mood == null || catalog == null || library == null) return null;
      if (youTube == null) return null;
      final hits = moodHits(mood, catalog, library, youTube);
      return _HomeSection(
        id,
        mood.name,
        songHeight,
        (_) => _songCards(
          hits.take(_rowLimit).toList(),
          playlistName: mood.name,
          moodKey: mood.key,
        ),
      );
    }
    return null;
  }

  /// A recommendation row; `null` while there's nothing to recommend (no plays yet, no
  /// genres in music.db).
  static _HomeSection? _recommendation(
    BuildContext context,
    String id,
    String title,
    HomeRecommendations? recommended,
  ) {
    const songHeight = 205.0;
    final catalog = SongCatalogScope.maybeOf(context);
    final library = LocalLibraryScope.maybeOf(context);
    final youTube = YouTubeLibraryScope.maybeOf(context);
    if (catalog == null || library == null || youTube == null) return null;
    final stats = recommended?.stats;
    switch (id) {
      case 'rec:newest':
        if (catalog.songs.isEmpty) return null;
        // MusicDatabase numbers songs as they're added.
        final newest = [...catalog.songs]..sort((a, b) => b.id.compareTo(a.id));
        final hits = [
          for (final song in newest.take(_rowLimit))
            withPhoneYouTube(
              SearchHit.main(song, library.filesOf(song.id)),
              youTube,
            ),
        ];
        return _HomeSection(
          id,
          title,
          songHeight,
          (_) => _songCards(hits, playlistName: title),
        );
      case 'rec:forgotten':
        final forgotten = recommended?.forgotten ?? const <StatsSong>[];
        if (forgotten.isEmpty) return null;
        return _HomeSection(
          id,
          title,
          songHeight,
          (context) => _songCards([
            for (final song in forgotten.take(_rowLimit))
              hitOfStatsSong(context, song),
          ], playlistName: title),
        );
      case 'rec:artists':
        final artists = [
          for (final a in stats?.artists ?? const <StatsEntry>[])
            if (a.plays > 0) a,
        ];
        if (artists.isEmpty) return null;
        return _HomeSection(
          id,
          title,
          185,
          (_) => [
            for (final artist in artists.take(_rowLimit))
              _ArtistCard(artist: artist),
          ],
        );
      case 'rec:albums':
        final albums = [
          for (final a in stats?.albums ?? const <StatsEntry>[])
            if (a.plays > 0) a,
        ];
        if (albums.isEmpty) return null;
        return _HomeSection(
          id,
          title,
          songHeight,
          (_) => [
            for (final album in albums.take(_rowLimit))
              _AlbumCard(album: album),
          ],
        );
      case 'rec:genres':
        // Before anything was heard: the day's genres, like Wyszukaj's "Odkryj coś nowego".
        final genres = recommended?.genres.isNotEmpty ?? false
            ? recommended!.genres
            : discoverGenres(catalog);
        if (genres.isEmpty) return null;
        return _HomeSection(
          id,
          title,
          songHeight,
          (_) => [
            for (final genre in genres.take(_rowLimit))
              _Card(
                cover: CoverArt(
                  seed: '#$genre',
                  size: _cardWidth,
                  icon: Icons.tag,
                ),
                title: genre,
                subtitle: 'Gatunek',
                onTap: () => openGenreSongs(context, genre),
              ),
          ],
        );
    }
    return null;
  }

  /// Its title in "Dostosuj stronę główną", also when it shows nothing now.
  static String titleFor(BuildContext context, String id) {
    if (_recommendations[id] case final title?) return title;
    if (_librarySections[id] case final title?) return title;
    if (id.startsWith('playlist:')) {
      return PlaylistLibraryScope.maybeOf(context)
              ?.byId(int.tryParse(id.substring(9)) ?? -1)
              ?.name ??
          'Usunięta playlista';
    }
    if (id.startsWith('mood:')) {
      final moods = MoodLibraryScope.maybeOf(context);
      return [
            ...?moods?.userMoods,
            ...?moods?.globalMoods,
          ].where((m) => m.key == id.substring(5)).firstOrNull?.name ??
          'Usunięty nastrój';
    }
    return id;
  }
}

/// [keys]: what each song is kept as ([TrackRef.key]), for a row whose songs are found again
/// from what the phone keeps; the same before music.db has loaded and after.
List<Widget> _songCards(
  List<SearchHit> hits, {
  String? playlistName,
  String? moodKey,
  int? playlistId,
  String? youTubeListId,
  List<String>? keys,
}) => [
  for (final (i, hit) in hits.indexed)
    _SongCard(
      hit: hit,
      songKey: keys?[i] ?? TrackRef.of(hit).key,
      onTap: (context) {
        final queue = PlaybackQueueScope.of(context);
        runQueueAction(
          context,
          (onStatus) => queue.start(
            hits,
            i,
            playlistId: playlistId,
            youTubeListId: youTubeListId,
            playlistName: playlistName,
            moodKey: moodKey,
            onStatus: onStatus,
          ),
        );
      },
    ),
];

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.section,
    required this.layout,
    required this.row,
  });

  final _HomeSection section;
  final HomeLayout layout;

  /// Its place on Home, from the top.
  final int row;

  /// The cards on screen as Home opens, whose covers show from the start ([StartupCovers]).
  static const _startupRows = 3;
  static const _startupCards = 3;

  @override
  Widget build(BuildContext context) {
    final cards = section.cards(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          section.title,
          icon: layout.isPinned(section.id) ? Icons.push_pin : null,
          trailing: InkResponse(
            onTap: () => _showSectionMenu(context, section, layout),
            radius: 20,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.more_horiz,
                semanticLabel: 'Menu sekcji (⋯)',
                color: context.palette.textSecondary,
              ),
            ),
          ),
        ),
        SizedBox(
          height: section.height,
          // One sideways scroll holds the whole row — no "Pokaż wszystko".
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => row < _startupRows && i < _startupCards
                ? _StartupSlot(slot: 'home:${section.id}#$i', child: cards[i])
                : cards[i],
          ),
        ),
      ],
    );
  }
}

Future<void> _showSectionMenu(
  BuildContext context,
  _HomeSection section,
  HomeLayout layout,
) {
  final pinned = layout.isPinned(section.id);
  return showMenuSheet(
    context,
    idPrefix: '$_id › Sekcja › Menu (⋯)',
    header: MenuSheetHeader(
      cover: const Icon(Icons.view_agenda_outlined, size: 40),
      title: section.title,
      subtitle: 'Sekcja strony głównej',
    ),
    entries: [
      MenuSheetEntry(
        pinned ? Icons.push_pin : Icons.push_pin_outlined,
        pinned ? 'Odepnij' : 'Przypnij na górze',
        onTap: () => layout.setPinned(section.id, !pinned),
      ),
      MenuSheetEntry(
        Icons.arrow_upward,
        'Przenieś wyżej',
        onTap: () => layout.move(section.id, -1),
      ),
      MenuSheetEntry(
        Icons.arrow_downward,
        'Przenieś niżej',
        onTap: () => layout.move(section.id, 1),
      ),
      if (layout.isAdded(section.id))
        MenuSheetEntry(
          Icons.remove_circle_outline,
          'Usuń sekcję',
          onTap: () => layout.remove(section.id),
        )
      else
        MenuSheetEntry(
          Icons.visibility_off_outlined,
          'Ukryj sekcję',
          subtitle: 'Wróci w „Dostosuj stronę główną”',
          onTap: () => layout.setHidden(section.id, true),
        ),
      MenuSheetEntry(
        Icons.tune,
        'Dostosuj stronę główną',
        onTap: () => CustomizeHomeScreen.open(context, layout),
      ),
    ],
  );
}

class _NothingShown extends StatelessWidget {
  const _NothingShown({required this.layout});

  final HomeLayout layout;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Strona główna jest pusta.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.palette.textSecondary),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.tune),
            label: const Text('Dostosuj stronę główną'),
            onPressed: () => CustomizeHomeScreen.open(context, layout),
          ),
        ],
      ),
    ),
  );
}

/// A card of a song: its cover, title and artist; tapping plays the row from it.
class _SongCard extends StatelessWidget {
  const _SongCard({
    required this.hit,
    required this.songKey,
    required this.onTap,
  });

  final SearchHit hit;

  /// The song as the phone keeps it, which tells the card [StartupCovers] remembered for this
  /// place: its names may still change as music.db loads (a video's title, then music.db's).
  final String songKey;
  final void Function(BuildContext context) onTap;

  @override
  Widget build(BuildContext context) {
    var (title, subtitle) = (hit.shownTitle(context), hit.shownArtist(context));
    final slot = _StartupSlot.of(context);
    final check = songKey;
    // Before music.db, the song is looked for without its album, and named without its Latin
    // form.
    final settled = _catalogRead(context);
    final startup = AlbumCoversScope.maybeOf(context)?.startup;
    if (slot != null && settled) {
      startup?.rememberTexts(slot, check, title, subtitle);
    } else if (slot != null) {
      // As it was shown last time until music.db can say so again.
      if (startup?.of(slot, check) case StartupCover(
        title: final shownTitle?,
        subtitle: final shownSubtitle?,
      )) {
        (title, subtitle) = (shownTitle, shownSubtitle);
      }
    }
    return _Card(
      cover: SongCover(
        cover: CoverRequest.of(hit),
        size: _cardWidth,
        startup: slot == null
            ? null
            : (slot: slot, check: check, settled: settled),
      ),
      title: title,
      subtitle: subtitle,
      onTap: () => onTap(context),
      onLongPress: () => showSongMenu(context, hit, idPrefix: '$_id › Utwór'),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist});

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) => _Card(
    cover: PlaylistCover(playlist: playlist, size: _cardWidth),
    title: playlist.name,
    subtitle: playlist.source == PlaylistSource.spotifyAlbum
        ? 'Album'
        : 'Playlista',
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistScreen(playlist: playlist),
      ),
    ),
    onLongPress: () => showLibraryEntryMenu(
      context,
      PlaylistEntry(playlist),
      PlaylistCover(playlist: playlist, size: 56),
      playlist.source == PlaylistSource.spotifyAlbum ? 'Album' : 'Playlista',
    ),
  );
}

class _MoodCard extends StatelessWidget {
  const _MoodCard({required this.mood});

  final Mood mood;

  @override
  Widget build(BuildContext context) => _Card(
    cover: MoodCover(mood: mood, size: _cardWidth),
    title: mood.name,
    subtitle: mood.global ? 'Nastrój globalny' : 'Twój nastrój',
    onTap: () => MoodScreen.open(context, mood),
    onLongPress: () => showLibraryEntryMenu(
      context,
      MoodEntry(mood),
      MoodCover(mood: mood, size: 56),
      mood.global ? 'Nastrój globalny' : 'Twój nastrój',
    ),
  );
}

/// The songs of a playlist added to Home, read when the row shows.
class _PlaylistSongs extends StatelessWidget {
  const _PlaylistSongs({required this.playlist});

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context) {
    final playlists = PlaylistLibraryScope.of(context);
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    return FutureBuilder(
      future: playlists.tracks(playlist.id),
      builder: (context, snapshot) {
        final hits = [
          for (final track in (snapshot.data ?? const []).take(_rowLimit))
            playlistHit(track, catalog, library, youTube),
        ];
        if (hits.isEmpty) {
          return SizedBox(
            width: _cardWidth * 2,
            child: Text(
              snapshot.hasData ? 'Pusta playlista' : '',
              style: TextStyle(color: context.palette.textSecondary),
            ),
          );
        }
        return Row(
          children: [
            for (final (i, card) in _songCards(
              hits,
              playlistId: playlist.id,
              playlistName: playlist.name,
              youTubeListId: playlist.youTubeId,
            ).indexed) ...[if (i > 0) const SizedBox(width: 14), card],
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.cover,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
  });

  final Widget cover;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// The card's menu: "Dodaj do kolejki", "Odtwórz jako następny"…
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    onLongPress: onLongPress,
    child: SizedBox(
      width: _cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cover,
          const SizedBox(height: 8),
          ScrollingText(title),
          ScrollingText(
            subtitle,
            style: TextStyle(
              color: context.palette.textSecondary,
              fontSize: AppFontSize.small,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Whether music.db's songs are read, or there are none to read.
bool _catalogRead(BuildContext context) {
  final catalog = SongCatalogScope.maybeOf(context);
  return catalog == null ||
      const {
        CatalogStatus.ready,
        CatalogStatus.noDatabase,
        CatalogStatus.error,
      }.contains(catalog.status);
}

/// A card among the first on Home ([_SectionRow]), named for [StartupCovers].
class _StartupSlot extends InheritedWidget {
  const _StartupSlot({required this.slot, required super.child});

  final String slot;

  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_StartupSlot>()?.slot;

  @override
  bool updateShouldNotify(_StartupSlot old) => slot != old.slot;
}

/// A card's place in a row still being read at start ([_HomeSection.reading]).
class _CardPlaceholder extends StatelessWidget {
  const _CardPlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final box = Container(
      width: _cardWidth,
      height: _cardWidth,
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: palette.radius(4),
      ),
    );
    // The card shown in this place last time, which is most likely what comes.
    if (_StartupSlot.of(context) case final slot?) {
      final shown = AlbumCoversScope.maybeOf(context)?.startup?.at(slot);
      if (shown != null && shown.title != null) {
        return _Card(
          cover: ClipRRect(
            borderRadius: palette.radius(4),
            child: Image(
              image: coverImageFor(
                context,
                FileImage(shown.file),
                _cardWidth,
                shown.seed,
              ),
              width: _cardWidth,
              height: _cardWidth,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => box,
            ),
          ),
          title: shown.title!,
          subtitle: shown.subtitle ?? '',
          onTap: () {},
        );
      }
    }
    Widget bar(double width) => Container(
      width: width,
      height: AppFontSize.small,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: palette.radius(2),
      ),
    );
    return SizedBox(
      width: _cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box,
          const SizedBox(height: 4),
          bar(_cardWidth * 0.7),
          bar(_cardWidth * 0.45),
        ],
      ),
    );
  }
}

/// A recommended artist: their most played song's cover in a circle; tapping opens their songs.
class _ArtistCard extends StatelessWidget {
  const _ArtistCard({required this.artist});

  final StatsEntry artist;

  @override
  Widget build(BuildContext context) {
    final song = artist.song;
    final name = showsLatinNames(context)
        ? withLatin(artist.name, artist.latin)
        : artist.name;
    return InkWell(
      onTap: () => openArtistSongs(context, artist.name),
      onLongPress: () => showSongsMenu(
        context,
        cover: CoverArt(seed: artist.name, size: 56, icon: Icons.person),
        title: name,
        subtitle: 'Wykonawca',
        hits: artistSongs(context, artist.name),
      ),
      child: SizedBox(
        width: _cardWidth,
        child: Column(
          children: [
            ClipOval(
              child: song == null
                  ? CoverArt(
                      seed: artist.name,
                      size: _cardWidth,
                      icon: Icons.person,
                      circle: true,
                    )
                  : SongCover(
                      cover: CoverRequest.of(hitOfStatsSong(context, song)),
                      size: _cardWidth,
                    ),
            ),
            const SizedBox(height: 8),
            ScrollingText(name, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// A recommended album: its most played song's cover; tapping opens the album's songs.
class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final StatsEntry album;

  @override
  Widget build(BuildContext context) {
    final song = album.song;
    return _Card(
      cover: song == null
          ? CoverArt(seed: album.name, size: _cardWidth, icon: Icons.album)
          : SongCover(
              cover: CoverRequest.of(hitOfStatsSong(context, song)),
              size: _cardWidth,
            ),
      title: album.name,
      subtitle: album.detail ?? 'Album',
      onTap: () => openAlbumSongs(context, album.name),
      onLongPress: () => showSongsMenu(
        context,
        cover: CoverArt(seed: album.name, size: 56, icon: Icons.album),
        title: album.name,
        subtitle: album.detail ?? 'Album',
        hits: albumSongs(context, album.name),
      ),
    );
  }
}

/// "Dostosuj stronę główną": every section with a switch (shown or hidden) and a pin, dragged
/// into order; "Rekomendacje" turns the recommended rows on and off; rows can be added from
/// Biblioteka (a playlist's or a mood's songs).
class CustomizeHomeScreen extends StatelessWidget {
  const CustomizeHomeScreen({super.key, required this.layout});

  final HomeLayout layout;

  static Future<void> open(BuildContext context, HomeLayout layout) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CustomizeHomeScreen(layout: layout),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListenableBuilder(
      listenable: layout,
      builder: (context, _) {
        final all = layout.all;
        return Scaffold(
          appBar: AppBar(title: const Text('Dostosuj stronę główną')),
          body: CustomScrollView(
            slivers: [
              SliverList.list(
                children: [
                  SwitchListTile(
                    title: const Text('Rekomendacje'),
                    subtitle: const Text(
                      'Wykonawcy, albumy, gatunki, nowe i zapomniane utwory — '
                      'z tego, czego słuchasz',
                    ),
                    value: layout.recommendations,
                    onChanged: layout.setRecommendations,
                  ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Dodaj sekcję z Biblioteki'),
                    subtitle: const Text(
                      'Utwory wybranej playlisty albo nastroju',
                    ),
                    onTap: () => _addFromLibrary(context),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      'Przytrzymaj ≡ i przeciągnij, żeby zmienić kolejność. '
                      'Przypięte są zawsze na górze.',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: AppFontSize.small,
                      ),
                    ),
                  ),
                ],
              ),
              SliverReorderableList(
                itemCount: all.length,
                onReorderItem: layout.reorder,
                itemBuilder: (context, i) {
                  final id = all[i];
                  final recommended = id.startsWith('rec:');
                  return Material(
                    key: ValueKey(id),
                    color: palette.background,
                    child: ListTile(
                      leading: Checkbox(
                        value: !layout.isHidden(id),
                        onChanged: (shown) =>
                            layout.setHidden(id, !(shown ?? true)),
                      ),
                      title: Text(
                        HomeScreenTitles.of(context, id),
                        style: TextStyle(
                          color: recommended && !layout.recommendations
                              ? palette.textSecondary
                              : null,
                        ),
                      ),
                      subtitle: recommended
                          ? const Text('Rekomendacja')
                          : layout.isAdded(id)
                          ? const Text('Z Biblioteki')
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: layout.isPinned(id)
                                ? 'Odepnij'
                                : 'Przypnij na górze',
                            icon: Icon(
                              layout.isPinned(id)
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                              color: layout.isPinned(id)
                                  ? palette.accent
                                  : null,
                            ),
                            onPressed: () =>
                                layout.setPinned(id, !layout.isPinned(id)),
                          ),
                          if (layout.isAdded(id))
                            IconButton(
                              tooltip: 'Usuń sekcję',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => layout.remove(id),
                            ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addFromLibrary(BuildContext context) {
    final playlists = PlaylistLibraryScope.maybeOf(context)?.playlists ?? [];
    final moods = MoodLibraryScope.maybeOf(context);
    return showMenuSheet(
      context,
      idPrefix: 'Dostosuj stronę główną › Dodaj sekcję',
      header: const ListTile(
        title: Text(
          'Dodaj sekcję z Biblioteki',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      entries: [
        for (final p in playlists)
          MenuSheetEntry(
            Icons.queue_music,
            p.name,
            onTap: () => layout.add('playlist:${p.id}'),
          ),
        for (final mood in [...?moods?.userMoods, ...?moods?.globalMoods])
          MenuSheetEntry(
            moodIcon,
            mood.name,
            onTap: () => layout.add('mood:${mood.key}'),
          ),
      ],
    );
  }
}

/// Section titles for screens outside this file.
abstract final class HomeScreenTitles {
  static String of(BuildContext context, String id) =>
      _HomeSection.titleFor(context, id);
}
