import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/account.dart';
import '../data/database_sync.dart';
import '../data/outbox.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'outbox_contents_screen.dart';

/// "Ustawienia › Zgłoszenia poprawek": the requests for MusicDatabase waiting in the phone's
/// outbox (e.g. links YouTube no longer plays) and sending them — to the server, or as a package
/// through the share sheet (ADR 0014).
class OutboxSettingsScreen extends StatelessWidget {
  const OutboxSettingsScreen({super.key});

  static String requestsLabel(int n) =>
      '$n ${pluralWord(n, 'zgłoszenie', 'zgłoszenia', 'zgłoszeń')}';

  /// Asks for the name packages are signed with; `false` when the user cancelled.
  static Future<bool> _askForSender(BuildContext context, Outbox outbox) async {
    final typed = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: 'Podpis paczek ze zgłoszeniami',
        hint: 'Imię lub pseudonim (puste — bez podpisu)',
        initial: outbox.typedSender ?? '',
      ),
    );
    if (typed == null) return false;
    await outbox.setTypedSender(typed);
    return true;
  }

  static Future<void> _sendPackage(BuildContext context, Outbox outbox) async {
    final messenger = ScaffoldMessenger.of(context);
    if (outbox.asksForSender && !await _askForSender(context, outbox)) return;
    final package = await outbox.exportPackage();
    if (package == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nie ma zgłoszeń do wysłania')),
      );
      return;
    }
    final result = await _share(package);
    if (result.status == ShareResultStatus.dismissed) {
      await outbox.undoExport(package);
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          [
            'Wyeksportowano ${requestsLabel(package.names.length)}',
            if (package.leftOut > 0)
              '${requestsLabel(package.leftOut)} nie zmieściło się — w następnej paczce',
            if (package.refused > 0)
              'za duże dla MusicDatabase: ${package.refused}',
          ].join(' · '),
        ),
      ),
    );
  }

  static Future<void> _sendAgain(BuildContext context, Outbox outbox) async {
    final messenger = ScaffoldMessenger.of(context);
    final package = await outbox.rebuildLastPackage();
    if (package == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Ostatniej paczki nie ma już na telefonie'),
        ),
      );
      return;
    }
    await _share(package);
  }

  static Future<ShareResult> _share(RequestPackage package) =>
      SharePlus.instance.share(
        ShareParams(
          files: [XFile(package.file.path, mimeType: 'application/zip')],
          subject: 'Zgłoszenia dla MusicDatabase',
        ),
      );

  @override
  Widget build(BuildContext context) {
    final outbox = OutboxScope.of(context);
    final sync = DatabaseSyncScope.of(context);
    final account = AccountScope.maybeOf(context)?.userName;
    final canExport = !outbox.sending && outbox.waiting > 0;
    final palette = context.palette;
    final result = outbox.lastSend;
    final canSend = !outbox.sending && outbox.waiting > 0 && sync.hasServer;
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
                  : outbox.waiting == 0
                  ? 'Nic'
                  : requestsLabel(outbox.waiting),
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
          ListTile(
            enabled: canExport,
            leading: Icon(
              Icons.archive_outlined,
              color: canExport ? palette.accent : palette.textSecondary,
            ),
            title: Text(
              'Wyślij paczkę…',
              style: TextStyle(
                color: canExport ? palette.accent : palette.textSecondary,
              ),
            ),
            subtitle: Text(
              outbox.waiting == 0
                  ? 'Plik .zip przez komunikator, e-mail…'
                  : '${requestsLabel(outbox.waiting)} jako plik .zip przez '
                        'komunikator, e-mail…',
            ),
            onTap: () => _sendPackage(context, outbox),
          ),
          if (outbox.lastPackage.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.replay),
              title: const Text('Wyeksportuj ponownie ostatnią paczkę'),
              subtitle: Text(requestsLabel(outbox.lastPackage.length)),
              onTap: () => _sendAgain(context, outbox),
            ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Podpis paczek'),
            subtitle: Text(switch (outbox.typedSender) {
              _ when account != null => '$account (nazwa konta)',
              null => 'Zapytam przy pierwszej paczce',
              '' => 'Bez podpisu',
              final name => name,
            }),
            onTap: account != null
                ? null
                : () => _askForSender(context, outbox),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'Telefon zgłasza m.in. linki z bazy, których YouTube już nie '
              'odtwarza, razem z filmem znalezionym w zamian. Wysyłka automatyczna następuje przy '
              'uruchomieniu i powrocie do aplikacji, pod te same adresy co pobieranie bazy. Gdy '
              'serwer odmówi, zgłoszenia czekają do '
              'następnego dnia. Bez serwera zgłoszenia można wysłać paczką (plik .zip).',
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
