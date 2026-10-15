import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/local_library.dart';
import '../data/moods.dart';
import '../data/song_catalog.dart';
import '../data/youtube_library.dart';
import '../dummy.dart';
import '../sample_content.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import 'mood_screen.dart';
import 'search_fields_sheet.dart';
import 'song_list_screen.dart';
import 'song_search_screen.dart';

const _id = 'Wyszukaj';

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
          const SliverToBoxAdapter(child: SectionTitle('Odkryj coś nowego')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: searchDiscoverTags.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, i) =>
                    _DiscoverCard(tag: searchDiscoverTags[i]),
              ),
            ),
          ),
          ..._browseGroups(context),
          const SliverToBoxAdapter(child: SectionTitle('Inne kategorie')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
              ),
              itemCount: searchCategories.length,
              itemBuilder: (context, i) =>
                  _CategoryTile(name: searchCategories[i]),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Przeglądaj" grouped under headings instead of one mix of tiles (Juxtopposed's Spotify
/// redesign), from what music.db and the moods know: moods, decades, languages and the
/// artists' countries — the biggest first. MusicDatabase has no genres.
List<Widget> _browseGroups(BuildContext context) {
  final catalog = SongCatalogScope.of(context);
  final moodLibrary = MoodLibraryScope.maybeOf(context);
  final moods = [...?moodLibrary?.globalMoods, ...?moodLibrary?.userMoods];
  final decades = <int, int>{};
  final languages = <String, int>{};
  final countries = <String, int>{};
  for (final song in catalog.songs) {
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

  List<SearchHit> hitsWhere(
    BuildContext context,
    bool Function(CatalogSong song) test,
  ) {
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    return [
      for (final song in catalog.songs)
        if (test(song))
          withPhoneYouTube(
            SearchHit.main(song, library.filesOf(song.id)),
            youTube,
          ),
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

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
    if (decades.isNotEmpty)
      group('Dekady', [
        for (final decade in decades.keys.toList()..sort((a, b) => b - a))
          _CategoryTile(
            name: decade < 2000
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
              songs: (context) =>
                  hitsWhere(context, (song) => song.language == language),
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
              ),
            ),
          ),
      ]),
  ];
}

class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showDummy(context, '$_id › Odkryj coś nowego › $tag'),
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
  const _CategoryTile({required this.name, this.count, this.onTap});

  final String name;
  final int? count;

  /// `null`: a dummy (a sample category).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.colorForSeed(name),
      shape: palette.boxShape(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => showDummy(context, '$_id › Kategoria: $name'),
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
