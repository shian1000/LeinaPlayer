import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/database_sync.dart';
import '../data/local_library.dart';
import '../data/outbox.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/song_requests.dart';
import '../data/youtube_library.dart';
import '../theme.dart';
import '../widgets/scrolling_text.dart';
import '../widgets/song_selection.dart';
import '../widgets/song_tile.dart';
import '../widgets/song_names.dart';

/// "Wyświetl utwory, których nie ma w bazie danych" from a playlist's ⋮: its tracks not
/// recognised as MusicDatabase songs, with "Poproś MusicDatabase o dodanie" asking for all of
/// them at once ([_RequestMissingButton]).
class MissingTracksScreen extends StatelessWidget {
  const MissingTracksScreen({
    super.key,
    required this.playlist,
    required this.tracks,
    this.saved = true,
  });

  final PlaylistSummary playlist;
  final List<PlaylistTrack> tracks;

  /// `false`: a playlist found by search and not in Biblioteka ([PlaylistSummary.id] means
  /// nothing).
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final hits = [
      for (final track in tracks) playlistHit(track, catalog, library, youTube),
    ];
    // Positions in the playlist, so a tap plays on through the whole playlist from there.
    final missing = [
      for (final (i, hit) in hits.indexed)
        if (!hit.inMainDatabase) i,
    ];

    final String summary;
    switch (catalog.status) {
      case CatalogStatus.ready:
        summary = missing.isEmpty
            ? 'Wszystkie utwory tej playlisty są w bazie danych.'
            : 'Poza bazą danych: ${missing.length} z ${hits.length}';
      case CatalogStatus.noDatabase:
        summary =
            'Baza danych nie jest jeszcze pobrana (Ustawienia › '
            'Serwer), więc żaden utwór nie został rozpoznany.';
      case CatalogStatus.error:
        summary = 'Nie udało się wczytać bazy danych.';
      case CatalogStatus.notLoaded || CatalogStatus.loading:
        summary = 'Wczytuję bazę danych…';
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Utwory spoza bazy danych'),
            ScrollingText(
              playlist.name,
              style: TextStyle(
                fontSize: AppFontSize.small,
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: SongSelectionArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                summary,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: AppFontSize.small,
                ),
              ),
            ),
            if (catalog.status == CatalogStatus.ready &&
                missing.isNotEmpty &&
                OutboxScope.maybeOf(context) != null)
              _RequestMissingButton(hits: [for (final i in missing) hits[i]]),
            if (catalog.status == CatalogStatus.ready)
              for (final i in missing)
                SongTile(
                  hit: hits[i],
                  queue: hits,
                  queueIndex: i,
                  playlistId: saved ? playlist.id : null,
                  youTubeListId: playlist.youTubeId,
                  playlistName: playlist.name,
                  subtitle: hits[i].shownArtist(context),
                ),
          ],
        ),
      ),
    );
  }
}

/// "Poproś MusicDatabase o dodanie": every listed track goes to the outbox as a song request,
/// as playing it would ([SongRequest.of]; one already asked for or rejected by MusicDatabase's
/// owner isn't asked again), then the outbox is sent at once, like "Wyślij teraz".
class _RequestMissingButton extends StatefulWidget {
  const _RequestMissingButton({required this.hits});

  final List<SearchHit> hits;

  @override
  State<_RequestMissingButton> createState() => _RequestMissingButtonState();
}

class _RequestMissingButtonState extends State<_RequestMissingButton> {
  bool _busy = false;

  Future<void> _request() async {
    final messenger = ScaffoldMessenger.of(context);
    final catalog = SongCatalogScope.of(context);
    final outbox = OutboxScope.of(context);
    final sync = DatabaseSyncScope.maybeOf(context);
    setState(() => _busy = true);
    var added = 0;
    var asked = 0;
    var rejected = 0;
    var unnamed = 0;
    String sent;
    try {
      for (final hit in widget.hits) {
        final request = SongRequest.of(hit, artistNamed: catalog.artistNamed);
        if (request == null) {
          unnamed++;
        } else if (catalog.rejectedSongRequests.rejects(request)) {
          rejected++;
        } else if (await outbox.requestSong(request)) {
          added++;
        } else {
          asked++;
        }
      }
      if (sync == null || !sync.hasServer) {
        sent = 'Wyślą się, gdy telefon połączy się z serwerem.';
      } else {
        final result = await outbox.send(
          await sync.serverAddresses(),
          manual: true,
        );
        sent = result.problem == null
            ? 'Wysłano do MusicDatabase.'
            : 'Nie wysłano: ${result.problem} Wyślą się przy następnej próbie.';
      }
    } catch (e) {
      sent = 'Nie udało się zapisać próśb: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    final counts = [
      'Nowe prośby o dodanie: $added',
      if (asked > 0) 'zgłoszone już wcześniej: $asked',
      if (rejected > 0) 'odrzucone przez MusicDatabase: $rejected',
      if (unnamed > 0) 'bez tytułu: $unnamed',
    ].join(' · ');
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('$counts\n$sent')));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        icon: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.playlist_add_check),
        label: const Text('Poproś MusicDatabase o dodanie'),
        onPressed: _busy ? null : _request,
      ),
    ),
  );
}
