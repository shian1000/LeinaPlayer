import 'package:flutter/material.dart';

import '../dummy.dart';
import '../sample_content.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _id = 'Menu profilu';

/// Side menu opened from the avatar in the top-left corner of every tab.
class ProfileDrawer extends StatelessWidget {
  const ProfileDrawer({
    super.key,
    required this.onOpenSettings,
    required this.onOpenRecents,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenRecents;

  @override
  Widget build(BuildContext context) {
    void dummy(String label) {
      // The drawer sits above the snackbar layer, so close it or the message stays hidden.
      Scaffold.of(context).closeDrawer();
      showDummy(context, '$_id › $label');
    }

    final palette = context.palette;
    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.9,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Material(
                color: palette.surfaceHigh,
                shape: palette.boxShape(10),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      leading: const ProfileAvatar(radius: 22),
                      title: const Text(
                        userName,
                        style: TextStyle(
                          fontSize: AppFontSize.emphasis,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text('Pokaż profil'),
                      onTap: () => dummy('Pokaż profil'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: palette.chip,
                        child: Icon(Icons.add, color: palette.textSecondary),
                      ),
                      title: const Text('Dodaj konto'),
                      subtitle: const Text(
                        'Dodaj konto dziecka lub innej osoby',
                      ),
                      onTap: () => dummy('Dodaj konto'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _DrawerItem(
              icon: Icons.show_chart,
              label: 'Statystyki słuchania',
              badge: 'Nowość',
              onTap: () => dummy('Statystyki słuchania'),
            ),
            _DrawerItem(
              icon: Icons.history,
              label: 'Ostatnie',
              onTap: onOpenRecents,
            ),
            _DrawerItem(
              icon: Icons.campaign_outlined,
              label: 'Aktualności',
              onTap: () => dummy('Aktualności'),
            ),
            _DrawerItem(
              icon: Icons.settings_outlined,
              label: 'Ustawienia',
              onTap: onOpenSettings,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _CircleAction(
                    label: 'Aktywność',
                    sublabel: 'Włącz',
                    child: const ProfileAvatar(radius: 27),
                    onTap: () => dummy('Aktywność'),
                  ),
                  const SizedBox(width: 12),
                  _CircleAction(
                    label: 'Zaproś\nznajomych',
                    child: CircleAvatar(
                      radius: 27,
                      backgroundColor: palette.chip,
                      child: Icon(
                        Icons.add,
                        size: 26,
                        color: palette.textPrimary,
                      ),
                    ),
                    onTap: () => dummy('Zaproś znajomych'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => dummy('Wiadomości'),
                    child: const Row(
                      children: [
                        Text(
                          'Wiadomości',
                          style: TextStyle(
                            fontSize: AppFontSize.section,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 30),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Nowa wiadomość (ikona)',
                    icon: Icon(Icons.edit_square, color: palette.textSecondary),
                    onPressed: () => dummy('Nowa wiadomość (ikona)'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Dziel się ze znajomymi tym, co kochasz.',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: AppFontSize.body,
                ),
              ),
            ),
            ListTile(
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: palette.chip,
                child: Icon(Icons.edit_square, color: palette.textSecondary),
              ),
              title: const Text('Nowa wiadomość'),
              onTap: () => dummy('Nowa wiadomość (przycisk)'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: Icon(icon, size: 28),
      title: Text(label),
      subtitle: badge == null
          ? null
          : Text(badge!, style: TextStyle(color: context.palette.badge)),
      onTap: onTap,
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.label,
    required this.child,
    required this.onTap,
    this.sublabel,
  });

  final String label;
  final String? sublabel;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: context.palette.radius(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            child,
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center),
            if (sublabel != null)
              Text(
                sublabel!,
                style: TextStyle(color: context.palette.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
