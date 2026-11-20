import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/local_library.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../data/album_covers.dart';
import '../widgets/scrolling_text.dart';
import '../widgets/song_cover.dart';

/// "Ustawienia › Odtwarzanie › Źródła › Telefon" — folders on the phone that hold music, the
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
        content: Text(l10n.localMusicScreenNoAccess),
        action: statuses.values.any((s) => s.isPermanentlyDenied)
            ? SnackBarAction(
                label: l10n.localMusicScreenSettings,
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
      dialogTitle: l10n.localMusicScreenPickFolder,
    );
    if (path == null) return;
    if (path == '/') {
      _say(messenger, l10n.localMusicScreenUnreadableFolder);
      return;
    }
    await library.addFolder(path);
    _say(messenger, l10n.localMusicScreenFolderAdded(path));
  }

  Future<void> _scan(BuildContext context, LocalLibrary library) async {
    final messenger = ScaffoldMessenger.of(context);
    if (library.folders.isEmpty) {
      _say(messenger, l10n.localMusicScreenAddFolderFirst);
      return;
    }
    if (!await _ensureAudioAccess(messenger)) return;
    final result = await library.scan();
    _say(
      messenger,
      [
        l10n.localMusicScreenScanDone(result.added, result.newPending),
        if (result.removed > 0)
          l10n.localMusicScreenScanRemoved(result.removed),
        if (!result.mainDatabaseAvailable) l10n.localMusicScreenScanNoDatabase,
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
        title: Text(l10n.localMusicScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionTitle(l10n.localMusicScreenFolders),
          if (library.folders.isEmpty)
            ListTile(
              leading: Icon(
                Icons.folder_off_outlined,
                color: palette.textSecondary,
              ),
              title: Text(l10n.localMusicScreenNoFolders),
            ),
          for (final folder in library.folders)
            ListTile(
              leading: const Icon(Icons.folder),
              title: Text(folder.split('/').last),
              subtitle: Text(folder),
              trailing: IconButton(
                tooltip: l10n.localMusicScreenRemoveFolder,
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
              l10n.localMusicScreenAddFolder,
              style: TextStyle(color: palette.accent),
            ),
            onTap: () => _addFolder(context, library),
          ),
          SectionTitle(l10n.localMusicScreenScanning),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l10n.localMusicScreenLastScan),
            subtitle: Text(
              lastScan == null
                  ? l10n.localMusicScreenNever
                  : _formatDate(lastScan),
            ),
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
                library.scanning
                    ? l10n.localMusicScreenScanInProgress
                    : l10n.localMusicScreenScanNow,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: library.scanning
                  ? null
                  : () => _scan(context, library),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: Text(l10n.localMusicScreenSongsOnDevice(library.songCount)),
          ),
          ListTile(
            leading: Icon(Icons.fiber_new_outlined, color: palette.accent),
            title: Text(l10n.localMusicScreenNewSongs(library.pendingCount)),
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
        title: Text(l10n.localMusicScreenPendingTitle),
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
                  l10n.localMusicScreenAllInDatabase,
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
                title: ScrollingText(song.title),
                subtitle: ScrollingText(
                  [
                    song.artist ?? l10n.localMusicScreenUnknownArtist,
                    song.fileName,
                  ].join(' • '),
                  maxLines: 2,
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
