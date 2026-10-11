import 'package:flutter/material.dart';

import '../data/play_history.dart';
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
        title: const Text('Historia odtwarzania'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Przechowuj historię'),
            subtitle: Text(keepDaysLabel(history.keepDays)),
            onTap: () => _pickKeepDays(context, history),
          ),
          ListTile(
            enabled: history.entries.isNotEmpty,
            leading: const Icon(Icons.delete_outline),
            title: const Text('Wyczyść historię'),
            onTap: () => confirmClearHistory(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Historia to lista „Ostatnie” w menu profilu. Starsze odtworzenia są '
              'usuwane same.',
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
        title: const Text('Przechowuj historię'),
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
  0 => 'Bez limitu',
  365 => 'Rok',
  _ => '$days dni',
};

/// Asks, then empties "Ostatnie".
Future<void> confirmClearHistory(BuildContext context) async {
  final history = PlayHistoryScope.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Wyczyścić historię?'),
      content: const Text(
        'Lista „Ostatnie” zostanie opróżniona. Playlisty, kolejka i pamięć podręczna '
        'zostają.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Wyczyść'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) await history.clear();
}
