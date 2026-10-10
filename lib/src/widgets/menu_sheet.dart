import 'package:flutter/material.dart';

import '../dummy.dart';
import '../theme.dart';

class MenuSheetEntry {
  const MenuSheetEntry(
    this.icon,
    this.label, {
    this.subtitle,
    this.premium = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool premium;

  /// When null the entry is a dummy reporting `<idPrefix> › <label>`.
  final VoidCallback? onTap;
}

/// Bottom-sheet menu used for all context menus (⋮), the "Utwórz" sheet and sort options.
Future<void> showMenuSheet(
  BuildContext context, {
  required String idPrefix,
  required List<MenuSheetEntry> entries,
  Widget? header,
  bool largeIcons = false,
}) {
  final palette = context.palette;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          if (header != null) ...[header, const Divider()],
          for (final entry in entries)
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
                  : Icon(entry.icon, color: palette.textSecondary, size: 26),
              title: Text(
                entry.label,
                style: TextStyle(
                  fontSize: AppFontSize.listTitle,
                  fontWeight: largeIcons ? FontWeight.bold : null,
                ),
              ),
              subtitle: entry.subtitle == null ? null : Text(entry.subtitle!),
              trailing: entry.premium ? const PremiumBadge() : null,
              onTap: () {
                Navigator.of(sheetContext).pop();
                (entry.onTap ??
                    () => showDummy(context, '$idPrefix › ${entry.label}'))();
              },
            ),
        ],
      ),
    ),
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
