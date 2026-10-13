import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/combined_search.dart';
import '../data/database_sync.dart';
import '../data/moods.dart';
import '../data/song_details.dart';
import '../data/youtube_library.dart';
import '../playback/player_controller.dart';
import '../playback/youtube_playback.dart';
import '../theme.dart';

/// "Informacje o utworze" under the full player: everything music.db, tag.db, the moods and the
/// phone know about [hit] — for now all of it, to be trimmed once it's clear what's worth showing
/// (user's request).
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
    final song = details.song;
    const shownElsewhere = {
      'artist_id',
      'album_id',
      'youtube_video_id',
      'spotify_url',
    };
    return _Section('Utwór', [
      for (final MapEntry(:key, :value) in song.entries)
        if (!shownElsewhere.contains(key))
          _Field(_songLabels[key] ?? key, _text(value)),
      for (final former in details.formerIds)
        _Field(
          'Dawne ID',
          '${former.id}${former.changedAt == null ? '' : ' (do ${former.changedAt})'}',
        ),
    ]);
  }

  Widget _artistSection(String role, DbRow artist, {required bool first}) =>
      _Section(
        first
            ? 'Wykonawca'
            : role == 'feat'
            ? 'Gościnnie (feat.)'
            : 'Współwykonawca',
        [
          for (final MapEntry(:key, :value) in artist.entries)
            _Field(_artistLabels[key] ?? key, _text(value)),
        ],
      );

  Widget _albumSection(SongDetails details) {
    final album = details.album!;
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
        else if (key == 'type')
          _Field('Rodzaj', _albumTypes[value] ?? _text(value))
        else
          _Field(_albumLabels[key] ?? key, _text(value), link: links[key]),
      for (final cover in details.albumCovers) _coverField(cover),
    ]);
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
    final storedVideo = details?.song['youtube_video_id'] as String?;
    final spotifyUrl = details?.song['spotify_url'] as String?;
    Uri video(String id) => youTubeWatchUri(id);
    return _Section('Linki', [
      if (mainSong != null)
        switch (storedVideo?.trim() ?? mainSong.youtubeVideoId) {
          null || '' => const _Field('YouTube (music.db)', 'brak'),
          'N/A' => const _Field(
            'YouTube (music.db)',
            'oznaczony jako niedostępny na YouTube (N/A)',
          ),
          final id => _Field(
            'YouTube (music.db)',
            hit.mainVideoRemoved ? '$id — usunięty z YouTube' : id,
            link: video(id),
          ),
        },
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
        ),
      if (hit.playlistVideoId != null &&
          hit.playlistVideoId != storedVideo?.trim())
        _Field(
          'YouTube (z playlisty)',
          hit.playlistVideoId,
          link: video(hit.playlistVideoId!),
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
    ]);
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
        track.isStream
            ? _Field(
                'Odtwarzane z',
                'YouTube${track.youtubeVideoId == null ? '' : ': ${track.youtubeVideoId}'}',
                link: track.youtubeVideoId == null
                    ? null
                    : youTubeWatchUri(track.youtubeVideoId!),
              )
            : _Field('Odtwarzane z', 'pliku: ${track.source}'),
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

String? _text(Object? value) => switch (value) {
  null => null,
  final String s when s.trim().isEmpty => null,
  _ => '$value',
};

const _songLabels = {
  'id': 'ID w MusicDatabase',
  'title': 'Tytuł',
  'album': 'Album',
  'year': 'Rok',
  'language': 'Język',
  'track_number': 'Numer utworu',
  'disc_number': 'Numer płyty',
};

const _artistLabels = {
  'id': 'ID',
  'name': 'Nazwa',
  'origin': 'Pochodzenie',
  'synonyms': 'Inne nazwy',
};

const _albumLabels = {
  'id': 'ID albumu',
  'title': 'Tytuł',
  'year': 'Rok',
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

/// One label and value; a long press copies the value, a tap opens [link].
class _Field extends StatelessWidget {
  const _Field(this.label, this.value, {this.link});

  final String label;

  /// Not shown at all when `null`.
  final String? value;
  final Uri? link;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final messenger = ScaffoldMessenger.of(context);
    return InkWell(
      onTap: link == null ? null : () => _openLink(link!),
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
              child: Text(
                value!,
                style: TextStyle(
                  fontSize: AppFontSize.small,
                  color: link == null ? null : palette.accent,
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

/// YouTube links in the YouTube app, the rest in the app that claims them or the browser.
Future<void> _openLink(Uri uri) async {
  if (uri.host.endsWith('youtube.com')) {
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
