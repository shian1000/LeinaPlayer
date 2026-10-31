import 'package:flutter/material.dart';

import '../data/local_library.dart';
import '../data/smart_playlists.dart';
import '../data/song_catalog.dart';
import '../data/youtube_library.dart';
import '../playback/playback_queue.dart';
import '../theme.dart';
import '../widgets/menu_sheet.dart';
import '../widgets/playlist_picker.dart';
import '../widgets/song_selection.dart';
import '../widgets/song_tile.dart';

const _id = 'Dynamiczna playlista';

/// Biblioteka › Dynamiczne playlisty: the phone's [SmartPlaylist]s and "Nowa dynamiczna
/// playlista".
class SmartPlaylistsScreen extends StatelessWidget {
  const SmartPlaylistsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SmartPlaylistsScreen()));

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final playlists = SmartPlaylistsScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Dynamiczne playlisty')),
      floatingActionButton: playlists == null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Nowa'),
              onPressed: () => createSmartPlaylist(context),
            ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Dynamiczna playlista to zapisany filtr — np. „Wykonawca: Kino” albo '
              '„Rok: 1987”. Jej utwory są wyszukiwane od nowa przy każdym otwarciu, '
              'więc same dochodzą po pobraniu nowszej bazy. Tylko na tym telefonie.',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: AppFontSize.small,
              ),
            ),
          ),
          for (final p in playlists?.playlists ?? const <SmartPlaylist>[])
            SmartPlaylistTile(playlist: p),
        ],
      ),
    );
  }
}

/// A dynamic playlist's row, opening it.
class SmartPlaylistTile extends StatelessWidget {
  const SmartPlaylistTile({super.key, required this.playlist});

  final SmartPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: palette.chip,
          borderRadius: palette.radius(4),
        ),
        child: Icon(Icons.auto_mode, color: palette.textSecondary),
      ),
      title: Text(playlist.name),
      subtitle: Text('Dynamiczna • ${playlist.rule}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SmartPlaylistScreen(playlistId: playlist.id),
        ),
      ),
    );
  }
}

/// Asks for a dynamic playlist's name, field and value, then saves it.
Future<void> createSmartPlaylist(BuildContext context) async {
  final playlists = SmartPlaylistsScope.maybeOf(context);
  if (playlists == null) return;
  final result = await showDialog<(String, SearchField, String)>(
    context: context,
    builder: (_) => const _NewSmartPlaylistDialog(),
  );
  if (result == null) return;
  final (name, field, value) = result;
  await playlists.add(name: name, field: field, value: value);
}

class _NewSmartPlaylistDialog extends StatefulWidget {
  const _NewSmartPlaylistDialog();

  @override
  State<_NewSmartPlaylistDialog> createState() =>
      _NewSmartPlaylistDialogState();
}

class _NewSmartPlaylistDialogState extends State<_NewSmartPlaylistDialog> {
  final _name = TextEditingController();
  final _value = TextEditingController();
  var _field = SearchField.artist;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _value.text.trim();
    return AlertDialog(
      title: const Text('Nowa dynamiczna playlista'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<SearchField>(
            initialValue: _field,
            decoration: const InputDecoration(labelText: 'Pole'),
            items: [
              for (final field in SearchField.values)
                DropdownMenuItem(value: field, child: Text(field.label)),
            ],
            onChanged: (field) => setState(() => _field = field ?? _field),
          ),
          TextField(
            controller: _value,
            decoration: const InputDecoration(
              labelText: 'Wartość',
              hintText: 'np. Kino, 1987, polski',
            ),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: 'Nazwa',
              hintText: value.isEmpty ? 'Nazwa playlisty' : value,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: value.isEmpty
              ? null
              : () => Navigator.of(context).pop((
                  _name.text.trim().isEmpty ? value : _name.text.trim(),
                  _field,
                  value,
                )),
          child: const Text('Utwórz'),
        ),
      ],
    );
  }
}

/// One dynamic playlist: its songs found now, "Odtwórz" / "Losowo", and its menu.
class SmartPlaylistScreen extends StatelessWidget {
  const SmartPlaylistScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final playlist = SmartPlaylistsScope.maybeOf(context)?.byId(playlistId);
    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            'Tej playlisty już nie ma.',
            style: TextStyle(color: palette.textSecondary),
          ),
        ),
      );
    }
    final hits = playlist.songs(
      SongCatalogScope.of(context),
      LocalLibraryScope.of(context),
      YouTubeLibraryScope.of(context),
    );
    void play({required bool shuffled}) {
      final queue = PlaybackQueueScope.of(context);
      runQueueAction(
        context,
        (onStatus) => shuffled
            ? queue.startShuffled(
                hits,
                playlistName: playlist.name,
                onStatus: onStatus,
              )
            : queue.start(
                hits,
                0,
                playlistName: playlist.name,
                onStatus: onStatus,
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          IconButton(
            tooltip: 'Menu playlisty (⋮)',
            icon: const Icon(Icons.more_vert),
            onPressed: () => showMenuSheet(
              context,
              idPrefix: '$_id › Menu (⋮)',
              entries: [
                if (hits.isNotEmpty) ...[
                  ...queueAllEntries(
                    context,
                    hits,
                    origin: QueueOrigin(playlistName: playlist.name),
                    feminine: true,
                  ),
                  ?playlistMenuEntry(context, hits),
                ],
                MenuSheetEntry(
                  Icons.delete_outline,
                  'Usuń dynamiczną playlistę',
                  subtitle: 'Utwory zostają',
                  onTap: () {
                    SmartPlaylistsScope.maybeOf(context)?.delete(playlist.id);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body: SongSelectionArea(
        all: () => {for (final hit in hits) SongSelection.keyOf(hit): hit},
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '${playlist.rule} • ${hits.length} utw.',
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Odtwórz'),
                    onPressed: hits.isEmpty
                        ? null
                        : () => play(shuffled: false),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Losowo'),
                    onPressed: hits.isEmpty ? null : () => play(shuffled: true),
                  ),
                ],
              ),
            ),
            if (hits.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Żaden utwór nie pasuje teraz do „${playlist.rule}”.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textSecondary),
                ),
              ),
            for (final (i, hit) in hits.indexed)
              SongTile(
                hit: hit,
                queue: hits,
                queueIndex: i,
                playlistName: playlist.name,
                trailing: SongMenuButton(
                  hit: hit,
                  idPrefix: '$_id › Utwór › Menu (⋮)',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
