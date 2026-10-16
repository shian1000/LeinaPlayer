import 'package:flutter/material.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/playlist_library.dart';
import '../theme.dart';
import '../widgets/song_cover.dart';
import '../widgets/song_names.dart';
import '../widgets/song_tile.dart';

/// "Edytuj" on a playlist made on the phone: its tracks in their own order, dragged by the
/// handle to move and taken out with ⊖. Nothing changes until "Zapisz"; Back drops the edit
/// (a [PopScope] asking first wouldn't be asked — `AppShell` pops tab routes directly).
class PlaylistEditScreen extends StatefulWidget {
  const PlaylistEditScreen({
    super.key,
    required this.playlist,
    required this.tracks,
    required this.onSaved,
  });

  final PlaylistSummary playlist;

  /// In the playlist's own order, each with the song it is.
  final List<(PlaylistTrack, SearchHit)> tracks;

  /// Called once the change is saved (a result can't come back through `pop`).
  final VoidCallback onSaved;

  static Future<void> open(
    BuildContext context, {
    required PlaylistSummary playlist,
    required List<(PlaylistTrack, SearchHit)> tracks,
    required VoidCallback onSaved,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlaylistEditScreen(
        playlist: playlist,
        tracks: tracks,
        onSaved: onSaved,
      ),
    ),
  );

  @override
  State<PlaylistEditScreen> createState() => _PlaylistEditScreenState();
}

class _PlaylistEditScreenState extends State<PlaylistEditScreen> {
  late final List<(PlaylistTrack, SearchHit)> _tracks = [...widget.tracks];
  bool _changed = false;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final library = PlaylistLibraryScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await library.rearrange(widget.playlist.id, [
        for (final (track, _) in _tracks) track.position,
      ]);
      widget.onSaved();
      navigator.pop();
    } catch (e) {
      debugPrint('Saving the playlist edit failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Nie udało się zapisać zmian.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.background,
        title: const Text('Edytuj playlistę'),
        actions: [
          TextButton(
            onPressed: _changed && !_saving ? _save : null,
            child: const Text('Zapisz'),
          ),
        ],
      ),
      body: _tracks.isEmpty
          ? Center(
              child: Text(
                'Playlista będzie pusta.',
                style: TextStyle(color: palette.textSecondary),
              ),
            )
          : ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _tracks.length,
              onReorderItem: (from, to) => setState(() {
                _tracks.insert(to, _tracks.removeAt(from));
                _changed = true;
              }),
              itemBuilder: (context, i) {
                final (track, hit) = _tracks[i];
                return ListTile(
                  key: ValueKey(track.position),
                  contentPadding: const EdgeInsets.only(left: 4, right: 8),
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Usuń z playlisty',
                        icon: Icon(
                          Icons.remove_circle_outline,
                          color: palette.textSecondary,
                        ),
                        onPressed: () => setState(() {
                          _tracks.removeAt(i);
                          _changed = true;
                        }),
                      ),
                      SongCover(
                        cover: CoverRequest.of(hit),
                        size: SongTile.coverSize,
                      ),
                    ],
                  ),
                  title: Text(
                    hit.shownTitle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    hit.shownArtist(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
