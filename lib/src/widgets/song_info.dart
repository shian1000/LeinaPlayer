import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/combined_search.dart';
import '../data/database_sync.dart';
import '../data/incoming_links.dart';
import '../data/latin_names.dart';
import '../data/moods.dart';
import '../data/outbox.dart';
import '../data/song_catalog.dart';
import '../data/song_details.dart';
import '../data/youtube_library.dart';
import '../playback/player_controller.dart';
import '../playback/youtube_playback.dart';
import '../theme.dart';
import 'common.dart';

/// "Wyświetl informacje o utworze" from a song's menu: the same [SongInfoCard] as under the
/// full player, in a sheet that can be dragged up to the whole screen.
Future<void> showSongInfoSheet(BuildContext context, SearchHit hit) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 1,
          builder: (sheetContext, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [SongInfoCard(hit: hit)],
          ),
        ),
      ),
    );

/// "Informacje o utworze" under the full player: everything music.db, tag.db, the moods and the
/// phone know about [hit] — for now all of it, to be trimmed once it's clear what's worth showing
/// (user's request). The song's, its artists' and its album's own fields can be corrected: the
/// correction goes to the [Outbox] for MusicDatabase, and the field keeps music.db's value until
/// a downloaded music.db changes it.
class SongInfoCard extends StatefulWidget {
  const SongInfoCard({super.key, required this.hit, this.track});

  final SearchHit hit;

  /// What the player is playing it from.
  final NowPlaying? track;

  @override
  State<SongInfoCard> createState() => _SongInfoCardState();
}

class _SongInfoCardState extends State<SongInfoCard> {
  Future<SongDetails?>? _details;
  (int?, DateTime?)? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(SongInfoCard old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    final sync = DatabaseSyncScope.maybeOf(context);
    final id = widget.hit.mainSong?.id;
    final key = (id, sync?.lastSync);
    if (key == _loadedFor) return;
    _loadedFor = key;
    _details = sync == null || id == null
        ? null
        : readSongDetails(sync, id).catchError((Object e) {
            debugPrint('Reading song details failed: $e');
            return null;
          });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      shape: palette.boxShape(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: FutureBuilder<SongDetails?>(
          future: _details,
          builder: (context, snapshot) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Informacje o utworze',
                style: TextStyle(
                  fontSize: AppFontSize.emphasis,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_details != null &&
                  snapshot.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ..._sections(context, snapshot.data),
            ],
          ),
        ),
      ),
    );
  }

  /// The song with what the phone has learned on YouTube since it was queued.
  SearchHit get _hit {
    final youTube = YouTubeLibraryScope.maybeOf(context);
    return youTube == null ? widget.hit : withPhoneYouTube(widget.hit, youTube);
  }

  List<Widget> _sections(BuildContext context, SongDetails? details) {
    final hit = _hit;
    final mainSong = hit.mainSong;
    return [
      if (mainSong == null)
        const _Note('Tego utworu nie ma w MusicDatabase.')
      else if (details == null)
        const _Note('Nie udało się odczytać szczegółów z music.db.'),
      if (details == null)
        _Section('Utwór', [
          _Field('Tytuł', hit.title),
          _Field('Wykonawca', hit.artistLabel),
          _Field('Album', hit.album),
          _Field('Rok', hit.year?.toString()),
          if (mainSong != null) ...[
            _Field('Język', mainSong.language),
            _Field('ID w MusicDatabase', '${mainSong.id}'),
          ],
        ])
      else ...[
        _songSection(details),
        for (final (i, a) in details.artists.indexed)
          _artistSection(a.role, a.artist, first: i == 0),
        if (details.album != null) _albumSection(details),
      ],
      _linksSection(details),
      _moodsSection(context, details),
      _phoneSection(),
    ];
  }

  Widget _songSection(SongDetails details) {
    final song = _withLatinColumn(details.song, 'title', 'title_latin');
    const shownElsewhere = {
      'artist_id',
      'album_id',
      'youtube_video_id',
      'music_video_youtube_id',
      'spotify_url',
    };
    return _Section('Utwór', [
      for (final key in song.keys)
        if (!shownElsewhere.contains(key))
          _editableField('songs', song, key, _songLabels[key] ?? key),
      for (final former in details.formerIds)
        _Field(
          'Dawne ID',
          '${former.id}${former.changedAt == null ? '' : ' (do ${former.changedAt})'}',
        ),
    ]);
  }

  Widget _artistSection(String role, DbRow artist, {required bool first}) {
    final row = _withLatinColumn(artist, 'name', 'name_latin');
    return _Section(
      first
          ? 'Wykonawca'
          : role == 'feat'
          ? 'Gościnnie (feat.)'
          : 'Współwykonawca',
      [
        for (final key in row.keys)
          _editableField('artists', row, key, _artistLabels[key] ?? key),
      ],
    );
  }

  Widget _albumSection(SongDetails details) {
    final album = _withLatinColumn(details.album!, 'title', 'title_latin');
    Uri? link(String key, String Function(Object id) url) =>
        album[key] == null ? null : Uri.parse(url(album[key]!));
    final links = {
      'musicbrainz_release_group_id': link(
        'musicbrainz_release_group_id',
        (id) => 'https://musicbrainz.org/release-group/$id',
      ),
      'itunes_collection_id': link(
        'itunes_collection_id',
        (id) => 'https://music.apple.com/album/$id',
      ),
      'deezer_album_id': link(
        'deezer_album_id',
        (id) => 'https://www.deezer.com/album/$id',
      ),
      'spotify_album_id': link(
        'spotify_album_id',
        (id) => 'https://open.spotify.com/album/$id',
      ),
    };
    return _Section('Album', [
      for (final MapEntry(:key, :value) in album.entries)
        if (key == 'artist_id')
          _Field('Wykonawca albumu', details.albumArtist ?? _text(value))
        else
          _editableField(
            'albums',
            album,
            key,
            _albumLabels[key] ?? key,
            link: links[key],
          ),
      for (final cover in details.albumCovers) _coverField(cover),
    ]);
  }

  /// [column] of music.db's [table] [row], with a pencil when the user may correct it.
  Widget _editableField(
    String table,
    DbRow row,
    String column,
    String label, {
    Uri? link,
  }) {
    final value = row[column];
    final kind = _editable[table]?[column];
    final outbox = OutboxScope.maybeOf(context);
    final song = widget.hit.mainSong;
    final id = row['id'];
    if (kind == null || outbox == null || song == null || id is! int) {
      return _Field(label, _shown(kind, value), link: link);
    }
    final correction = outbox.correctionOf(table, id, column, value);
    return _Field(
      label,
      _shown(kind, value) ?? '—',
      link: link,
      correction: correction == null
          ? null
          : '${correction.sent ? 'Wysłano poprawkę' : 'Poprawka czeka na wysłanie'}: '
                '${_shown(kind, correction.newValue) ?? '(puste)'}',
      onEdit: () => _edit(
        outbox,
        song,
        table: table,
        rowId: id,
        column: column,
        label: label,
        kind: kind,
        current: value,
        shown: correction == null ? value : correction.newValue,
      ),
    );
  }

  Future<void> _edit(
    Outbox outbox,
    CatalogSong song, {
    required String table,
    required int rowId,
    required String column,
    required String label,
    required _Kind kind,
    required Object? current,
    required Object? shown,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    Object? value;
    if (kind == _Kind.albumType) {
      final picked = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(label),
          children: [
            for (final MapEntry(:key, value: name) in {
              ..._albumTypes,
              '': 'nie wiadomo',
            }.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(key),
                child: Row(
                  children: [
                    Expanded(child: Text(name)),
                    if (key == '${shown ?? ''}')
                      Icon(Icons.check, color: context.palette.accent),
                  ],
                ),
              ),
          ],
        ),
      );
      if (picked == null) return;
      value = picked.isEmpty ? null : picked;
    } else {
      final text = await showDialog<String>(
        context: context,
        builder: (_) => TextInputDialog(
          title: label,
          hint: kind == _Kind.required ? label : 'Puste — usuń wartość',
          initial: _text(shown) ?? '',
          number: kind == _Kind.number,
        ),
      );
      if (text == null) return;
      final trimmed = text.trim();
      if (trimmed.isEmpty && kind == _Kind.required) {
        messenger.showSnackBar(
          SnackBar(content: Text('„$label” nie może być puste.')),
        );
        return;
      }
      value = trimmed.isEmpty
          ? null
          : kind == _Kind.number
          ? int.tryParse(trimmed)
          : trimmed;
    }
    if (_sameValue(value, shown)) return;
    await outbox.correctField(
      table: table,
      rowId: rowId,
      column: column,
      oldValue: current,
      newValue: value,
      song: song,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _sameValue(value, current) ? 'Poprawka wycofana.' : 'Poprawka trafi do MusicDatabase (Zgłoszenia dla MusicDatabase).',
        ),
      ),
    );
  }

  Widget _coverField(DbRow cover) {
    final size = cover['width'] == null
        ? null
        : '${cover['width']}×${cover['height']}';
    final bytes = cover['bytes'] as int?;
    final url = cover['url'] as String?;
    return _Field(
      'Okładka: ${cover['source']}',
      [
        cover['status'] == 'found' ? 'jest' : 'brak',
        ?size,
        if (bytes != null) '${(bytes / 1024).round()} KB',
        if (cover['checked_at'] != null) 'sprawdzono ${cover['checked_at']}',
        ?url,
        ?cover['path'] as String?,
      ].join(' · '),
      link: url == null ? null : Uri.tryParse(url),
    );
  }

  Widget _linksSection(SongDetails? details) {
    final hit = _hit;
    final mainSong = hit.mainSong;
    final storedVideo = mainSong?.fromMusicDb.youtubeVideoId;
    final spotifyUrl = details?.song['spotify_url'] as String?;
    Uri video(String id) => youTubeWatchUri(id);
    final fromPlayer = widget.track != null;
    return _Section('Linki', [
      if (mainSong != null) ...[
        _youTubeField(
          mainSong.fromMusicDb,
          column: 'youtube_video_id',
          label: 'YouTube (music.db)',
          stored: mainSong.fromMusicDb.youtubeValue,
          removed: hit.mainVideoRemoved && mainSong.userLinks?.video == null,
        ),
        _youTubeField(
          mainSong.fromMusicDb,
          column: 'music_video_youtube_id',
          label: 'Teledysk (music.db)',
          stored: mainSong.fromMusicDb.musicVideoId,
        ),
      ],
      if (mainSong != null)
        _Field(
          'Spotify (music.db)',
          spotifyUrl ?? 'brak',
          link: spotifyUrl == null ? null : Uri.tryParse(spotifyUrl),
        ),
      if (hit.phoneMatch != null && hit.phoneMatch != storedVideo?.trim())
        _Field(
          'YouTube (znaleziony na telefonie)',
          hit.phoneMatch,
          link: video(hit.phoneMatch!),
          fromPlayer: fromPlayer,
        ),
      if (hit.playlistVideoId != null &&
          hit.playlistVideoId != storedVideo?.trim())
        _Field(
          'YouTube (z playlisty)',
          hit.playlistVideoId,
          link: video(hit.playlistVideoId!),
          fromPlayer: fromPlayer,
        ),
      if (hit.spotifyTrackId != null &&
          hit.spotifyTrackId != mainSong?.spotifyTrackId)
        _Field(
          'Spotify (z playlisty)',
          hit.spotifyTrackId,
          link: Uri.https('open.spotify.com', '/track/${hit.spotifyTrackId}'),
        ),
      if (hit.notFoundOnYouTube)
        const _Field('YouTube', 'telefon niedawno szukał i nie znalazł'),
      for (final bad in details?.badVideos ?? const <DbRow>[])
        _Field(
          'YouTube (odrzucony w MusicDatabase)',
          [
            '${bad['video_id']}',
            switch (bad['reason']) {
              'wrong_for_song' => 'zły film dla tego utworu',
              'no_video_for_song' => 'utwór oznaczony jako N/A',
              final reason => '$reason',
            },
            if (bad['marked_at'] != null) '${bad['marked_at']}',
          ].join(' · '),
          link: video('${bad['video_id']}'),
          fromPlayer: fromPlayer,
        ),
    ]);
  }

  /// A YouTube link of music.db's [song] ([column], stored as [stored]), with a pencil to set
  /// another — a field correction like the others, but the phone plays (or opens) the user's
  /// link meanwhile ([CatalogSong.userLinks]).
  Widget _youTubeField(
    CatalogSong song, {
    required String column,
    required String label,
    required String? stored,
    bool removed = false,
  }) {
    final outbox = OutboxScope.maybeOf(context);
    final correction = outbox?.correctionOf('songs', song.id, column, stored);
    final fromPlayer = widget.track != null;
    String shown(Object? value) => switch (value) {
      null || '' => 'brak',
      'N/A' => 'oznaczony jako niedostępny na YouTube (N/A)',
      _ => '$value',
    };
    final newValue = correction?.newValue as String?;
    return _Field(
      label,
      removed ? '$stored — usunięty z YouTube' : shown(stored),
      link: stored == null || stored == 'N/A' ? null : youTubeWatchUri(stored),
      fromPlayer: fromPlayer && column == 'youtube_video_id',
      correction: correction == null
          ? null
          : '${correction.sent ? 'Wysłano poprawkę' : 'Poprawka czeka na wysłanie'}, '
                'telefon już używa: ${shown(newValue)}',
      correctionLink: newValue == null || newValue.isEmpty || newValue == 'N/A'
          ? null
          : youTubeWatchUri(newValue),
      onEdit: outbox == null
          ? null
          : () => _editYouTube(
              outbox,
              song,
              column: column,
              label: label,
              stored: stored,
              shown: correction == null ? stored : newValue,
            ),
    );
  }

  Future<void> _editYouTube(
    Outbox outbox,
    CatalogSong song, {
    required String column,
    required String label,
    required String? stored,
    required String? shown,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final musicVideo = column == 'music_video_youtube_id';
    final text = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: label,
        hint: musicVideo ? 'Link lub ID filmu' : 'Link, ID filmu lub N/A',
        initial: shown == null || shown.isEmpty ? '' : shown,
      ),
    );
    if (text == null) return;
    final value = parseYouTubeLinkInput(text, allowNotOnYouTube: !musicVideo);
    if (value == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('To nie jest link do filmu na YouTube.')),
      );
      return;
    }
    final newValue = value.isEmpty ? null : value;
    if (_sameValue(newValue, shown)) return;
    await outbox.correctField(
      table: 'songs',
      rowId: song.id,
      column: column,
      oldValue: stored,
      newValue: newValue,
      song: song,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _sameValue(newValue, stored) ? 'Wrócono do linku z music.db.' : 'Telefon używa już tego linku; poprawka trafi do MusicDatabase.',
        ),
      ),
    );
  }

  Widget _moodsSection(BuildContext context, SongDetails? details) {
    final id = widget.hit.mainSong?.id;
    final moods = MoodLibraryScope.maybeOf(context);
    final inMoods = id == null || moods == null
        ? const <Mood>[]
        : [
            ...moods.globalMoods,
            ...moods.userMoods,
          ].where((m) => m.songIds.contains(id)).toList();
    final tags = [
      for (final tag in details?.tags ?? const <({String name, String kind})>[])
        if (tag.kind != 'mood') tag,
    ];
    return _Section('Nastroje i tagi', [
      _Chips('Nastroje', [
        for (final mood in inMoods)
          mood.global
              ? '${mood.name} (globalny)'
              : mood.phoneOnly
              ? '${mood.name} (twój, tylko na telefonie)'
              : '${mood.name} (twój)',
      ]),
      _Chips('Tagi (tag.db)', [
        for (final tag in tags)
          tag.kind == 'marker' ? tag.name : '${tag.name} (${tag.kind})',
      ]),
    ]);
  }

  Widget _phoneSection() {
    final hit = _hit;
    final track = widget.track;
    return _Section('Na telefonie', [
      // Empty until a song restored after a restart is played.
      if (track != null && track.source.isNotEmpty)
        track.serverFileId != null
            ? _Field('Odtwarzane z', 'serwera: ${track.source}')
            : track.isStream
            ? _Field(
                'Odtwarzane z',
                'YouTube${track.youtubeVideoId == null ? '' : ': ${track.youtubeVideoId}'}',
                link: track.youtubeVideoId == null
                    ? null
                    : youTubeWatchUri(track.youtubeVideoId!),
                fromPlayer: true,
              )
            : _Field('Odtwarzane z', 'pliku: ${track.source}'),
      if (hit.inMainDatabase)
        _Field('Plik na serwerze (files.db)', hit.serverFile?.path ?? 'brak'),
      if (hit.phoneFiles.isEmpty) const _Field('Pliki', 'brak'),
      for (final file in hit.phoneFiles) ...[
        _Field('Plik', file.filePath),
        _Field(
          'Tagi pliku',
          [
            file.title,
            ?file.artist,
            ?file.album,
            ?file.year?.toString(),
          ].join(' · '),
        ),
        if (file.pending)
          const _Field('MusicDatabase', 'jeszcze go nie ma (do dodania)'),
      ],
    ]);
  }
}

/// The video id in [text] typed as a YouTube link or a bare id; "" for an empty text, "N/A"
/// when [allowNotOnYouTube] and typed so; `null` when it's neither.
String? parseYouTubeLinkInput(String text, {bool allowNotOnYouTube = true}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';
  if (allowNotOnYouTube && trimmed.toUpperCase() == 'N/A') return 'N/A';
  if (_bareVideoId.hasMatch(trimmed)) return trimmed;
  final link = parseYouTubeLink(
    trimmed.contains('://') ? trimmed : 'https://$trimmed',
  );
  return link is YouTubeVideoLink ? link.videoId : null;
}

final _bareVideoId = RegExp(r'^[\w-]{11}$');

/// How "Informacje o utworze" names [column] of music.db's [table], and shows [value] of it.
String fieldLabel(String table, String column) =>
    switch (table) {
      'songs' => _songLabels,
      'artists' => _artistLabels,
      'albums' => _albumLabels,
      _ => const <String, String>{},
    }[column] ??
    column;

String? fieldValue(String table, String column, Object? value) =>
    _shown(_editable[table]?[column], value);

bool _sameValue(Object? a, Object? b) =>
    a == null || b == null ? a == b : '$a' == '$b';

String? _shown(_Kind? kind, Object? value) =>
    kind == _Kind.albumType ? _albumTypes[value] ?? _text(value) : _text(value);

enum _Kind { text, required, number, albumType }

/// [row] with its Latin form column ([latinColumn] of [column], `latin_names.dart`) only where
/// it's of use: next to a name in another alphabet — even before music.db has the column, so
/// the user can already send one — or when it's set; right after [column].
DbRow _withLatinColumn(DbRow row, String column, String latinColumn) {
  final wanted =
      _text(row[latinColumn]) != null ||
      hasNonLatinLetters(row[column] as String?);
  if (wanted == row.containsKey(latinColumn)) return row;
  return {
    for (final MapEntry(:key, :value) in row.entries)
      if (key != latinColumn) ...{
        key: value,
        if (key == column && wanted) latinColumn: row[latinColumn],
      },
  };
}

/// What can be corrected, by music.db table and column. Ids, links, service ids and the old
/// mood columns stay as they are.
const _editable = {
  'songs': {
    'title': _Kind.required,
    'album': _Kind.text,
    'year': _Kind.number,
    'language': _Kind.text,
    'track_number': _Kind.number,
    'disc_number': _Kind.number,
    'title_latin': _Kind.text,
  },
  'artists': {
    'name': _Kind.required,
    'name_latin': _Kind.text,
    'origin': _Kind.text,
    'synonyms': _Kind.text,
  },
  'albums': {
    'title': _Kind.required,
    'title_latin': _Kind.text,
    'year': _Kind.number,
    'type': _Kind.albumType,
  },
};

String? _text(Object? value) => switch (value) {
  null => null,
  final String s when s.trim().isEmpty => null,
  _ => '$value',
};

const _songLabels = {
  'id': 'ID w MusicDatabase',
  'title': 'Tytuł',
  'title_latin': 'Tytuł alfabetem łacińskim',
  'album': 'Album',
  'year': 'Rok',
  'language': 'Język',
  'track_number': 'Numer utworu',
  'disc_number': 'Numer płyty',
};

const _artistLabels = {
  'id': 'ID',
  'name': 'Nazwa',
  'name_latin': 'Nazwa alfabetem łacińskim',
  'origin': 'Pochodzenie',
  'synonyms': 'Inne nazwy',
};

const _albumLabels = {
  'id': 'ID albumu',
  'title': 'Tytuł',
  'title_latin': 'Tytuł alfabetem łacińskim',
  'year': 'Rok',
  'type': 'Rodzaj',
  'musicbrainz_release_group_id': 'MusicBrainz',
  'itunes_collection_id': 'iTunes',
  'deezer_album_id': 'Deezer',
  'spotify_album_id': 'Spotify',
};

const _albumTypes = {
  'album': 'album',
  'ep': 'EP',
  'single': 'singiel',
  'compilation': 'kompilacja',
  'soundtrack': 'ścieżka dźwiękowa',
};

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: AppFontSize.small,
        color: context.palette.textSecondary,
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final child in children)
        if (child is! _Field || child.value != null) child,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: AppFontSize.listTitle,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...shown,
        ],
      ),
    );
  }
}

/// One label and value; a long press copies the value, a tap opens [link], the pencil (shown
/// with [onEdit]) corrects it.
class _Field extends StatelessWidget {
  const _Field(
    this.label,
    this.value, {
    this.link,
    this.onEdit,
    this.correction,
    this.correctionLink,
    this.fromPlayer = false,
  });

  final String label;

  /// Not shown at all when `null`.
  final String? value;
  final Uri? link;
  final VoidCallback? onEdit;

  /// The user's correction waiting for MusicDatabase, under the value.
  final String? correction;

  /// Opened by a tap on [correction].
  final Uri? correctionLink;

  /// [link] is the playing song's video: it opens where the player is, and the player pauses
  /// (like "Otwórz w YouTube" above the card).
  final bool fromPlayer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final messenger = ScaffoldMessenger.of(context);
    final player = fromPlayer ? PlayerScope.of(context) : null;
    return InkWell(
      onTap: link == null ? null : () => _openLink(link!, player: player),
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: value!));
        messenger.showSnackBar(
          const SnackBar(content: Text('Skopiowano do schowka.')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppFontSize.small,
                  color: palette.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value!,
                    style: TextStyle(
                      fontSize: AppFontSize.small,
                      color: link == null ? null : palette.accent,
                    ),
                  ),
                  if (correction != null)
                    GestureDetector(
                      onTap: correctionLink == null
                          ? null
                          : () => _openLink(correctionLink!, player: player),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          correction!,
                          style: TextStyle(
                            fontSize: AppFontSize.small,
                            color: palette.accent,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (onEdit != null)
              InkResponse(
                onTap: onEdit,
                radius: 18,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: palette.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips(this.label, this.names);

  final String label;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppFontSize.small,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          if (names.isEmpty)
            const Text('brak', style: TextStyle(fontSize: AppFontSize.small))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in names)
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: palette.chip,
                      shape: palette.pillShape,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: AppFontSize.small),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// YouTube links in the YouTube app, the rest in the app that claims them or the browser. With
/// [player], the video of the song it's playing: from that moment, with the player paused.
Future<void> _openLink(Uri uri, {PlayerController? player}) async {
  if (uri.host.endsWith('youtube.com')) {
    if (player != null) {
      uri = youTubeUriAt(uri, player.currentPosition);
      if (player.playing) await player.togglePlay();
    }
    await openInYouTube(uri);
    return;
  }
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication)) {
      return;
    }
  } catch (_) {
    // No app claims the link; fall through to the browser.
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
