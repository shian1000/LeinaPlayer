import 'package:flutter/material.dart';

import '../data/error_log.dart';
import '../theme.dart';

/// "Informacje i pomoc › Dziennik błędów": what went wrong lately (newest first), kept only on
/// the phone ([ErrorLog]), with "Wyczyść".
class ErrorLogScreen extends StatelessWidget {
  const ErrorLogScreen({super.key, this.log});

  /// Tests pass their own; [ErrorLog.instance] otherwise.
  final ErrorLog? log;

  Future<void> _clear(BuildContext context, ErrorLog log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Wyczyścić dziennik błędów?'),
        content: const Text(
          'Wpisy znikną z telefonu. Nie da się ich potem dołączyć do raportu.',
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
    if (confirmed ?? false) await log.clear();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final log = this.log ?? ErrorLog.instance;
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final entries = log.entries.reversed.toList();
        return Scaffold(
          appBar: AppBar(
            backgroundColor: palette.surface,
            title: const Text('Dziennik błędów'),
            actions: [
              if (entries.isNotEmpty)
                IconButton(
                  tooltip: 'Wyczyść',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _clear(context, log),
                ),
            ],
          ),
          body: entries.isEmpty
              ? Center(
                  child: Text(
                    'Brak błędów z ostatnich ${ErrorLog.keepFor.inDays} dni',
                    style: TextStyle(color: palette.textSecondary),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final entry = entries[i];
                    final line = entry.line;
                    final time = line.substring(0, 19);
                    return ListTile(
                      dense: true,
                      title: SelectableText(
                        entry.message,
                        style: TextStyle(
                          fontSize: AppFontSize.small,
                          fontFamily: 'monospace',
                          color: palette.textPrimary,
                        ),
                      ),
                      subtitle: Text(time),
                    );
                  },
                ),
        );
      },
    );
  }
}
