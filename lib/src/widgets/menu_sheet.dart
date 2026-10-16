import 'package:flutter/material.dart';

import '../theme.dart';

class MenuSheetEntry {
  const MenuSheetEntry(
    this.icon,
    this.label, {
    this.subtitle,
    this.premium = false,
    this.onTap,
    this.submenu,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool premium;

  /// What tapping does; `null` only for an entry with a [submenu].
  final VoidCallback? onTap;

  /// Its own options, unfolded under it in the same sheet ("Dodaj do playlisty ›") instead of
  /// opening another sheet (Juxtopposed's Spotify redesign); built when unfolded.
  final List<MenuSheetEntry> Function()? submenu;
}

/// Bottom-sheet menu used for all context menus (⋮), the "Utwórz" sheet and sort options.
/// [quickEntries] — options used now and then, in a smaller block above the main ones (after
/// Juxtopposed's Spotify redesign), so the main ones stay at the bottom, near the thumb.
Future<void> showMenuSheet(
  BuildContext context, {
  required String idPrefix,
  required List<MenuSheetEntry> entries,
  List<MenuSheetEntry> quickEntries = const [],
  Widget? header,
  bool largeIcons = false,
}) {
  final palette = context.palette;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      String? open;
      return StatefulBuilder(
        builder: (sheetContext, setState) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              if (header != null) ...[header, const Divider()],
              if (quickEntries.isNotEmpty) ...[
                for (final entry in quickEntries)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Icon(
                      entry.icon,
                      color: palette.textSecondary,
                      size: 22,
                    ),
                    title: Text(entry.label),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      entry.onTap?.call();
                    },
                  ),
                const Divider(),
              ],
              for (final entry in entries) ...[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 0,
                  ),
                  leading: largeIcons
                      ? CircleAvatar(
                          radius: 24,
                          backgroundColor: palette.chip,
                          child: Icon(entry.icon, color: palette.textPrimary),
                        )
                      : Icon(
                          entry.icon,
                          color: palette.textSecondary,
                          size: 26,
                        ),
                  title: Text(
                    entry.label,
                    style: TextStyle(
                      fontSize: AppFontSize.listTitle,
                      fontWeight: largeIcons ? FontWeight.bold : null,
                    ),
                  ),
                  subtitle: entry.subtitle == null
                      ? null
                      : Text(entry.subtitle!),
                  trailing: entry.premium
                      ? const PremiumBadge()
                      : entry.submenu == null
                      ? null
                      : Icon(
                          open == entry.label
                              ? Icons.expand_less
                              : Icons.chevron_right,
                        ),
                  onTap: entry.submenu != null
                      ? () => setState(
                          () => open = open == entry.label ? null : entry.label,
                        )
                      : () {
                          Navigator.of(sheetContext).pop();
                          entry.onTap?.call();
                        },
                ),
                if (entry.submenu != null && open == entry.label)
                  for (final inner in entry.submenu!())
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(
                        left: 56,
                        right: 20,
                      ),
                      leading: Icon(inner.icon, color: palette.textSecondary),
                      title: Text(
                        inner.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: inner.subtitle == null
                          ? null
                          : Text(inner.subtitle!),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        inner.onTap?.call();
                      },
                    ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Header shown at the top of item context menus (cover + title + subtitle).
class MenuSheetHeader extends StatelessWidget {
  const MenuSheetHeader({
    super.key,
    required this.cover,
    required this.title,
    required this.subtitle,
  });

  final Widget cover;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: cover,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
    );
  }
}

class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: palette.chip,
        borderRadius: palette.radius(4),
        border: palette.outline == null
            ? null
            : Border.all(color: palette.outline!),
      ),
      child: const Text(
        'Premium',
        style: TextStyle(
          fontSize: AppFontSize.badge,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
