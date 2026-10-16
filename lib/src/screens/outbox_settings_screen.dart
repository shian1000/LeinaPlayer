import 'package:flutter/material.dart';

import '../data/database_sync.dart';
import '../data/outbox.dart';
import '../theme.dart';
import 'outbox_contents_screen.dart';

/// "Ustawienia › Zgłoszenia poprawek": the requests for MusicDatabase waiting in the phone's
/// outbox (e.g. links YouTube no longer plays) and sending them.
class OutboxSettingsScreen extends StatelessWidget {
  const OutboxSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final outbox = OutboxScope.of(context);
    final sync = DatabaseSyncScope.of(context);
    final palette = context.palette;
    final result = outbox.lastSend;
    final canSend = !outbox.sending && outbox.waiting > 0 && sync.hasSource;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Zgłoszenia poprawek'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.forward_to_inbox_outlined),
            title: const Text('Wysyłaj zgłoszenia poprawek automatycznie'),
            subtitle: Text(
              outbox.autoSend
                  ? 'Gdy serwer MusicDatabase jest osiągalny'
                  : 'Zgłoszenia czekają na telefonie na „Wyślij teraz”',
            ),
            value: outbox.autoSend,
            onChanged: outbox.setAutoSend,
          ),
          ListTile(
            leading: const Icon(Icons.outbox_outlined),
            title: const Text('Czeka na wysłanie'),
            subtitle: Text(
              outbox.sending
                  ? 'Wysyłanie…'
                  : switch (outbox.waiting) {
                      0 => 'Nic',
                      1 => '1 zgłoszenie',
                      final n
                          when n % 10 >= 2 &&
                              n % 10 <= 4 &&
                              (n % 100 < 12 || n % 100 > 14) =>
                        '$n zgłoszenia',
                      final n => '$n zgłoszeń',
                    },
            ),
            trailing: outbox.sending
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : outbox.waiting > 0
                ? const Icon(Icons.chevron_right)
                : null,
            onTap: outbox.waiting > 0
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const OutboxContentsScreen(),
                    ),
                  )
                : null,
          ),
          if (result != null && !outbox.sending)
            ListTile(
              leading: Icon(
                result.problem == null ? Icons.check : Icons.error_outline,
                color: result.problem == null
                    ? palette.accent
                    : Theme.of(context).colorScheme.error,
              ),
              title: const Text('Ostatnie wysyłanie'),
              subtitle: Text(
                [
                  'Wysłano: ${result.sent}',
                  if (result.refused > 0)
                    'odrzucone przez serwer: ${result.refused}',
                  ?result.problem,
                  if (outbox.heldForToday && outbox.autoSend)
                    'kolejna próba jutro albo przez „Wyślij teraz”',
                ].join(' · '),
              ),
            ),
          ListTile(
            enabled: canSend,
            leading: Icon(
              Icons.send,
              color: canSend ? palette.accent : palette.textSecondary,
            ),
            title: Text(
              'Wyślij teraz',
              style: TextStyle(
                color: canSend ? palette.accent : palette.textSecondary,
              ),
            ),
            onTap: () async =>
                outbox.send(await sync.serverAddresses(), manual: true),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'Telefon zgłasza MusicDatabase m.in. linki z bazy, których YouTube już nie '
              'odtwarza, razem z filmem znalezionym w zamian. Wysyłanie automatyczne próbuje przy '
              'uruchomieniu i powrocie do aplikacji, pod te same adresy co pobieranie bazy. Gdy '
              'serwer odmówi (pełna skrzynka odbiorcza, odłączony dysk), zgłoszenia czekają do '
              'następnego dnia. W MusicDatabase przegląda się je w Manage database › Resolve new '
              'requests.',
              style: TextStyle(
                fontSize: AppFontSize.listSubtitle,
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
