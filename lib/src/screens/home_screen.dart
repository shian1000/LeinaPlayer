import 'package:flutter/material.dart';

import '../dummy.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_art.dart';
import 'app_shell.dart';

enum _CardStyle { square, artist, album }

class _Section {
  const _Section(this.title, this.style, this.itemName);

  final String title;
  final _CardStyle style;
  final String itemName;
}

const _sections = [
  _Section('Popularne radio', _CardStyle.square, 'Radio'),
  _Section('Weekend z muzyką', _CardStyle.square, 'Playlista'),
  _Section('Nowe wydania dla Ciebie', _CardStyle.album, 'Wydanie'),
  _Section('Popularni wykonawcy', _CardStyle.artist, 'Wykonawca'),
  _Section('Popularne albumy i single', _CardStyle.album, 'Album'),
  _Section('W otoczeniu jesiennych dźwięków', _CardStyle.square, 'Playlista'),
  _Section('Nowe nuty dla Ciebie', _CardStyle.square, 'Mix'),
  _Section('Odkrywaj swoje gatunki', _CardStyle.square, '#gatunek'),
];

const _filters = ['Wszystko', 'Muzyka', 'Podcasty'];
const _cardsPerSection = 6;
const _cardWidth = 144.0;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedFilter = 0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          TabHeader(
            onAvatarTap: () => AppShell.of(context).openDrawer(),
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
                        showDummy(context, 'Home › Filtr: ${_filters[i]}');
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _sections.length,
              itemBuilder: (context, i) => _SectionRow(section: _sections[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.section});

  final _Section section;

  @override
  Widget build(BuildContext context) {
    final height = switch (section.style) {
      _CardStyle.square => 205.0,
      _CardStyle.artist => 185.0,
      _CardStyle.album => 220.0,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(section.title),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _cardsPerSection,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => _Card(section: section, index: i),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.section, required this.index});

  final _Section section;
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
          showDummy(context, 'Home › ${section.title} › karta ${index + 1}'),
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
