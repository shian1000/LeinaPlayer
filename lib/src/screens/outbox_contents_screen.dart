import 'package:flutter/material.dart';

import '../data/combined_search.dart';
import '../data/local_library.dart';
import '../data/outbox.dart';
import '../data/song_catalog.dart';
import '../data/youtube_library.dart';
import '../theme.dart';
import '../widgets/song_info.dart';
import '../widgets/song_tile.dart';

/// "Czeka na wysłanie" in Ustawienia › Zgłoszenia poprawek: the songs reported in the
/// requests still waiting in the outbox, with the video the phone found instead, the videos found
/// for songs without a link, and the fields the user corrected in "Informacje o utworze".
class OutboxContentsScreen extends StatefulWidget {
  const OutboxContentsScreen({super.key});

  @override
  State<OutboxContentsScreen> createState() => _OutboxContentsScreenState();
}

class _OutboxContentsScreenState extends State<OutboxContentsScreen> {
  Future<(List<DeadLinkReport>, List<FoundLinkReport>)>? _reports;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Also after a send or a new report while the screen is open.
    final outbox = OutboxScope.of(context);
    _reports = (outbox.waitingReports(), outbox.waitingFoundLinks()).wait;
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
      body: FutureBuilder<(List<DeadLinkReport>, List<FoundLinkReport>)>(
        future: _reports,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Note('Nie udało się odczytać zgłoszeń.');
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final (reports, found) = data;
          if (reports.isEmpty && found.isEmpty && corrections.isEmpty) {
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

  @override
  Widget build(BuildContext context) {
    final c = correction;
    String shown(Object? v) => fieldValue(c.table, c.column, v) ?? '(puste)';
    final where = switch (c.table) {
      'artists' => 'wykonawca',
      'albums' => 'album',
      _ => null,
    };
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
      subtitle: Text(
        '${c.title} · ${c.artist}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
