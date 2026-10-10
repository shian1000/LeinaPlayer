import 'package:flutter/material.dart';

import '../dummy.dart';
import '../sample_content.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import 'app_shell.dart';
import 'search_fields_sheet.dart';
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
              onAvatarTap: () => AppShell.of(context).openDrawer(),
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
          const SliverToBoxAdapter(child: SectionTitle('Przeglądaj wszystko')),
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
  const _CategoryTile({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.colorForSeed(name),
      shape: palette.boxShape(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDummy(context, '$_id › Kategoria: $name'),
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
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppFontSize.listTitle,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
