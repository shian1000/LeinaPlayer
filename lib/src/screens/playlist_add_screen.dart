import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/local_library.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/youtube_library.dart';
import '../theme.dart';
import '../widgets/song_selection.dart';
import '../widgets/song_tile.dart';

/// "Dodaj" on a saved playlist: song search (music.db and the phone, as Wyszukaj
/// finds them), each song with ⊕ putting it at the playlist's end at once, ✓ once it's there.
/// Tapping a row plays it, as everywhere else.
class PlaylistAddScreen extends StatefulWidget {
  const PlaylistAddScreen({
    super.key,
    required this.playlist,
    required this.present,
    required this.onAdded,
  });

  final PlaylistSummary playlist;

  /// [SongSelection.keyOf] of the songs already on it.
  final Set<Object> present;

  /// Called after each song added, so the playlist under this screen shows it.
  final VoidCallback onAdded;

  static Future<void> open(
    BuildContext context, {
    required PlaylistSummary playlist,
    required Set<Object> present,
    required VoidCallback onAdded,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlaylistAddScreen(
        playlist: playlist,
        present: present,
        onAdded: onAdded,
      ),
    ),
  );

  @override
  State<PlaylistAddScreen> createState() => _PlaylistAddScreenState();
}

class _PlaylistAddScreenState extends State<PlaylistAddScreen> {
  final _query = TextEditingController();
  late final Set<Object> _present = {...widget.present};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SongCatalogScope.of(context).ensureLoaded();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _add(SearchHit hit) async {
    final key = SongSelection.keyOf(hit);
    final messenger = ScaffoldMessenger.of(context);
    if (_present.contains(key)) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Ten utwór już jest na „${widget.playlist.name}”.'),
            duration: const Duration(seconds: 2),
          ),
        );
      return;
    }
    setState(() => _present.add(key));
    try {
      await PlaylistLibraryScope.of(context)
          .addSongs(widget.playlist.id, [hit]);
      widget.onAdded();
    } catch (e) {
      debugPrint('Adding to the playlist failed: $e');
      if (!mounted) return;
      setState(() => _present.remove(key));
      messenger.showSnackBar(
        const SnackBar(content: Text('Nie udało się dodać utworu.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hits = searchEverywhere(
      _query.text,
      SongCatalogScope.of(context),
      LocalLibraryScope.of(context),
      youTube: YouTubeLibraryScope.of(context),
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.background,
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Dodaj do „${widget.playlist.name}”',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_query.text.isNotEmpty)
            IconButton(
              tooltip: 'Wyczyść',
              icon: const Icon(Icons.close),
              onPressed: () => setState(_query.clear),
            ),
        ],
      ),
      body: _query.text.trim().isEmpty
          ? _Note('Wyszukaj utwory, które chcesz dodać.', palette: palette)
          : hits.isEmpty
          ? _Note('Brak wyników dla „${_query.text.trim()}”', palette: palette)
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final hit in hits)
                  SongTile(
                    hit: hit,
                    trailing: _present.contains(SongSelection.keyOf(hit))
                        ? IconButton(
                            tooltip: 'Jest na playliście',
                            icon: Icon(
                              Icons.check_circle,
                              color: palette.accent,
                            ),
                            onPressed: () => _add(hit),
                          )
                        : IconButton(
                            tooltip: 'Dodaj do playlisty',
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => _add(hit),
                          ),
                  ),
              ],
            ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {required this.palette});

  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: palette.textSecondary),
    ),
  );
}
