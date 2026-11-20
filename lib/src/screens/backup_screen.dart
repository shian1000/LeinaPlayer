import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_name.dart';
import '../data/local_library.dart';
import '../data/user_backup.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Ustawienia › Kopia zapasowa: the user's data in one file kept outside the phone, and
/// restoring it (`user_backup.dart`).
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key, this.closeApp = _exit});

  /// Ends the app after a restore is staged, so the next start puts it in place; replaced in
  /// tests.
  final void Function() closeApp;

  static void _exit() => exit(0);

  static String _when(DateTime t) =>
      '${dayMonthLabel(t, year: true)}, '
      '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _export(BuildContext context) async {
    final backup = UserBackupScope.of(context);
    final library = LocalLibraryScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await backup.export(await library.database());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/zip')],
          subject: l10n.backupScreenShareSubject(appName),
        ),
      );
    } catch (e) {
      debugPrint('Making a backup failed: $e');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.backupScreenExportFailed)),
      );
    }
  }

  Future<void> _restore(BuildContext context) async {
    final backup = UserBackupScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    void fail(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));
    final List<int> bytes;
    final BackupInfo info;
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: l10n.backupScreenPickFile,
      );
      final file = picked.firstOrNull;
      if (file == null) return;
      bytes = await file.readAsBytes();
      info = UserBackup.inspect(bytes);
    } on BackupException catch (e) {
      fail(e.message);
      return;
    } catch (e) {
      debugPrint('Opening a backup failed: $e');
      fail(l10n.backupScreenOpenFailed);
      return;
    }
    if (!context.mounted) return;
    final sure =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.backupScreenRestoreTitle),
            content: Text(l10n.backupScreenRestoreBody(_when(info.createdAt))),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.backupScreenRestore),
              ),
            ],
          ),
        ) ??
        false;
    if (!sure) return;
    try {
      await backup.stage(bytes);
    } on BackupException catch (e) {
      fail(e.message);
      return;
    } catch (e) {
      debugPrint('Restoring a backup failed: $e');
      fail(l10n.backupScreenRestoreFailed);
      return;
    }
    closeApp();
  }

  @override
  Widget build(BuildContext context) {
    final backup = UserBackupScope.of(context);
    final palette = context.palette;
    final lastExport = backup.lastExport;
    final restoredFrom = backup.restoredFrom;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.backupScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          ListTile(
            enabled: !backup.busy,
            leading: Icon(Icons.save_alt, color: palette.accent),
            title: Text(
              l10n.backupScreenExport,
              style: TextStyle(color: palette.accent),
            ),
            subtitle: Text(l10n.backupScreenExportSubtitle),
            trailing: backup.busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: () => _export(context),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l10n.backupScreenLastExport),
            subtitle: Text(
              lastExport == null
                  ? l10n.backupScreenNoExportYet
                  : _when(lastExport),
            ),
          ),
          ListTile(
            enabled: !backup.busy,
            leading: const Icon(Icons.settings_backup_restore),
            title: Text(l10n.backupScreenRestoreFromFile),
            subtitle: Text(
              restoredFrom == null
                  ? l10n.backupScreenRestoreSubtitle
                  : l10n.backupScreenLastRestored(_when(restoredFrom)),
            ),
            onTap: () => _restore(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              l10n.backupScreenWhatsIn,
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
