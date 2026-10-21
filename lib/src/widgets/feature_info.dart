import 'package:flutter/material.dart';

import '../theme.dart';

/// A button at the bottom of a [FeatureInfo] sheet; [onTap] runs after the sheet closes, with
/// the context the sheet was opened from.
class FeatureInfoAction {
  const FeatureInfoAction(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final void Function(BuildContext context) onTap;
}

/// What a long press on some elements explains (user's list, sharing checklist 5.2): what it
/// is, what it's for, how it works, which libraries and which services it uses. Texts live in
/// `feature_infos.dart`.
class FeatureInfo {
  const FeatureInfo({
    required this.title,
    required this.what,
    this.why,
    this.how,
    this.libraries,
    this.connects,
    this.note,
    this.actions = const [],
  });

  final String title;
  final String what;
  final String? why;
  final String? how;
  final String? libraries;
  final String? connects;

  /// Shown above everything else, e.g. that a feature hasn't been tried in practice yet.
  final String? note;

  final List<FeatureInfoAction> actions;
}

/// Opens [info] as a sheet from the bottom.
Future<void> showFeatureInfo(BuildContext context, FeatureInfo info) {
  final palette = context.palette;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      Widget section(String title, String? body) {
        if (body == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: AppFontSize.small,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(
                  fontSize: AppFontSize.body,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        );
      }

      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(top: 20, bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: palette.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      info.title,
                      style: TextStyle(
                        fontSize: AppFontSize.emphasis,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (info.note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Text(
                  info.note!,
                  style: TextStyle(
                    fontSize: AppFontSize.small,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
              ),
            section('Co to jest', info.what),
            section('Do czego służy', info.why),
            section('Jak działa', info.how),
            section('Z czego korzysta', info.libraries),
            section('Z czym się łączy', info.connects),
            if (info.actions.isNotEmpty) const Divider(),
            for (final action in info.actions)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: Icon(action.icon, color: palette.accent),
                title: Text(action.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  action.onTap(context);
                },
              ),
          ],
        ),
      );
    },
  );
}
