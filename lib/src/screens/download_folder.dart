import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_name.dart';
import '../data/source_settings.dart';
import '../l10n.dart';
import '../playback/downloads.dart';
import '../theme.dart';
import '../widgets/menu_sheet.dart';

/// [path] as the user knows it: the phone's own storage and an SD card by name.
String shownDownloadFolder(String path) => path
    .replaceFirst(
      RegExp(r'^/storage/emulated/0(?=/|$)'),
      l10n.downloadFolderPhoneStorage,
    )
    .replaceFirst(
      RegExp(r'^/storage/[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}(?=/|$)'),
      l10n.downloadFolderSdCard,
    );

/// "Miejsce na pobrane utwory" (Oszczędzanie danych i tryb offline): where "Pobierz" keeps songs
/// — the app's own storage, or a folder the user picks (visible to other apps, kept after the
/// app is uninstalled). Songs downloaded before are moved there.
class DownloadFolderTile extends StatelessWidget {
  const DownloadFolderTile({super.key});

  @override
  Widget build(BuildContext context) {
    final folder = SourceSettingsScope.of(context).downloadFolder;
    return ListTile(
      leading: const Icon(Icons.download_for_offline_outlined),
      title: Text(l10n.downloadFolderTitle),
      subtitle: Text(
        folder == null
            ? l10n.downloadFolderInAppSubtitle
            : shownDownloadFolder(folder),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _choose(context),
    );
  }

  void _choose(BuildContext context) {
    final folder = SourceSettingsScope.of(context).downloadFolder;
    showMenuSheet(
      context,
      idPrefix: 'download-folder',
      entries: [
        MenuSheetEntry(
          folder == null ? Icons.check : Icons.phone_android,
          l10n.downloadFolderInApp,
          subtitle: l10n.downloadFolderInAppNote(appName),
          onTap: folder == null ? () {} : () => _apply(context, null),
        ),
        MenuSheetEntry(
          folder == null ? Icons.create_new_folder_outlined : Icons.check,
          folder == null
              ? l10n.downloadFolderPick
              : l10n.downloadFolderPickOther,
          subtitle: l10n.downloadFolderPickNote,
          onTap: () => _pick(context),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: l10n.downloadFolderPickerTitle,
    );
    if (path == null || !context.mounted) return;
    final folder = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    if (folder == '/') {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.downloadFolderRootNotWritable)),
      );
      return;
    }
    if (!await _canWrite(folder)) {
      if (!context.mounted || !await _askForAccess(context)) return;
      await [Permission.storage, Permission.manageExternalStorage].request();
      if (!await _canWrite(folder)) {
        messenger.showSnackBar(
          SnackBar(
            persist: false,
            content: Text(
              l10n.downloadFolderCannotWrite(
                appName,
                shownDownloadFolder(folder),
              ),
            ),
            action: SnackBarAction(
              label: l10n.downloadFolderSettings,
              onPressed: openAppSettings,
            ),
          ),
        );
        return;
      }
    }
    if (context.mounted) await _apply(context, folder);
  }

  static Future<bool> _canWrite(String folder) async {
    final probe = File(
      '$folder/.leina-player-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await Directory(folder).create(recursive: true);
      await probe.writeAsString('');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _askForAccess(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.downloadFolderAccessTitle),
          content: Text(l10n.downloadFolderAccessText(appName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.downloadFolderContinue),
            ),
          ],
        ),
      ) ??
      false;

  /// Saves [folder] and moves the songs downloaded so far there, showing how far it got.
  Future<void> _apply(BuildContext context, String? folder) async {
    final messenger = ScaffoldMessenger.of(context);
    final settings = SourceSettingsScope.of(context);
    final downloads = DownloadsScope.maybeOf(context);
    await settings.setDownloadFolder(folder);
    final shown = folder == null ? null : shownDownloadFolder(folder);
    if (downloads == null || downloads.count == 0 || !context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            shown == null
                ? l10n.downloadFolderWillGoToApp
                : l10n.downloadFolderWillGoTo(shown),
          ),
        ),
      );
      return;
    }
    final total = downloads.count;
    final progress = ValueNotifier((done: 0, total: total));
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.downloadFolderMovingTitle),
          content: ValueListenableBuilder(
            valueListenable: progress,
            builder: (context, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: value.total == 0 ? null : value.done / value.total,
                  color: context.palette.accent,
                ),
                const SizedBox(height: 12),
                Text(l10n.downloadFolderProgress(value.done, value.total)),
              ],
            ),
          ),
        ),
      ),
    );
    var failed = 0;
    try {
      failed = await downloads.relocate(
        onProgress: (done, total) =>
            progress.value = (done: done, total: total),
      );
    } catch (e) {
      debugPrint('Moving downloaded songs failed: $e');
      failed = total;
    } finally {
      navigator.pop();
      progress.dispose();
    }
    final moved = total - failed;
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch ((failed == 0, shown)) {
          (true, null) => l10n.downloadFolderMovedToApp(moved),
          (true, final to?) => l10n.downloadFolderMovedTo(moved, to),
          (false, null) => l10n.downloadFolderMoveFailedApp,
          (false, final to?) => l10n.downloadFolderMoveFailed(to),
        }),
      ),
    );
  }
}
