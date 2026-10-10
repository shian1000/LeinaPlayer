import 'package:flutter/material.dart';

import '../dummy.dart';
import '../theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/menu_sheet.dart';

const _id = 'Playlista';
const _trackCount = 12;

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key, required this.title, required this.owner});

  final String title;
  final String owner;

  void _showPlaylistMenu(BuildContext context) {
    showMenuSheet(
      context,
      idPrefix: '$_id › Menu (⋮)',
      header: MenuSheetHeader(
        cover: CoverArt(seed: title, size: 56),
        title: title,
        subtitle: 'Playlista • $owner',
      ),
      entries: const [
        MenuSheetEntry(Icons.share_outlined, 'Udostępnij'),
        MenuSheetEntry(Icons.check_circle, 'Usuń z Biblioteki'),
        MenuSheetEntry(
          Icons.download_for_offline_outlined,
          'Pobierz',
          premium: true,
        ),
        MenuSheetEntry(Icons.add, 'Dodaj do tej playlisty'),
        MenuSheetEntry(Icons.edit_outlined, 'Edytuj playlistę'),
        MenuSheetEntry(Icons.playlist_add, 'Dodaj do innej playlisty'),
        MenuSheetEntry(Icons.groups_outlined, 'Rozpocznij Jam', premium: true),
        MenuSheetEntry(Icons.flag_outlined, 'Zgłoś'),
        MenuSheetEntry(Icons.drive_file_move_outline, 'Przenieś do folderu'),
        MenuSheetEntry(Icons.person_remove_outlined, 'Usuń z profilu'),
        MenuSheetEntry(Icons.logout, 'Opuść playlistę'),
        MenuSheetEntry(
          Icons.block,
          'Nie uwzględniaj playlisty w profilu gustu',
        ),
        MenuSheetEntry(Icons.qr_code, 'Pokaż kod playlisty'),
      ],
    );
  }

  void _showTrackMenu(BuildContext context, int index) {
    showMenuSheet(
      context,
      idPrefix: '$_id › Utwór › Menu (⋮)',
      header: MenuSheetHeader(
        cover: CoverArt(seed: '$title$index', size: 56),
        title: 'Utwór ${index + 1}',
        subtitle: 'Wykonawca • Dodał(a/o) $owner',
      ),
      entries: const [
        MenuSheetEntry(Icons.share_outlined, 'Udostępnij'),
        MenuSheetEntry(
          Icons.add_circle_outline,
          'Dodaj do Polubionych utworów',
        ),
        MenuSheetEntry(Icons.playlist_add, 'Dodaj do playlisty'),
        MenuSheetEntry(Icons.remove_circle_outline, 'Usuń z tej playlisty'),
        MenuSheetEntry(Icons.queue_music, 'Dodaj do kolejki'),
        MenuSheetEntry(Icons.format_list_numbered, 'Przejdź do kolejki'),
        MenuSheetEntry(Icons.album_outlined, 'Przejdź do albumu'),
        MenuSheetEntry(Icons.person_outline, 'Przejdź do wykonawców'),
        MenuSheetEntry(Icons.groups_outlined, 'Rozpocznij Jam', premium: true),
        MenuSheetEntry(Icons.block, 'Nie uwzględniaj utworu w profilu gustu'),
        MenuSheetEntry(Icons.radio, 'Przejdź do radia utworu'),
        MenuSheetEntry(Icons.people_alt_outlined, 'Pokaż autorów utworu'),
        MenuSheetEntry(Icons.qr_code, 'Pokaż kod utworu'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    void dummy(String label) => showDummy(context, '$_id › $label');
    final palette = context.palette;
    final tint = palette.colorForSeed(title);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Wstecz',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Menu playlisty (⋮)',
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showPlaylistMenu(context),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tint, palette.background],
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + 56,
              16,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: CoverArt(seed: title, size: 220)),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppFontSize.largeTitle,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: palette.accent,
                      child: Text(
                        owner.characters.first,
                        style: TextStyle(
                          color: palette.onAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        owner,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.textPrimary,
                        backgroundColor: palette.chip,
                        side: palette.outlineSide,
                        shape: palette.pillShape,
                      ),
                      icon: const Icon(Icons.forum_outlined, size: 18),
                      label: const Text('Wiadomość'),
                      onPressed: () => dummy('Wiadomość'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.public, size: 18, color: palette.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      '$_trackCount utworów • 45 min',
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Dodano do Biblioteki',
                  icon: Icon(
                    Icons.check_circle,
                    color: palette.accent,
                    size: 30,
                  ),
                  onPressed: () => dummy('Dodano do Biblioteki (✓)'),
                ),
                IconButton(
                  tooltip: 'Pobierz',
                  icon: const Icon(
                    Icons.download_for_offline_outlined,
                    size: 30,
                  ),
                  onPressed: () => dummy('Pobierz (ikona)'),
                ),
                IconButton(
                  tooltip: 'Udostępnij',
                  icon: const Icon(Icons.share_outlined, size: 28),
                  onPressed: () => dummy('Udostępnij (ikona)'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Odtwarzanie losowe',
                  icon: Icon(Icons.shuffle, color: palette.accent, size: 30),
                  onPressed: () => dummy('Odtwarzanie losowe'),
                ),
                const SizedBox(width: 4),
                FloatingActionButton(
                  heroTag: null,
                  tooltip: 'Odtwórz playlistę',
                  backgroundColor: palette.accent,
                  foregroundColor: palette.onAccent,
                  shape: palette.rounded
                      ? const CircleBorder()
                      : const RoundedRectangleBorder(),
                  onPressed: () => dummy('Odtwórz playlistę'),
                  child: const Icon(Icons.play_arrow, size: 36),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                _ActionChip(
                  icon: Icons.add,
                  label: 'Dodaj',
                  onTap: () => dummy('Dodaj (do tej playlisty)'),
                ),
                _ActionChip(
                  icon: Icons.menu,
                  label: 'Edytuj',
                  onTap: () => dummy('Edytuj (playlistę)'),
                ),
                _ActionChip(
                  icon: Icons.swap_vert,
                  label: 'Sortuj',
                  onTap: () => dummy('Sortuj (playlistę)'),
                ),
              ],
            ),
          ),
          for (var i = 0; i < _trackCount; i++)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 16, right: 4),
              leading: CoverArt(seed: '$title$i', size: 52),
              title: Text('Utwór ${i + 1}'),
              subtitle: const Text('Wykonawca'),
              trailing: IconButton(
                tooltip: 'Menu utworu (⋮)',
                icon: Icon(Icons.more_vert, color: palette.textSecondary),
                onPressed: () => _showTrackMenu(context, i),
              ),
              onTap: () => dummy('Utwór (odtwórz) ${i + 1}'),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ActionChip(
      avatar: Icon(icon, size: 20, color: palette.accent),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: palette.chip,
      side: palette.outlineSide,
      shape: palette.pillShape,
      onPressed: onTap,
    );
  }
}
