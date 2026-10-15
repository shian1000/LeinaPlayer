import 'package:flutter/material.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/home_layout.dart';
import '../data/local_library.dart';
import '../data/moods.dart';
import '../data/play_history.dart';
import '../data/playlist_library.dart';
import '../data/saved_songs.dart';
import '../data/song_catalog.dart';
import '../data/track_ref.dart';
import '../data/youtube_library.dart';
import '../dummy.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/collection_cover.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/mood_sheet.dart';
import '../widgets/song_cover.dart';
import '../widgets/song_names.dart';
import '../widgets/song_tile.dart';
import 'mood_screen.dart';
import 'playlist_screen.dart';

const _id = 'Home';

enum _CardStyle { square, artist, album }

/// A sample row (placeholder content, "recommendations").
class _Sample {
  const _Sample(this.title, this.style, this.itemName);

  final String title;
  final _CardStyle style;
  final String itemName;

  String get id => 'sample:$title';
}

const _samples = [
  _Sample('Popularne radio', _CardStyle.square, 'Radio'),
  _Sample('Weekend z muzyką', _CardStyle.square, 'Playlista'),
  _Sample('Nowe wydania dla Ciebie', _CardStyle.album, 'Wydanie'),
  _Sample('Popularni wykonawcy', _CardStyle.artist, 'Wykonawca'),
  _Sample('Popularne albumy i single', _CardStyle.album, 'Album'),
  _Sample('W otoczeniu jesiennych dźwięków', _CardStyle.square, 'Playlista'),
  _Sample('Nowe nuty dla Ciebie', _CardStyle.square, 'Mix'),
  _Sample('Odkrywaj swoje gatunki', _CardStyle.square, '#gatunek'),
];

/// Home's rows made from what's on the phone.
const _librarySections = {
  'lib:recent': 'Ostatnio odtwarzane',
  'lib:playlists': 'Twoje playlisty',
  'lib:moods': 'Twoje nastroje',
  'lib:saved': 'Na później',
};

const _filters = ['Wszystko', 'Muzyka', 'Podcasty'];
const _cardsPerSection = 6;
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
    for (final sample in _samples) sample.id,
  ];

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedFilter = 0;

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
        final sections = [
          for (final id in layout.visible) ?_HomeSection.of(context, id),
        ];
        return SafeArea(
          child: Column(
            children: [
              TabHeader(
                content: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < _filters.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        PillChip(
                          label: _filters[i],
                          selected: i == _selectedFilter,
                          onTap: () {
                            setState(() => _selectedFilter = i);
                            showDummy(context, '$_id › Filtr: ${_filters[i]}');
                          },
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
                        itemBuilder: (context, i) =>
                            _SectionRow(section: sections[i], layout: layout),
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

  /// `null` when the section's playlist / mood is gone, or a library row has nothing to show.
  static _HomeSection? of(BuildContext context, String id) {
    final sample = _samples.where((s) => s.id == id).firstOrNull;
    if (sample != null) {
      return _HomeSection(
        id,
        sample.title,
        switch (sample.style) {
          _CardStyle.square => 205,
          _CardStyle.artist => 185,
          _CardStyle.album => 220,
        },
        (_) => [
          for (var i = 0; i < _cardsPerSection; i++)
            _SampleCard(section: sample, index: i),
        ],
      );
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
        final hits = [
          for (final played in history.entries)
            if (seen.add(played.track.key))
              resolveTrack(played.track, catalog, library, youTube),
        ].take(_rowLimit).toList();
        return _HomeSection(
          id,
          _librarySections[id]!,
          songHeight,
          (_) => _songCards(hits),
        );
      case 'lib:saved':
        final saved = SavedSongsScope.maybeOf(context);
        if (saved == null || saved.songs.isEmpty) return null;
        if (catalog == null || library == null || youTube == null) return null;
        final hits = [
          for (final ref in saved.songs.take(_rowLimit))
            resolveTrack(ref, catalog, library, youTube),
        ];
        return _HomeSection(
          id,
          _librarySections[id]!,
          songHeight,
          (_) => _songCards(hits),
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

  /// Its title in "Dostosuj stronę główną", also when it shows nothing now.
  static String titleFor(BuildContext context, String id) {
    final sample = _samples.where((s) => s.id == id).firstOrNull;
    if (sample != null) return sample.title;
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

List<Widget> _songCards(
  List<SearchHit> hits, {
  String? playlistName,
  String? moodKey,
  int? playlistId,
  String? youTubeListId,
}) => [
  for (final (i, hit) in hits.indexed)
    _SongCard(
      hit: hit,
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
  const _SectionRow({required this.section, required this.layout});

  final _HomeSection section;
  final HomeLayout layout;

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
            itemBuilder: (context, i) => cards[i],
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
  const _SongCard({required this.hit, required this.onTap});

  final SearchHit hit;
  final void Function(BuildContext context) onTap;

  @override
  Widget build(BuildContext context) => _Card(
    cover: SongCover(cover: CoverRequest.of(hit), size: _cardWidth),
    title: hit.shownTitle(context),
    subtitle: hit.shownArtist(context),
    onTap: () => onTap(context),
  );
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
  });

  final Widget cover;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      width: _cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cover,
          const SizedBox(height: 8),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

class _SampleCard extends StatelessWidget {
  const _SampleCard({required this.section, required this.index});

  final _Sample section;
  final int index;

  @override
  Widget build(BuildContext context) {
    final title = '${section.itemName} ${index + 1}';
    final secondary = TextStyle(
      color: context.palette.textSecondary,
      fontSize: AppFontSize.small,
    );
    final details = switch (section.style) {
      _CardStyle.square => [
        Text(
          'Wykonawca A, Wykonawca B, Wykonawca C i inni',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: secondary,
        ),
      ],
      _CardStyle.artist => [
        Text(
          title,
          maxLines: 1,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ],
      _CardStyle.album => [
        Text(index.isEven ? 'Album' : 'Singiel', style: secondary),
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text('Wykonawca', maxLines: 1, style: secondary),
      ],
    };
    return InkWell(
      onTap: () =>
          showDummy(context, '$_id › ${section.title} › karta ${index + 1}'),
      child: SizedBox(
        width: _cardWidth,
        child: Column(
          crossAxisAlignment: section.style == _CardStyle.artist
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CoverArt(
                  seed: '${section.title}$index',
                  size: _cardWidth,
                  circle: section.style == _CardStyle.artist,
                  icon: section.style == _CardStyle.artist
                      ? Icons.person
                      : Icons.music_note,
                ),
                if (section.style == _CardStyle.square)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    right: 8,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppFontSize.listTitle,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ...details,
          ],
        ),
      ),
    );
  }
}

/// "Dostosuj stronę główną": every section with a switch (shown or hidden) and a pin, dragged
/// into order; "Rekomendacje" turns Home's sample rows on and off; rows can be added from
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
                      'Sekcje proponowane przez aplikację (na razie przykładowe)',
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
                  final sample = id.startsWith('sample:');
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
                          color: sample && !layout.recommendations
                              ? palette.textSecondary
                              : null,
                        ),
                      ),
                      subtitle: sample
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
