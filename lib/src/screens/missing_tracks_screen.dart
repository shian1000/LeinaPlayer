import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/database_sync.dart';
import '../data/local_library.dart';
import '../data/outbox.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/song_requests.dart';
import '../data/sync_sources.dart';
import '../l10n.dart';
import '../data/youtube_library.dart';
import '../theme.dart';
import '../widgets/scrolling_text.dart';
import '../widgets/song_selection.dart';
import '../widgets/song_tile.dart';
import '../widgets/song_names.dart';

/// "Wyświetl utwory, których nie ma w bazie danych" from a playlist's ⋮: its tracks not
/// recognised as MusicDatabase songs, with "Poproś MusicDatabase o dodanie" asking for all of
/// them at once ([_RequestMissingButton]). Tracks whose request MusicDatabase's owner rejected
/// ([_requestOf]) are left out of the list and the count, behind a line that shows them.
class MissingTracksScreen extends StatefulWidget {
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
  State<MissingTracksScreen> createState() => _MissingTracksScreenState();
}

class _MissingTracksScreenState extends State<MissingTracksScreen> {
  bool _showRejected = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final playlist = widget.playlist;
    final hits = [
      for (final track in widget.tracks)
        playlistHit(track, catalog, library, youTube),
    ];
    // Positions in the playlist, so a tap plays on through the whole playlist from there.
    final outside = [
      for (final (i, hit) in hits.indexed)
        if (!hit.inMainDatabase) i,
    ];
    final ready = catalog.status == CatalogStatus.ready;
    final rejected = <int>{
      if (ready)
        for (final i in outside)
          if (_requestOf(hits[i], catalog).rejected) i,
    };
    final missing = [
      for (final i in outside)
        if (!rejected.contains(i)) i,
    ];

    final String summary;
    switch (catalog.status) {
      case CatalogStatus.ready:
        summary = missing.isNotEmpty
            ? l10n.missingTracksScreenOutside(missing.length, hits.length)
            : rejected.isEmpty
            ? l10n.missingTracksScreenAllInDatabase
            : l10n.missingTracksScreenRestInDatabase;
      case CatalogStatus.noDatabase:
        summary = l10n.missingTracksScreenNoDatabase;
      case CatalogStatus.error:
        summary = l10n.missingTracksScreenLoadFailed;
      case CatalogStatus.notLoaded || CatalogStatus.loading:
        summary = l10n.missingTracksScreenLoading;
    }

    Widget row(int i) => SongTile(
      hit: hits[i],
      queue: hits,
      queueIndex: i,
      playlistId: widget.saved ? playlist.id : null,
      youTubeListId: playlist.youTubeId,
      playlistName: playlist.name,
      subtitle: hits[i].shownArtist(context),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.missingTracksScreenTitle),
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
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                rejected.isEmpty ? 8 : 0,
              ),
              child: Text(
                summary,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: AppFontSize.small,
                ),
              ),
            ),
            if (rejected.isNotEmpty)
              InkWell(
                onTap: () => setState(() => _showRejected = !_showRejected),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ScrollingText(
                          _showRejected
                              ? l10n.missingTracksScreenRejectedHide(
                                  rejected.length,
                                )
                              : l10n.missingTracksScreenRejectedShow(
                                  rejected.length,
                                ),
                          maxLines: 2,
                          style: TextStyle(
                            color: palette.accent,
                            fontSize: AppFontSize.small,
                          ),
                        ),
                      ),
                      Icon(
                        _showRejected ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: palette.accent,
                      ),
                    ],
                  ),
                ),
              ),
            if (_showRejected && rejected.isNotEmpty) ...[
              for (final i in rejected) row(i),
              Divider(color: palette.divider, height: 16),
            ],
            // The rejected ones go along so the snackbar still counts them.
            if (ready &&
                missing.isNotEmpty &&
                OutboxScope.maybeOf(context) != null)
              _RequestMissingButton(hits: [for (final i in outside) hits[i]]),
            if (ready)
              for (final i in missing) row(i),
          ],
        ),
      ),
    );
  }
}

/// What [hit] is asked as ([SongRequest.of]; `null` for no title) and whether MusicDatabase's
/// owner rejected that request — one decision for the screen's list and
/// [_RequestMissingButton], so they never disagree on which tracks are rejected.
({SongRequest? request, bool rejected}) _requestOf(
  SearchHit hit,
  SongCatalog catalog,
) {
  final request = SongRequest.of(hit, artistNamed: catalog.artistNamed);
  return (
    request: request,
    rejected: request != null && catalog.rejectedSongRequests.rejects(request),
  );
}

/// "Poproś MusicDatabase o dodanie": every track outside the database goes to the outbox as a
/// song request, as playing it would ([SongRequest.of]; one already asked for or rejected by
/// MusicDatabase's owner — [_requestOf] — isn't asked again, only counted), then the outbox is
/// sent at once, like "Wyślij teraz". Shown only while some track not rejected is still to be
/// asked for ([Outbox.allSongsRequested], checked again whenever the outbox changes) — once all
/// are in the outbox, waiting or sent, the screen opened again has no button.
class _RequestMissingButton extends StatefulWidget {
  const _RequestMissingButton({required this.hits});

  final List<SearchHit> hits;

  @override
  State<_RequestMissingButton> createState() => _RequestMissingButtonState();
}

class _RequestMissingButtonState extends State<_RequestMissingButton> {
  bool _busy = false;

  /// `null` until the outbox has been checked: no button meanwhile, so it doesn't flash.
  bool? _allAsked;
  int _check = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkAsked();
  }

  @override
  void didUpdateWidget(_RequestMissingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hits != widget.hits) _checkAsked();
  }

  Future<void> _checkAsked() async {
    final outbox = OutboxScope.of(context);
    final catalog = SongCatalogScope.of(context);
    final check = ++_check;
    final requests = [
      for (final hit in widget.hits)
        if (_requestOf(hit, catalog) case (
          request: final request?,
          rejected: false,
        ))
          request,
    ];
    try {
      final asked = await outbox.allSongsRequested(requests);
      if (mounted && check == _check) setState(() => _allAsked = asked);
    } catch (e) {
      debugPrint('Checking the asked-for songs failed: $e');
      if (mounted && check == _check) setState(() => _allAsked = false);
    }
  }

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
        final (:request, rejected: isRejected) = _requestOf(hit, catalog);
        if (request == null) {
          unnamed++;
        } else if (isRejected) {
          rejected++;
        } else if (await outbox.requestSong(request)) {
          added++;
        } else {
          asked++;
        }
      }
      if (sync == null || !sync.usesServer(SyncFeature.requests)) {
        sent = l10n.missingTracksScreenSendLater;
      } else {
        final result = await outbox.send(
          await sync.serverAddresses(),
          manual: true,
        );
        sent = result.problem == null
            ? l10n.missingTracksScreenSent
            : l10n.missingTracksScreenNotSent(result.problem!);
      }
    } catch (e) {
      sent = l10n.missingTracksScreenSaveFailed('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    final counts = [
      l10n.missingTracksScreenNewRequests(added),
      if (asked > 0) l10n.missingTracksScreenAskedBefore(asked),
      if (rejected > 0) l10n.missingTracksScreenRejected(rejected),
      if (unnamed > 0) l10n.missingTracksScreenUntitled(unnamed),
    ].join(' · ');
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('$counts\n$sent')));
  }

  @override
  Widget build(BuildContext context) => _allAsked != false && !_busy
      ? const SizedBox.shrink()
      : Padding(
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
              label: Text(l10n.missingTracksScreenRequestButton),
              onPressed: _busy ? null : _request,
            ),
          ),
        );
}
