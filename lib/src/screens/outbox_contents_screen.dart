import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/database_sync.dart';
import '../data/local_library.dart';
import '../data/outbox.dart';
import '../data/song_catalog.dart';
import '../data/song_details.dart';
import '../data/song_requests.dart';
import '../data/text_normalizer.dart';
import '../data/youtube_library.dart';
import '../theme.dart';
import '../widgets/song_info.dart';
import '../widgets/song_tile.dart';

/// "Czeka na wysłanie" in Ustawienia › Zgłoszenia poprawek: the songs reported in the
/// requests still waiting in the outbox, with the video the phone found instead, the videos found
/// for songs without a link, the fields the user corrected in "Informacje o utworze", and the
/// songs played that music.db doesn't have, asked to be added.
class OutboxContentsScreen extends StatefulWidget {
  const OutboxContentsScreen({super.key});

  @override
  State<OutboxContentsScreen> createState() => _OutboxContentsScreenState();
}

class _OutboxContentsScreenState extends State<OutboxContentsScreen> {
  Future<(List<DeadLinkReport>, List<FoundLinkReport>, List<SongRequest>)>?
  _reports;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Also after a send or a new report while the screen is open.
    final outbox = OutboxScope.of(context);
    _reports = (
      outbox.waitingReports(),
      outbox.waitingFoundLinks(),
      outbox.waitingSongRequests(),
    ).wait;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final corrections = OutboxScope.of(context).waitingCorrections;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: const Text('Czeka na wysłanie'),
      ),
      body:
          FutureBuilder<
            (List<DeadLinkReport>, List<FoundLinkReport>, List<SongRequest>)
          >(
            future: _reports,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _Note('Nie udało się odczytać zgłoszeń.');
              }
              final data = snapshot.data;
              if (data == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final (reports, found, songs) = data;
              if (reports.isEmpty &&
                  found.isEmpty &&
                  corrections.isEmpty &&
                  songs.isEmpty) {
                return const _Note('Wszystkie zgłoszenia zostały wysłane.');
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (reports.isNotEmpty) ...[
                    const _Note(
                      'Linki z bazy danych, których YouTube już nie odtwarza. Do czasu poprawki w '
                      'MusicDatabase telefon gra film znaleziony w zamian.',
                    ),
                    for (final report in reports)
                      _SongReportTile(
                        songId: report.songId,
                        title: report.title,
                        artist: report.artist,
                        what: report.replacementTitle == null
                            ? 'Bez zamiennika'
                            : 'Zamiennik: '
                                  '${_video(report.replacementTitle, report.replacementChannel)}',
                      ),
                  ],
                  if (found.isNotEmpty) ...[
                    const _Note(
                      'Filmy znalezione przez telefon dla utworów bez linku w bazie danych.',
                    ),
                    for (final report in found)
                      _SongReportTile(
                        songId: report.songId,
                        title: report.title,
                        artist: report.artist,
                        what:
                            'Znaleziono: ${_video(report.videoTitle, report.videoChannel)}',
                      ),
                  ],
                  if (corrections.isNotEmpty) ...[
                    const _Note(
                      'Poprawki informacji o utworach. Do czasu ich przyjęcia w MusicDatabase '
                      'telefon pokazuje wartości z bazy danych.',
                    ),
                    for (final correction in corrections)
                      _CorrectionTile(correction),
                  ],
                  if (songs.isNotEmpty) ...[
                    const _Note(
                      'Utwory spoza bazy danych, o których dodanie telefon prosi MusicDatabase.',
                    ),
                    for (final song in songs)
                      ListTile(
                        leading: const Icon(Icons.playlist_add),
                        title: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          song.artist ?? SongRequest.unknownArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
    );
  }
}

String _video(String? title, String? channel) =>
    '${title ?? ''}${channel == null || channel.isEmpty ? '' : ' ($channel)'}';

class _SongReportTile extends StatelessWidget {
  const _SongReportTile({
    required this.songId,
    required this.title,
    required this.artist,
    required this.what,
  });

  final int songId;
  final String title;
  final String artist;
  final String what;

  @override
  Widget build(BuildContext context) {
    final subtitle = '$artist · $what';
    final song = SongCatalogScope.of(context).byId(songId);
    // Gone from the downloaded music.db (merged or deleted since): shown as reported.
    if (song == null) {
      return ListTile(
        leading: const Icon(Icons.music_note_outlined),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      );
    }
    final hit = withPhoneYouTube(
      SearchHit.main(song, LocalLibraryScope.of(context).filesOf(song.id)),
      YouTubeLibraryScope.of(context),
    );
    return SongTile(hit: hit, queue: [hit], subtitle: subtitle);
  }
}

class _CorrectionTile extends StatelessWidget {
  const _CorrectionTile(this.correction);

  final FieldCorrection correction;

  /// A rename that doesn't look like a spelling fix — "Paramore" → "David Byrne" — was likely
  /// meant as another artist for the song it was made from (MusicDatabase's hand-off
  /// `artist-rename-guard-for-musicdatabaseapp.md`).
  bool get _unlikeRename {
    final c = correction;
    return c.table == 'artists' &&
        c.column == 'name' &&
        c.oldValue is String &&
        c.newValue is String &&
        !nameResembles(c.oldValue! as String, c.newValue! as String);
  }

  /// Turns the rename into a `songs.artist_id` correction of the song it was made from, when
  /// the renamed artist is that song's own one in music.db.
  Future<void> _switchToOtherArtist(BuildContext context) async {
    final c = correction;
    final messenger = ScaffoldMessenger.of(context);
    final outbox = OutboxScope.of(context);
    final sync = DatabaseSyncScope.maybeOf(context);
    final song = SongCatalogScope.of(context).current(c.songId);
    final details = sync == null || song == null
        ? null
        : await readSongDetails(sync, song.id).catchError((Object e) {
            debugPrint('Reading song details failed: $e');
            return null;
          });
    if (song == null ||
        details == null ||
        details.song['artist_id'] != c.rowId) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '„${c.oldValue}” nie jest głównym wykonawcą utworu „${c.title}” — '
            'zostaje zmiana nazwy.',
          ),
        ),
      );
      return;
    }
    await outbox.correctField(
      table: 'artists',
      rowId: c.rowId,
      column: 'name',
      oldValue: c.oldValue,
      newValue: c.oldValue,
      song: song,
    );
    await outbox.correctField(
      table: 'songs',
      rowId: song.id,
      column: 'artist_id',
      oldValue: c.rowId,
      newValue: c.newValue,
      oldAsValue: c.oldValue,
      song: song,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Zamiast zmiany nazwy: „${c.newValue}” jako wykonawca utworu „${c.title}”.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = correction;
    String shown(Object? v) => fieldValue(c.table, c.column, v) ?? '(puste)';
    final where = switch (c.table) {
      'artists' => 'wykonawca',
      'albums' => 'album',
      _ => null,
    };
    final unlike = _unlikeRename;
    return ListTile(
      leading: const Icon(Icons.edit_outlined),
      title: Text(
        // old_value is an artists.id there; the song's artist is in the subtitle.
        c.table == 'songs' && c.column == 'artist_id'
            ? 'Inny wykonawca: ${shown(c.newValue)}'
            : '${fieldLabel(c.table, c.column)}${where == null ? '' : ' ($where)'}: '
                  '${shown(c.oldValue)} → ${shown(c.newValue)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${c.title} · ${c.artist}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (unlike) ...[
            Text(
              'To nie wygląda na poprawkę pisowni — zmieni nazwę we wszystkich utworach '
              'wykonawcy. Czy ten utwór ma innego wykonawcę?',
              style: TextStyle(color: context.palette.accent),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => _switchToOtherArtist(context),
                child: const Text('Tak, tylko ten utwór'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      text,
      style: TextStyle(
        color: context.palette.textSecondary,
        fontSize: AppFontSize.small,
      ),
    ),
  );
}
