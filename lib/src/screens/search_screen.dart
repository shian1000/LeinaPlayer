import 'dart:math';

import 'package:flutter/material.dart';

import '../data/account.dart';
import '../data/combined_search.dart';
import '../data/listening_log.dart';
import '../data/listening_stats.dart';
import '../data/local_library.dart';
import '../data/moods.dart';
import '../data/song_catalog.dart';
import '../data/youtube_library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import 'listening_stats_screen.dart';
import 'mood_screen.dart';
import 'search_fields_sheet.dart';
import 'song_list_screen.dart';
import 'song_search_screen.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: TabHeader(
              title: 'Wyszukaj',
              actions: const [SearchFieldsButton()],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              // Inverted colours (light field on dark page), as in the reference app.
              child: Material(
                color: palette.textPrimary,
                borderRadius: palette.radius(6),
                child: InkWell(
                  borderRadius: palette.radius(6),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SongSearchScreen(),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, color: palette.background, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Czego chcesz posłuchać?',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.background.withValues(alpha: 0.65),
                              fontSize: AppFontSize.listTitle,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (discoverGenres(SongCatalogScope.of(context)) case final genres
              when genres.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionTitle('Odkryj coś nowego')),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 220,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: genres.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) => _DiscoverCard(
                    tag: '#${genres[i]}',
                    onTap: () => openGenreSongs(context, genres[i]),
                  ),
                ),
              ),
            ),
          ],
          ..._browseGroups(context),
          const SliverToBoxAdapter(child: SectionTitle('Inne kategorie')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: _otherCategories(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Przeglądaj" grouped under headings instead of one mix of tiles (Juxtopposed's Spotify
/// redesign), from what music.db and the moods know: moods, genres, decades, languages and the
/// artists' countries — the biggest first. Full albums aren't in them: they are mixes to play
/// through, and an album would fill 45 minutes of one.
List<Widget> _browseGroups(BuildContext context) {
  final catalog = SongCatalogScope.of(context);
  final moodLibrary = MoodLibraryScope.maybeOf(context);
  final moods = [...?moodLibrary?.globalMoods, ...?moodLibrary?.userMoods];
  final decades = <int, int>{};
  final languages = <String, int>{};
  final countries = <String, int>{};
  final genres = <String, int>{};
  for (final song in catalog.songs) {
    if (song.isFullAlbum) continue;
    for (final genre in song.genres) {
      genres.update(genre, (n) => n + 1, ifAbsent: () => 1);
    }
    // A year still to come is a mistake in music.db, not a decade to browse.
    if (song.year case final year? when year <= DateTime.now().year) {
      decades.update(year ~/ 10 * 10, (n) => n + 1, ifAbsent: () => 1);
    }
    if (song.language case final language?
        when language.isNotEmpty && language != 'Unknown') {
      languages.update(language, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final country in song.countries) {
      countries.update(country, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  List<MapEntry<K, int>> biggest<K>(Map<K, int> counts) =>
      (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .take(12)
          .toList();

  Widget group(String title, List<Widget> tiles) => SliverMainAxisGroup(
    slivers: [
      SliverToBoxAdapter(child: SectionTitle(title)),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        sliver: SliverGrid.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: tiles,
        ),
      ),
    ],
  );

  return [
    if (moods.isNotEmpty)
      group('Nastroje', [
        for (final mood in moods)
          _CategoryTile(
            name: mood.name,
            onTap: () => MoodScreen.open(context, mood),
          ),
      ]),
    if (genres.isNotEmpty)
      group('Gatunki', [
        for (final MapEntry(key: genre, value: count) in biggest(genres))
          _CategoryTile(
            name: genre,
            count: count,
            onTap: () => openGenreSongs(context, genre),
          ),
      ]),
    if (decades.isNotEmpty)
      group('Dekady', [
        for (final decade in decades.keys.toList()..sort((a, b) => b - a))
          _CategoryTile(
            // "Lata 80." only for the 1900s: 1890 or a year like 1000 (likely a mistake in
            // music.db) would read as the 1990s or "Lata 0.".
            name: decade >= 1900 && decade < 2000
                ? 'Lata ${decade % 100}.'
                : '$decade–${decade + 9}',
            count: decades[decade],
            onTap: () => SongListScreen.open(
              context,
              title: 'Lata $decade–${decade + 9}',
              subtitle: 'Dekada',
              songs: (context) => hitsWhere(
                context,
                (song) => song.year != null && song.year! ~/ 10 * 10 == decade,
                fullAlbums: false,
              ),
            ),
          ),
      ]),
    if (languages.isNotEmpty)
      group('Języki', [
        for (final MapEntry(key: language, value: count) in biggest(languages))
          _CategoryTile(
            name: language,
            count: count,
            onTap: () => SongListScreen.open(
              context,
              title: language,
              subtitle: 'Język',
              songs: (context) => hitsWhere(
                context,
                (song) => song.language == language,
                fullAlbums: false,
              ),
            ),
          ),
      ]),
    if (countries.isNotEmpty)
      group('Kraje wykonawców', [
        for (final MapEntry(key: country, value: count) in biggest(countries))
          _CategoryTile(
            name: country,
            count: count,
            onTap: () => SongListScreen.open(
              context,
              title: country,
              subtitle: 'Kraj wykonawcy',
              songs: (context) => hitsWhere(
                context,
                (song) => song.countries.contains(country),
                fullAlbums: false,
              ),
            ),
          ),
      ]),
  ];
}

/// music.db's songs passing [test], as rows, by title; without full albums
/// ([CatalogSong.isFullAlbum]) unless [fullAlbums].
List<SearchHit> hitsWhere(
  BuildContext context,
  bool Function(CatalogSong song) test, {
  bool fullAlbums = true,
}) {
  final catalog = SongCatalogScope.of(context);
  final library = LocalLibraryScope.of(context);
  final youTube = YouTubeLibraryScope.of(context);
  return [
    for (final song in catalog.songs)
      if ((fullAlbums || !song.isFullAlbum) && test(song))
        withPhoneYouTube(
          SearchHit.main(song, library.filesOf(song.id)),
          youTube,
        ),
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
}

/// "Odkryj coś nowego": up to six of music.db's genres (`songs.genre`), another draw each day.
List<String> discoverGenres(SongCatalog catalog, {DateTime? now}) {
  // A genre's list has no full albums (openGenreSongs), so their genres alone would show none.
  final genres = {
    for (final song in catalog.songs)
      if (!song.isFullAlbum) ...song.genres,
  }.toList()..sort();
  final today = now ?? DateTime.now();
  return (genres
        ..shuffle(Random(today.year * 1000 + today.month * 40 + today.day)))
      .take(6)
      .toList();
}

/// A genre's songs in a song list.
Future<void> openGenreSongs(BuildContext context, String genre) =>
    SongListScreen.open(
      context,
      title: genre,
      subtitle: 'Gatunek',
      songs: (context) => hitsWhere(
        context,
        (song) => song.genres.contains(genre),
        fullAlbums: false,
      ),
    );

/// "Inne kategorie": lists made from what the phone knows, not Spotify's categories.
List<Widget> _otherCategories(BuildContext context) {
  final moods = MoodLibraryScope.maybeOf(context);
  return [
    _CategoryTile(
      name: 'Ostatnio dodane',
      onTap: () => SongListScreen.open(
        context,
        title: 'Ostatnio dodane',
        subtitle: 'Najnowsze w bazie danych',
        songs: (context) {
          final library = LocalLibraryScope.of(context);
          final youTube = YouTubeLibraryScope.of(context);
          // MusicDatabase numbers songs as they're added.
          final newest = [...SongCatalogScope.of(context).songs]
            ..sort((a, b) => b.id.compareTo(a.id));
          return [
            for (final song in newest.take(_newestCount))
              withPhoneYouTube(
                SearchHit.main(song, library.filesOf(song.id)),
                youTube,
              ),
          ];
        },
      ),
    ),
    if (SongCatalogScope.of(context).songs.any((s) => s.isFullAlbum))
      _CategoryTile(
        name: 'Całe albumy',
        onTap: () => SongListScreen.open(
          context,
          title: 'Całe albumy',
          subtitle: 'Albumy w jednym nagraniu',
          songs: (context) => hitsWhere(context, (song) => song.isFullAlbum),
        ),
      ),
    _CategoryTile(
      name: 'Najczęściej słuchane',
      onTap: () => _openMostPlayed(context),
    ),
    if (moods != null)
      _CategoryTile(
        name: 'Bez nastroju',
        onTap: () => SongListScreen.open(
          context,
          title: 'Bez nastroju',
          subtitle: 'Utwory, które nie są w żadnym nastroju',
          songs: (context) =>
              hitsWhere(context, (song) => moods.moodKeysOf(song.id).isEmpty),
        ),
      ),
    _CategoryTile(
      name: 'Bez linku YouTube',
      onTap: () => SongListScreen.open(
        context,
        title: 'Bez linku YouTube',
        subtitle: 'Baza danych nie zna jeszcze filmu',
        songs: (context) =>
            hitsWhere(context, (song) => song.youTube == YouTubeLink.unknown),
      ),
    ),
    _CategoryTile(
      name: 'Tylko na telefonie',
      onTap: () => SongListScreen.open(
        context,
        title: 'Tylko na telefonie',
        subtitle: 'Pliki spoza bazy danych',
        songs: (context) =>
            [
              for (final song in LocalLibraryScope.of(context).songs)
                if (song.pending) SearchHit.phoneOnly(song),
            ]..sort(
              (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
            ),
      ),
    ),
  ];
}

const _newestCount = 100;

/// The songs played most over everything (the listening stats), most first.
Future<void> _openMostPlayed(BuildContext context) async {
  final log = ListeningLogScope.maybeOf(context);
  final user = AccountScope.maybeOf(context)?.userName;
  final catalog = SongCatalogScope.of(context);
  final listens = await log?.listens(account: user) ?? const <Listen>[];
  if (!context.mounted) return;
  final top = [
    for (final song in ListeningStats.of(listens, song: catalog.current).songs)
      if (song.plays > 0) song,
  ].take(_newestCount).toList();
  await SongListScreen.open(
    context,
    title: 'Najczęściej słuchane',
    subtitle: 'Ze statystyk słuchania',
    songs: (context) => [for (final song in top) hitOfStatsSong(context, song)],
  );
}

class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard({required this.tag, required this.onTap});

  final String tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: context.palette.radius(8),
            child: SizedBox(
              width: 140,
              height: 220,
              child: FittedBox(
                fit: BoxFit.cover,
                child: CoverArt(
                  seed: tag,
                  size: 220,
                  icon: Icons.play_circle_outline,
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 12,
            child: Text(
              tag,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppFontSize.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.name, this.count, required this.onTap});

  final String name;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.colorForSeed(name),
      shape: palette.boxShape(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: -14,
              bottom: -8,
              child: Transform.rotate(
                angle: 0.4,
                child: const Icon(Icons.album, size: 70, color: Colors.black26),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppFontSize.listTitle,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (count != null)
                    Text(
                      '$count utw.',
                      style: const TextStyle(fontSize: AppFontSize.small),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
