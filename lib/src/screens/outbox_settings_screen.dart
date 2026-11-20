import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/account.dart';
import '../data/database_sync.dart';
import '../data/outbox.dart';
import '../data/sync_sources.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'outbox_contents_screen.dart';

/// "Zgłoszenia poprawek" (Synchronizacja › Prośby do bazy danych › Telefon): the requests for MusicDatabase waiting in the phone's
/// outbox (e.g. links YouTube no longer plays) and sending them — to the server, or as a package
/// through the share sheet (ADR 0014).
class OutboxSettingsScreen extends StatelessWidget {
  const OutboxSettingsScreen({super.key});

  static String requestsLabel(int n) => l10n.outboxSettingsScreenRequests(n);

  /// Asks for the name packages are signed with; `false` when the user cancelled.
  static Future<bool> _askForSender(BuildContext context, Outbox outbox) async {
    final typed = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: l10n.outboxSettingsScreenSenderDialogTitle,
        hint: l10n.outboxSettingsScreenSenderDialogHint,
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
        SnackBar(content: Text(l10n.outboxSettingsScreenNothingToSend)),
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
            l10n.outboxSettingsScreenExported(package.names.length),
            if (package.leftOut > 0)
              l10n.outboxSettingsScreenLeftOut(package.leftOut),
            if (package.refused > 0)
              l10n.outboxSettingsScreenTooLarge(package.refused),
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
        SnackBar(content: Text(l10n.outboxSettingsScreenLastPackageGone)),
      );
      return;
    }
    await _share(package);
  }

  static Future<ShareResult> _share(RequestPackage package) =>
      SharePlus.instance.share(
        ShareParams(
          files: [XFile(package.file.path, mimeType: 'application/zip')],
          subject: l10n.outboxSettingsScreenShareSubject,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final outbox = OutboxScope.of(context);
    final account = AccountScope.maybeOf(context)?.userName;
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.outboxSettingsScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.forward_to_inbox_outlined),
            title: Text(l10n.outboxSettingsScreenAutoSend),
            subtitle: Text(
              outbox.autoSend
                  ? l10n.outboxSettingsScreenAutoSendOn
                  : l10n.outboxSettingsScreenAutoSendOff,
            ),
            value: outbox.autoSend,
            onChanged: outbox.setAutoSend,
          ),
          const OutboxSendTiles(),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(l10n.outboxSettingsScreenSender),
            subtitle: Text(switch (outbox.typedSender) {
              _ when account != null => l10n.outboxSettingsScreenSenderAccount(
                account,
              ),
              null => l10n.outboxSettingsScreenSenderAsk,
              '' => l10n.outboxSettingsScreenSenderNone,
              final name => name,
            }),
            onTap: account != null
                ? null
                : () => _askForSender(context, outbox),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              l10n.outboxSettingsScreenExplanation,
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

/// "Czeka na wysłanie", "Ostatnie wysyłanie", "Wyślij teraz", "Wyślij paczkę…" and "Wyeksportuj
/// ponownie ostatnią paczkę" — on Zgłoszenia poprawek and at the end of Synchronizacja › Prośby.
class OutboxSendTiles extends StatelessWidget {
  const OutboxSendTiles({super.key});

  @override
  Widget build(BuildContext context) {
    final outbox = OutboxScope.of(context);
    final sync = DatabaseSyncScope.of(context);
    final palette = context.palette;
    final result = outbox.lastSend;
    final canExport = !outbox.sending && outbox.waiting > 0;
    final canSend =
        !outbox.sending &&
        outbox.waiting > 0 &&
        sync.usesServer(SyncFeature.requests);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.outbox_outlined),
          title: Text(l10n.outboxSettingsScreenWaiting),
          subtitle: Text(
            outbox.sending
                ? l10n.outboxSettingsScreenSending
                : outbox.waiting == 0
                ? l10n.outboxSettingsScreenNothing
                : OutboxSettingsScreen.requestsLabel(outbox.waiting),
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
            title: Text(l10n.outboxSettingsScreenLastSend),
            subtitle: Text(
              [
                l10n.outboxSettingsScreenSent(result.sent),
                if (result.refused > 0)
                  l10n.outboxSettingsScreenRefused(result.refused),
                ?result.problem,
                if (outbox.heldForToday && outbox.autoSend)
                  l10n.outboxSettingsScreenRetryTomorrow,
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
            l10n.outboxSettingsScreenSendNow,
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
            l10n.outboxSettingsScreenSendPackage,
            style: TextStyle(
              color: canExport ? palette.accent : palette.textSecondary,
            ),
          ),
          subtitle: Text(
            outbox.waiting == 0
                ? l10n.outboxSettingsScreenPackageHint
                : l10n.outboxSettingsScreenPackageHintCount(outbox.waiting),
          ),
          onTap: () => OutboxSettingsScreen._sendPackage(context, outbox),
        ),
        if (outbox.lastPackage.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.replay),
            title: Text(l10n.outboxSettingsScreenExportAgain),
            subtitle: Text(
              OutboxSettingsScreen.requestsLabel(outbox.lastPackage.length),
            ),
            onTap: () => OutboxSettingsScreen._sendAgain(context, outbox),
          ),
      ],
    );
  }
}
