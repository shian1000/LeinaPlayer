import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/local_library.dart';
import '../data/playlist_library.dart';
import '../data/song_catalog.dart';
import '../data/source_settings.dart';
import '../data/youtube_account.dart';
import '../data/youtube_api.dart';
import '../data/youtube_export.dart';
import '../data/youtube_library.dart';
import '../playback/playback_queue.dart';
import '../playback/youtube_playback.dart';
import '../theme.dart';

/// "Utwórz na YouTube": asks first, then makes it ([exportToYouTube]) with the
/// progress shown, and ends with what was skipped.
Future<void> showYouTubeExportDialog(
  BuildContext context,
  PlaylistSummary playlist,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _YouTubeExportDialog(playlist: playlist),
);

enum _Stage { confirm, running, finished }

class _YouTubeExportDialog extends StatefulWidget {
  const _YouTubeExportDialog({required this.playlist});

  final PlaylistSummary playlist;

  @override
  State<_YouTubeExportDialog> createState() => _YouTubeExportDialogState();
}

class _YouTubeExportDialogState extends State<_YouTubeExportDialog> {
  var _stage = _Stage.confirm;
  var _done = 0;
  var _total = 0;
  var _cancelled = false;
  YouTubeExportResult? _result;
  String? _error;

  PlaylistSummary get _playlist => widget.playlist;

  Future<void> _start() async {
    final playlists = PlaylistLibraryScope.of(context);
    final catalog = SongCatalogScope.of(context);
    final library = LocalLibraryScope.of(context);
    final youTube = YouTubeLibraryScope.of(context);
    final queue = PlaybackQueueScope.of(context);
    final settings = SourceSettingsScope.of(context);
    final account = YouTubeAccountScope.of(context);
    setState(() => _stage = _Stage.running);
    try {
      await catalog.ensureLoaded();
      final tracks = await playlists.tracks(_playlist.id);
      final result = await exportToYouTube(
        playlist: _playlist,
        tracks: tracks,
        library: playlists,
        hitOf: (track) => playlistHit(track, catalog, library, youTube),
        findVideo: (hit) async => settings.youTubeSearchEnabled
            ? (await queue.findVideo(hit))?.id
            : null,
        token: account.token,
        tokenRejected: account.tokenRejected,
        api: account.api,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
            });
          }
        },
        cancelled: () => _cancelled,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _stage = _Stage.finished;
      });
    } on GoogleSignInFailed catch (e) {
      if (!mounted) return;
      if (e.cancelled) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _error = e.message;
        _stage = _Stage.finished;
      });
    } on YouTubeApiException catch (e) {
      // Making the playlist itself failed: nothing to show but why.
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _stage = _Stage.finished;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _stage != _Stage.running,
    child: switch (_stage) {
      _Stage.confirm => _confirm(context),
      _Stage.running => _running(context),
      _Stage.finished => _finished(context),
    },
  );

  Widget _confirm(BuildContext context) {
    final email = YouTubeAccountScope.of(context).email;
    final resuming = _playlist.youTubeCopyUnfinished;
    return AlertDialog(
      title: Text(
        resuming
            ? 'Dokończyć playlistę na YouTube?'
            : 'Utworzyć playlistę na YouTube?',
      ),
      content: Text(
        resuming
            ? 'Do „${_playlist.name}” na YouTube zostanie dodane '
                  '${_playlist.trackCount - _playlist.youTubeCopyDone!} pozostałych '
                  'utworów.'
            : 'Na ${email ?? 'Twoim koncie Google'} powstanie niepubliczna playlista '
                  '„${_playlist.name}” (${_playlist.trackCount} utw.) — każdy, kto dostanie '
                  'link, ją otworzy. To kopia: późniejsze zmiany w Bibliotece do niej nie '
                  'trafią.\n\n'
                  'YouTube pozwala dodać około 200 utworów dziennie; resztę można dokończyć '
                  'następnego dnia.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: _start,
          child: Text(resuming ? 'Dokończ' : 'Utwórz'),
        ),
      ],
    );
  }

  Widget _running(BuildContext context) => AlertDialog(
    title: const Text('Tworzenie playlisty na YouTube'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
        const SizedBox(height: 12),
        Text(
          _total == 0 ? 'Logowanie…' : '$_done z $_total utworów',
          style: TextStyle(color: context.palette.textSecondary),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _cancelled ? null : () => setState(() => _cancelled = true),
        child: const Text('Przerwij'),
      ),
    ],
  );

  Widget _finished(BuildContext context) {
    final result = _result;
    final palette = context.palette;
    if (result == null) {
      return AlertDialog(
        title: const Text('Nie udało się utworzyć playlisty'),
        content: Text(_error ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    }
    final stopped = result.stopped;
    final skipped = result.skipped;
    return AlertDialog(
      title: Text(
        stopped == null
            ? 'Playlista jest na YouTube'
            : 'Playlista na YouTube nie jest gotowa',
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                'Dodano ${result.added} utw.',
                if (stopped != null)
                  '${stopped.message}. Dokończysz ją z „Udostępnij” '
                      'tej playlisty.',
              ].join(' '),
            ),
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Bez filmu na YouTube, pominięte (${skipped.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final track in skipped)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          [?track.artist, track.title].join(' – '),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: AppFontSize.small,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Zamknij'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            openInYouTube(youTubePlaylistUri(result.playlistId));
          },
          child: const Text('Otwórz w YouTube'),
        ),
      ],
    );
  }
}
