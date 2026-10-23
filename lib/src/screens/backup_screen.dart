import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/local_library.dart';
import '../data/user_backup.dart';
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
          subject: 'Kopia zapasowa Leina Radio',
        ),
      );
    } catch (e) {
      debugPrint('Making a backup failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Nie udało się zrobić kopii zapasowej.')),
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
        dialogTitle: 'Wybierz plik kopii zapasowej',
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
      fail('Nie udało się otworzyć tego pliku.');
      return;
    }
    if (!context.mounted) return;
    final sure =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Przywrócić kopię zapasową?'),
            content: Text(
              'Kopia z ${_when(info.createdAt)}. Playlisty, nastroje, statystyki, '
              'polubione, „Na później”, historia i ustawienia z tego telefonu '
              'zostaną zastąpione tymi z kopii.\n\n'
              'Aplikacja się zamknie — otwórz ją ponownie, żeby dokończyć.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Anuluj'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Przywróć'),
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
      fail('Nie udało się przywrócić kopii zapasowej.');
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
        title: const Text('Kopia zapasowa'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          ListTile(
            enabled: !backup.busy,
            leading: Icon(Icons.save_alt, color: palette.accent),
            title: Text(
              'Zrób kopię zapasową…',
              style: TextStyle(color: palette.accent),
            ),
            subtitle: const Text(
              'Plik .zip na Dysk Google, do e-maila, na komputer…',
            ),
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
            title: const Text('Ostatnia kopia'),
            subtitle: Text(
              lastExport == null ? 'Jeszcze nie zrobiona' : _when(lastExport),
            ),
          ),
          ListTile(
            enabled: !backup.busy,
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Przywróć z pliku…'),
            subtitle: Text(
              restoredFrom == null
                  ? 'Zastępuje dane na tym telefonie danymi z kopii'
                  : 'Ostatnio przywrócona: kopia z ${_when(restoredFrom)}',
            ),
            onTap: () => _restore(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'W kopii: playlisty i foldery, nastroje, statystyki słuchania, historia, '
              'polubione i „Na później” (utwory i linki), wybrane okładki, filmy dopasowane '
              'przez telefon, czekające zgłoszenia poprawek i ustawienia.\n\n'
              'Bez: logowania do MusicDatabase i Google, kodów API YouTube i Spotify, '
              'pobranych utworów i pamięci podręcznej (pobierają się ponownie) oraz bazy '
              'muzyki (pobiera się z serwera albo GitHuba).\n\n'
              'Aplikacja niczego sama nie wysyła — plik trafia tylko tam, gdzie go '
              'udostępnisz. Z kontem MusicDatabase playlisty, nastroje i polubione '
              'synchronizują się też z serwerem.',
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
