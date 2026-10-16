import 'package:flutter/material.dart';

import '../data/account.dart';
import '../data/later_links.dart';
import '../data/moods.dart';
import '../data/playlist_library.dart';
import '../dummy.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart';
import 'later_links_screen.dart';
import 'recents_screen.dart';
import 'settings_screen.dart';

const _id = 'Ja';

/// The "Ja" tab: the profile, the MusicDatabase account, then history, "Na później"
/// and settings — what used to hide behind the avatar in the top corner, now down by the thumb
/// (Juxtopposed's Spotify redesign).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final account = AccountScope.maybeOf(context);
    final loggedIn = account?.loggedIn ?? false;
    final playlists = PlaylistLibraryScope.maybeOf(context)?.playlists.length;
    final moods = MoodLibraryScope.maybeOf(context)?.userMoods.length;
    final later = LaterLinksScope.maybeOf(context);
    final laterCount = later?.links.length ?? 0;
    final unopened = later?.unopenedCount ?? 0;
    void dummy(String label) => showDummy(context, '$_id › $label');
    void push(Widget screen) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen));

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _Card(
            color: palette.surfaceHigh,
            onTap: () => push(const AccountScreen()),
            child: Row(
              children: [
                const ProfileAvatar(radius: 34),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loggedIn ? account!.userName! : 'Nie zalogowano',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppFontSize.section,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        loggedIn
                            ? [
                                if (playlists != null)
                                  _count(
                                    playlists,
                                    'playlista',
                                    'playlisty',
                                    'playlist',
                                  ),
                                if (moods != null)
                                  _count(
                                    moods,
                                    'własny nastrój',
                                    'własne nastroje',
                                    'własnych nastrojów',
                                  ),
                              ].join(' • ')
                            : 'Zaloguj się do MusicDatabase',
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edytuj profil',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => dummy('Edytuj profil'),
                ),
                IconButton(
                  tooltip: 'Udostępnij profil',
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => dummy('Udostępnij profil'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            color: palette.accent.withValues(alpha: 0.18),
            onTap: () => push(const AccountScreen()),
            child: Row(
              children: [
                Icon(Icons.dns_outlined, color: palette.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Konto MusicDatabase'),
                      Text(
                        loggedIn
                            ? 'Playlisty i nastroje synchronizują się z serwerem'
                            : 'Tylko na tym telefonie',
                        style: TextStyle(
                          color: palette.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _Row(
            icon: Icons.history,
            label: 'Ostatnie',
            onTap: () => push(const RecentsScreen()),
          ),
          _Row(
            icon: Icons.bookmark_border,
            label: 'Na później',
            subtitle: laterCount == 0
                ? 'Linki od znajomych zapisane z „Otwórz w…”'
                : unopened == 0
                ? 'Wszystko odsłuchane ($laterCount)'
                : 'Do odsłuchania: $unopened z $laterCount',
            onTap: () => push(const LaterLinksScreen()),
          ),
          _Row(
            icon: Icons.show_chart,
            label: 'Statystyki słuchania',
            onTap: () => dummy('Statystyki słuchania'),
          ),
          _Row(
            icon: Icons.settings_outlined,
            label: 'Ustawienia',
            onTap: () => push(const SettingsScreen()),
          ),
        ],
      ),
    );
  }

  static String _count(int n, String one, String few, String many) {
    if (n == 1) return '1 $one';
    final tens = n % 100 ~/ 10;
    final last = n % 10;
    return '$n ${tens != 1 && last >= 2 && last <= 4 ? few : many}';
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.color, required this.child, this.onTap});

  final Color color;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: context.palette.boxShape(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    leading: Icon(icon, size: 26),
    title: Text(label),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
