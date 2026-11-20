import 'package:flutter/material.dart';

import '../data/error_log.dart';
import '../theme.dart';
import 'error_log_screen.dart';
import 'problem_report_screen.dart';

/// "Synchronizacja › Raportowanie błędów › Telefon › Problemy": the error log kept on the phone
/// and "Zgłoś problem", which hands a report to the share sheet.
class ProblemsScreen extends StatelessWidget {
  const ProblemsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.palette.surface,
        title: const Text('Problemy'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Zgłoś problem'),
            subtitle: const Text(
              'Raport z wersją, telefonem i ostatnimi błędami — wysyłasz go sam',
            ),
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
              title: const Text('Dziennik błędów'),
              subtitle: Text(
                ErrorLog.instance.entries.isEmpty
                    ? 'Pusty'
                    : 'Wpisów: ${ErrorLog.instance.entries.length} '
                          '(ostatnie ${ErrorLog.keepFor.inDays} dni, tylko na telefonie)',
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
