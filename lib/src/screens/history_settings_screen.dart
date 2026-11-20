import 'package:flutter/material.dart';

import '../data/play_history.dart';
import '../l10n.dart';
import '../theme.dart';

/// "Ustawienia › Historia odtwarzania": how long "Ostatnie" keeps plays, and clearing it.
class HistorySettingsScreen extends StatelessWidget {
  const HistorySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final history = PlayHistoryScope.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.historySettingsScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(l10n.historySettingsScreenKeep),
            subtitle: Text(keepDaysLabel(history.keepDays)),
            onTap: () => _pickKeepDays(context, history),
          ),
          ListTile(
            enabled: history.entries.isNotEmpty,
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.historySettingsScreenClear),
            onTap: () => confirmClearHistory(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              l10n.historySettingsScreenNote,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: AppFontSize.small,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickKeepDays(BuildContext context, PlayHistory history) async {
    final days = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.historySettingsScreenKeep),
        children: [
          for (final choice in PlayHistory.keepDaysChoices)
            ListTile(
              title: Text(keepDaysLabel(choice)),
              trailing: choice == history.keepDays
                  ? Icon(Icons.check, color: context.palette.accent)
                  : null,
              onTap: () => Navigator.of(dialogContext).pop(choice),
            ),
        ],
      ),
    );
    if (days != null) await history.setKeepDays(days);
  }
}

/// "7 dni", "rok", "bez limitu".
String keepDaysLabel(int days) => switch (days) {
  0 => l10n.historySettingsScreenNoLimit,
  365 => l10n.historySettingsScreenYear,
  _ => l10n.historySettingsScreenDays(days),
};

/// Asks, then empties "Ostatnie".
Future<void> confirmClearHistory(BuildContext context) async {
  final history = PlayHistoryScope.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.historySettingsScreenClearTitle),
      content: Text(l10n.historySettingsScreenClearBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.historySettingsScreenClearButton),
        ),
      ],
    ),
  );
  if (confirmed ?? false) await history.clear();
}
