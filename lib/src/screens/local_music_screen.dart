import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/local_library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../data/album_covers.dart';
import '../widgets/song_cover.dart';

/// "Ustawienia › Muzyka na telefonie" — folders on the phone that hold music, the
/// scan that records their files in the phone's `local.db`, and the files not yet in
/// MusicDatabase ("Nowe utwory spoza bazy danych").
class LocalMusicScreen extends StatelessWidget {
  const LocalMusicScreen({super.key});

  static void _say(ScaffoldMessengerState messenger, String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  /// Asks for read access to music files: READ_MEDIA_AUDIO on Android 13+, storage below it
  /// (each request is a no-op where it doesn't apply).
  static Future<bool> _ensureAudioAccess(
    ScaffoldMessengerState messenger,
  ) async {
    final statuses = await [Permission.audio, Permission.storage].request();
    if (statuses.values.any((s) => s.isGranted || s.isLimited)) return true;
    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'Bez dostępu do plików muzycznych nie da się ich skanować.',
        ),
        action: statuses.values.any((s) => s.isPermanentlyDenied)
            ? const SnackBarAction(
                label: 'Ustawienia',
                onPressed: openAppSettings,
              )
            : null,
      ),
    );
    return false;
  }

  Future<void> _addFolder(BuildContext context, LocalLibrary library) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await _ensureAudioAccess(messenger)) return;
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Wybierz folder z muzyką',
    );
    if (path == null) return;
    if (path == '/') {
      _say(
        messenger,
        'Tego folderu nie da się odczytać. Wybierz folder w pamięci telefonu.',
      );
      return;
    }
    await library.addFolder(path);
    _say(messenger, 'Dodano folder $path');
  }

  Future<void> _scan(BuildContext context, LocalLibrary library) async {
    final messenger = ScaffoldMessenger.of(context);
    if (library.folders.isEmpty) {
      _say(messenger, 'Najpierw dodaj folder z muzyką.');
      return;
    }
    if (!await _ensureAudioAccess(messenger)) return;
    final result = await library.scan();
    _say(
      messenger,
      [
        'Skanowanie zakończone: nowe pliki ${result.added}, '
            'w tym spoza bazy danych ${result.newPending}.',
        if (result.removed > 0) 'Usunięte z listy: ${result.removed}.',
        if (!result.mainDatabaseAvailable) 'Brak pobranej bazy danych — nie dało się sprawdzić, które są w bazie.',
      ].join(' '),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final library = LocalLibraryScope.of(context);
    final lastScan = library.lastScan;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Muzyka na telefonie'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SectionTitle('Foldery do skanowania'),
          if (library.folders.isEmpty)
            ListTile(
              leading: Icon(
                Icons.folder_off_outlined,
                color: palette.textSecondary,
              ),
              title: const Text('Nie dodano folderów'),
            ),
          for (final folder in library.folders)
            ListTile(
              leading: const Icon(Icons.folder),
              title: Text(folder.split('/').last),
              subtitle: Text(folder),
              trailing: IconButton(
                tooltip: 'Usuń folder',
                icon: Icon(Icons.close, color: palette.textSecondary),
                onPressed: () => library.removeFolder(folder),
              ),
            ),
          ListTile(
            leading: Icon(
              Icons.create_new_folder_outlined,
              color: palette.accent,
            ),
            title: Text(
              'Dodaj folder',
              style: TextStyle(color: palette.accent),
            ),
            onTap: () => _addFolder(context, library),
          ),
          const SectionTitle('Skanowanie'),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Ostatnie skanowanie'),
            subtitle: Text(lastScan == null ? 'Nigdy' : _formatDate(lastScan)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.onAccent,
                shape: palette.pillShape,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: library.scanning
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.onAccent,
                      ),
                    )
                  : const Icon(Icons.manage_search),
              label: Text(
                library.scanning ? 'Skanowanie…' : 'Skanuj teraz',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: library.scanning
                  ? null
                  : () => _scan(context, library),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: Text('Utwory zapisane na urządzeniu: ${library.songCount}'),
          ),
          ListTile(
            leading: Icon(Icons.fiber_new_outlined, color: palette.accent),
            title: Text(
              'Nowe utwory spoza bazy danych: ${library.pendingCount}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PendingSongsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Files on the phone whose songs aren't in MusicDatabase yet (`pending` in `local.db`).
class PendingSongsScreen extends StatefulWidget {
  const PendingSongsScreen({super.key});

  @override
  State<PendingSongsScreen> createState() => _PendingSongsScreenState();
}

class _PendingSongsScreenState extends State<PendingSongsScreen> {
  Future<List<LocalSong>>? _songs;
  int? _loadedForCount;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-query only when the pending count changes (e.g. a scan finished), not on every build.
    final library = LocalLibraryScope.of(context);
    if (_loadedForCount != library.pendingCount) {
      _loadedForCount = library.pendingCount;
      _songs = library.pendingSongs();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Nowe utwory spoza bazy'),
      ),
      body: FutureBuilder<List<LocalSong>>(
        future: _songs,
        builder: (context, snapshot) {
          final songs = snapshot.data;
          if (songs == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (songs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Wszystkie utwory z telefonu są w bazie danych.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textSecondary),
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, i) {
              final song = songs[i];
              return ListTile(
                leading: SongCover(cover: CoverRequest.ofFile(song), size: 48),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    song.artist ?? 'Nieznany wykonawca',
                    song.fileName,
                  ].join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

String _formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}, ${two(d.hour)}:${two(d.minute)}';
}
