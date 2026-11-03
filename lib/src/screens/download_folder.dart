import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_name.dart';
import '../data/source_settings.dart';
import '../playback/downloads.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/menu_sheet.dart';

/// [path] as the user knows it: the phone's own storage and an SD card by name.
String shownDownloadFolder(String path) => path
    .replaceFirst(RegExp(r'^/storage/emulated/0(?=/|$)'), 'Pamięć telefonu')
    .replaceFirst(
      RegExp(r'^/storage/[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}(?=/|$)'),
      'Karta SD',
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
      title: const Text('Miejsce na pobrane utwory'),
      subtitle: Text(
        folder == null
            ? 'W aplikacji — niewidoczne dla innych aplikacji'
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
          'W aplikacji',
          subtitle:
              'Widać je tylko w $appName; znikają po odinstalowaniu aplikacji',
          onTap: folder == null ? () {} : () => _apply(context, null),
        ),
        MenuSheetEntry(
          folder == null ? Icons.create_new_folder_outlined : Icons.check,
          folder == null ? 'Wybierz folder…' : 'Wybierz inny folder…',
          subtitle:
              'Np. Music — pliki „Wykonawca - Tytuł” widać w innych aplikacjach i zostają '
              'po odinstalowaniu',
          onTap: () => _pick(context),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Wybierz folder na pobrane utwory',
    );
    if (path == null || !context.mounted) return;
    final folder = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    if (folder == '/') {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Do tego folderu nie da się zapisywać. Wybierz folder w pamięci telefonu.',
          ),
        ),
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
              '$appName nie może zapisywać w folderze ${shownDownloadFolder(folder)}. '
              'Zezwól na dostęp do wszystkich plików albo wybierz inny folder.',
            ),
            action: const SnackBarAction(
              label: 'Ustawienia',
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
          title: const Text('Dostęp do plików'),
          content: const Text(
            'Żeby zapisywać utwory w wybranym folderze, $appName potrzebuje dostępu do '
            'wszystkich plików. Android otworzy ustawienia — włącz tam „Zezwalaj na dostęp do '
            'wszystkich plików” i wróć do aplikacji.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Dalej'),
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
    final where = folder == null
        ? 'do aplikacji'
        : 'do ${shownDownloadFolder(folder)}';
    if (downloads == null || downloads.count == 0 || !context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Pobierane utwory będą trafiać $where.')),
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
          title: const Text('Przenoszenie pobranych utworów'),
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
                Text('${value.done} z ${value.total}'),
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
        content: Text(
          failed == 0
              ? 'Przeniesiono $moved ${pluralWord(moved, 'utwór', 'utwory', 'utworów')} $where.'
              : 'Nie udało się przenieść części utworów — grają dalej ze starego miejsca. '
                    'Nowe pobrania trafiają $where.',
        ),
      ),
    );
  }
}
