import 'package:flutter/material.dart';

import '../data/error_log.dart';
import '../theme.dart';
import 'error_log_screen.dart';
import 'problem_report_screen.dart';
import '../l10n.dart';

/// "Synchronizacja › Raportowanie błędów › Telefon › Problemy": the error log kept on the phone
/// and "Zgłoś problem", which hands a report to the share sheet.
class ProblemsScreen extends StatelessWidget {
  const ProblemsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.palette.surface,
        title: Text(l10n.problemsScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(l10n.problemsScreenReport),
            subtitle: Text(l10n.problemsScreenReportHelp),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProblemReportScreen(),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: ErrorLog.instance,
            builder: (context, _) => ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(l10n.problemsScreenErrorLog),
              subtitle: Text(
                ErrorLog.instance.entries.isEmpty
                    ? l10n.problemsScreenEmpty
                    : l10n.problemsScreenEntries(
                        ErrorLog.instance.entries.length,
                        ErrorLog.keepFor.inDays,
                      ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ErrorLogScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
