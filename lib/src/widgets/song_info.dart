import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/audio_quality.dart';
import '../data/combined_search.dart';
import '../data/database_sync.dart';
import '../data/incoming_links.dart';
import '../data/language_codes.dart';
import '../data/latin_names.dart';
import '../data/local_library.dart';
import '../data/moods.dart';
import '../data/outbox.dart';
import '../data/song_catalog.dart';
import '../data/song_details.dart';
import '../data/text_normalizer.dart';
import '../data/youtube_library.dart';
import '../l10n.dart';
import '../playback/player_controller.dart';
import '../playback/youtube_playback.dart';
import '../theme.dart';
import 'common.dart';
import 'song_tile.dart';

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
              Text(
                l10n.songInfoTitle,
                style: const TextStyle(
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
        _Note(l10n.songInfoNotInMusicDatabase)
      else if (details == null)
        _Note(l10n.songInfoReadFailed),
      if (details == null)
        _Section(l10n.songInfoSectionSong, [
          _Field(l10n.songInfoLabelTitle, hit.title),
          _Field(l10n.songInfoSectionArtist, hit.artistLabel),
          _Field(l10n.songInfoLabelAlbum, hit.album),
          _Field(l10n.songInfoLabelYear, hit.year?.toString()),
          if (mainSong != null) ...[
            _Field(
              l10n.songInfoLabelLanguage,
              _shown(_Kind.language, mainSong.language),
            ),
            _Field(l10n.songInfoLabelMusicDatabaseId, '${mainSong.id}'),
          ],
        ])
      else ...[
        _songSection(details),
        for (final a in details.artists)
          _artistSection(
            a.role,
            a.artist,
            song: a.role == 'main' ? details.song : null,
          ),
        if (details.album != null) _albumSection(details),
      ],
      if (mainSong != null) _versionsSection(mainSong),
      _linksSection(details),
      _moodsSection(context, details),
      _phoneSection(),
    ];
  }

  Widget _songSection(SongDetails details) {
    final song = _withLatinColumn(details.song, 'title', 'title_latin');
    const shownElsewhere = {
      'artist_id',
      'covered_artist_id',
      'version_kind',
      'version_label',
      'version_of',
      'album_id',
      'youtube_video_id',
      'music_video_youtube_id',
      'spotify_url',
    };
    return _Section(l10n.songInfoSectionSong, [
      for (final key in song.keys)
        if (key == 'kind')
          _songKindField(song)
        else if (!shownElsewhere.contains(key))
          _editableField('songs', song, key, _songLabels[key] ?? key),
      _coveredArtistField(details),
      if (widget.hit.version case final version?)
        _Field(
          l10n.songInfoVersion,
          [version.kind.label, ?version.label].join(' · '),
        ),
      for (final former in details.formerIds)
        _Field(
          l10n.songInfoFormerId,
          former.changedAt == null
              ? '${former.id}'
              : l10n.songInfoFormerIdUntil(
                  '${former.id}',
                  '${former.changedAt}',
                ),
        ),
    ]);
  }

  /// `songs.covered_artist_id`: whose song this one is a cover of. Corrected like the song's own
  /// artist, with a name — empty when it's no cover of an artist; MusicDatabase finds the artist
  /// or makes one (hand-off `musicdatabase-cover-songs.md`). A traditional song with no artist to
  /// name has only `covered_title`, a field of its own.
  Widget _coveredArtistField(SongDetails details) {
    final song = details.song;
    final outbox = OutboxScope.maybeOf(context);
    final catalogSong = widget.hit.mainSong;
    final songId = song['id'];
    final stored = song['covered_artist_id'];
    final name = details.coveredArtist;
    if (outbox == null ||
        catalogSong == null ||
        songId is! int ||
        !song.containsKey('covered_artist_id')) {
      return _Field(l10n.songInfoCoverOf, name);
    }
    final correction = outbox.correctionOf(
      'songs',
      songId,
      'covered_artist_id',
      stored,
    );
    final shown = correction == null ? name : _text(correction.newValue);
    return _Field(
      l10n.songInfoCoverOf,
      name ?? '—',
      correction: correction == null
          ? null
          : _correctionNote(correction, shown ?? l10n.songInfoEmptyValue),
      onEdit: () async {
        final messenger = ScaffoldMessenger.of(context);
        final text = await showDialog<String>(
          context: context,
          builder: (_) => TextInputDialog(
            title: l10n.songInfoCoverOfTitle,
            hint: l10n.songInfoArtistName,
            helper: l10n.songInfoCoverOfHint,
            initial: shown ?? '',
          ),
        );
        if (text == null || !mounted) return;
        final typed = text.trim();
        // The covered artist typed differently is the same artist: taken back.
        final value = typed.isEmpty
            ? null
            : name != null && _sameArtistName(typed, name)
            ? name
            : typed;
        if (value == null
            ? shown == null
            : shown != null && _sameArtistName(value, shown)) {
          return;
        }
        // MusicDatabase can't store the song's own artist as the covered one.
        if (value != null &&
            details.artists.any(
              (a) =>
                  a.artist['id'] == song['artist_id'] &&
                  _sameArtistName(a.artist['name'], value),
            )) {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.songInfoCoverOfOwnArtist)),
          );
          return;
        }
        await outbox.correctField(
          table: 'songs',
          rowId: songId,
          column: 'covered_artist_id',
          oldValue: stored,
          newValue: value,
          oldAsValue: name,
          song: catalogSong,
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _sameValue(value, name)
                  ? l10n.songInfoCorrectionWithdrawn
                  : l10n.songInfoCorrectionQueued,
            ),
          ),
        );
      },
    );
  }

  /// "Inne wersje": the original and its versions (`songs.version_of`), as song rows to play.
  Widget _versionsSection(CatalogSong song) {
    final catalog = SongCatalogScope.maybeOf(context);
    final versions = catalog?.otherVersionsOf(song) ?? const [];
    if (versions.isEmpty) return const SizedBox.shrink();
    final library = LocalLibraryScope.maybeOf(context);
    final youTube = YouTubeLibraryScope.maybeOf(context);
    SearchHit hitOf(CatalogSong song) {
      final hit = SearchHit.main(song, library?.filesOf(song.id) ?? const []);
      return youTube == null ? hit : withPhoneYouTube(hit, youTube);
    }

    return _Section(l10n.songInfoOtherVersions, [
      // The card is padded already.
      ListTileTheme.merge(
        contentPadding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final version in versions)
              SongTile(
                hit: hitOf(version),
                menuIdPrefix:
                    'Informacje o utworze › Inne wersje › Utwór › Menu (⋮)',
              ),
          ],
        ),
      ),
    ]);
  }

  /// [song] is given for the song's own artist (`songs.artist_id`), the first section.
  Widget _artistSection(String role, DbRow artist, {DbRow? song}) {
    final row = _withLatinColumn(artist, 'name', 'name_latin');
    return _Section(
      song != null
          ? l10n.songInfoSectionArtist
          : role == 'feat'
          ? l10n.songInfoSectionFeaturing
          : l10n.songInfoSectionCoArtist,
      [
        for (final key in row.keys)
          if (key == 'name' && song != null)
            _mainArtistNameField(song, row)
          else
            _editableField('artists', row, key, _artistLabels[key] ?? key),
      ],
    );
  }

  /// The song's own artist. Its pencil asks what's wrong: the song is another artist's — a
  /// `songs.artist_id` correction carrying that artist's name, which changes only this song in
  /// MusicDatabase — or the name is misspelt — `artists.name`, for all the artist's songs. The
  /// first is what's usually meant, so it comes first. Without what the first needs there's no
  /// pencil at all: a rename as the only thing it does once moved all of Paramore's songs to
  /// "David Byrne" (MusicDatabase's hand-off `artist-rename-guard-for-musicdatabaseapp.md`).
  Widget _mainArtistNameField(DbRow song, DbRow artist) {
    final outbox = OutboxScope.maybeOf(context);
    final catalogSong = widget.hit.mainSong;
    final songId = song['id'];
    final artistId = song['artist_id'];
    final name = _text(artist['name']);
    if (outbox == null ||
        catalogSong == null ||
        songId is! int ||
        artistId is! int ||
        name == null) {
      return _Field(_artistLabels['name']!, _text(artist['name']));
    }
    final other = outbox.correctionOf('songs', songId, 'artist_id', artistId);
    final rowId = artist['id'];
    final spelling = rowId is int
        ? outbox.correctionOf('artists', rowId, 'name', name)
        : null;
    final notes = [
      // A sent one taken back names the same artist again: nothing to show.
      if (other != null && !_sameArtistName(other.newValue, name))
        other.sent
            ? l10n.songInfoOtherArtistSent('${other.newValue}')
            : l10n.songInfoOtherArtistWaiting('${other.newValue}'),
      if (spelling != null)
        spelling.sent
            ? l10n.songInfoSpellingSent(
                _text(spelling.newValue) ?? l10n.songInfoEmptyValue,
              )
            : l10n.songInfoSpellingWaiting(
                _text(spelling.newValue) ?? l10n.songInfoEmptyValue,
              ),
    ];
    return _Field(
      _artistLabels['name']!,
      name,
      correction: notes.isEmpty ? null : notes.join('\n'),
      onEdit: () async {
        final choice = await showDialog<bool>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(name),
            children: [
              _ChoiceOption(
                l10n.songInfoOtherArtistOption,
                l10n.songInfoOtherArtistOptionNote,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              if (rowId is int)
                _ChoiceOption(
                  l10n.songInfoSpellingOption,
                  l10n.songInfoSpellingOptionNote,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
            ],
          ),
        );
        if (choice == null || !mounted) return;
        if (choice) {
          await _proposeOtherArtist(
            outbox,
            catalogSong,
            songId: songId,
            artistId: artistId,
            name: name,
            shown: other?.newValue as String? ?? name,
          );
        } else if (rowId is int) {
          await _edit(
            outbox,
            catalogSong,
            table: 'artists',
            rowId: rowId,
            column: 'name',
            label: l10n.songInfoArtistSpelling,
            kind: _Kind.required,
            current: name,
            shown: spelling == null ? name : spelling.newValue,
            asOtherArtist: (typed) => _saveOtherArtist(
              outbox,
              catalogSong,
              songId: songId,
              artistId: artistId,
              name: name,
              typed: typed,
            ),
          );
        }
      },
    );
  }

  /// Sends the user's artist for the song as a `songs.artist_id` correction: [artistId] is the
  /// song's artist in music.db, [name] its name, the new value the name typed. MusicDatabase
  /// finds the artist of that name (or makes one) and moves only this song to it.
  Future<void> _proposeOtherArtist(
    Outbox outbox,
    CatalogSong song, {
    required int songId,
    required int artistId,
    required String name,
    required String shown,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: l10n.songInfoOtherArtistTitle,
        hint: l10n.songInfoArtistName,
        initial: shown,
      ),
    );
    if (text == null) return;
    final typed = text.trim();
    if (typed.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.songInfoArtistNameEmpty)),
      );
      return;
    }
    if (_sameArtistName(typed, shown) || !mounted) return;
    await _saveOtherArtist(
      outbox,
      song,
      songId: songId,
      artistId: artistId,
      name: name,
      typed: typed,
    );
  }

  Future<void> _saveOtherArtist(
    Outbox outbox,
    CatalogSong song, {
    required int songId,
    required int artistId,
    required String name,
    required String typed,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    // The same artist typed differently is no other artist: taken back.
    final back = _sameArtistName(typed, name);
    await outbox.correctField(
      table: 'songs',
      rowId: songId,
      column: 'artist_id',
      oldValue: artistId,
      newValue: back ? name : typed,
      oldAsValue: name,
      song: song,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          back
              ? l10n.songInfoCorrectionWithdrawn
              : l10n.songInfoOtherArtistQueued,
        ),
      ),
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
    return _Section(l10n.songInfoLabelAlbum, [
      for (final MapEntry(:key, :value) in album.entries)
        if (key == 'artist_id')
          _Field(l10n.songInfoAlbumArtist, details.albumArtist ?? _text(value))
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
          : _correctionNote(
              correction,
              _shown(kind, correction.newValue) ?? l10n.songInfoEmptyValue,
            ),
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

  /// `songs.kind` as a switch: the row is a whole album in one recording, or a song (hand-off
  /// `musicdatabase-song-kind.md`). Goes out as a field correction like the others; only
  /// `full_album` or empty is accepted by MusicDatabase.
  Widget _songKindField(DbRow row) {
    final stored = row['kind'];
    final outbox = OutboxScope.maybeOf(context);
    final song = widget.hit.mainSong;
    final id = row['id'];
    final correction = outbox == null || id is! int
        ? null
        : outbox.correctionOf('songs', id, 'kind', stored);
    final marked =
        SongKind.of(correction == null ? stored : correction.newValue) ==
        SongKind.fullAlbum;
    return _Field(
      l10n.songInfoIsFullAlbum,
      fieldValue('songs', 'kind', stored),
      correction: correction == null
          ? null
          : _correctionNote(
              correction,
              '${fieldValue('songs', 'kind', correction.newValue)}',
            ),
      trailing: outbox == null || song == null || id is! int
          ? null
          : Switch(
              value: marked,
              onChanged: (on) async {
                final messenger = ScaffoldMessenger.of(context);
                // Switched off, back to music.db's value unless that's the full album.
                final value = on
                    ? SongKind.fullAlbumValue
                    : SongKind.of(stored) == SongKind.fullAlbum
                    ? null
                    : stored;
                await outbox.correctField(
                  table: 'songs',
                  rowId: id,
                  column: 'kind',
                  oldValue: stored,
                  newValue: value,
                  song: song,
                );
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      _sameValue(value, stored)
                          ? l10n.songInfoCorrectionWithdrawn
                          : l10n.songInfoCorrectionQueued,
                    ),
                  ),
                );
              },
            ),
    );
  }

  /// An `artists.name` correction from [name] to [typed] that doesn't look like a spelling fix:
  /// `true` renames the artist in all its songs, `false` makes [typed] the artist of only this
  /// song (offered when [asOtherArtist] is given — the song's own artist), `null` cancels.
  Future<bool?> _confirmRename(
    String name,
    String typed,
    Future<void> Function(String typed)? asOtherArtist,
  ) => showDialog<bool>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(
        asOtherArtist == null
            ? l10n.songInfoNotSpellingFix
            : l10n.songInfoNotSpellingFixOtherArtist,
      ),
      children: [
        if (asOtherArtist != null)
          _ChoiceOption(
            l10n.songInfoOnlyThisSong,
            l10n.songInfoOnlyThisSongNote(typed),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        _ChoiceOption(
          asOtherArtist == null
              ? l10n.songInfoRenameEverywhere
              : l10n.songInfoNoRenameEverywhere,
          l10n.songInfoRenameEverywhereNote(name, typed),
          onPressed: () => Navigator.of(context).pop(true),
        ),
        if (asOtherArtist == null)
          _ChoiceOption(
            l10n.commonCancel,
            l10n.songInfoNameUnchanged,
            onPressed: () => Navigator.of(context).pop(),
          ),
      ],
    ),
  );

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
    Future<void> Function(String typed)? asOtherArtist,
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
              '': l10n.songInfoUnknown,
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
          hint: kind == _Kind.required ? label : l10n.songInfoEmptyHint,
          initial: _shown(kind, shown) ?? '',
          number: kind == _Kind.number,
        ),
      );
      if (text == null) return;
      final trimmed = text.trim();
      if (trimmed.isEmpty && kind == _Kind.required) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.songInfoFieldEmpty(label))),
        );
        return;
      }
      value = trimmed.isEmpty
          ? null
          : switch (kind) {
              _Kind.number => int.tryParse(trimmed),
              _Kind.language => languageValueOfTyped(trimmed),
              _ => trimmed,
            };
    }
    if (kind == _Kind.language) shown = languageValue(shown as String?);
    if (_sameValue(value, shown)) return;
    if (table == 'artists' &&
        column == 'name' &&
        value is String &&
        current is String &&
        !nameResembles(current, value)) {
      final rename = await _confirmRename(current, value, asOtherArtist);
      if (rename == null || !mounted) return;
      if (!rename) {
        await asOtherArtist!(value);
        return;
      }
    }
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
          _sameValue(value, current)
              ? l10n.songInfoCorrectionWithdrawn
              : l10n.songInfoCorrectionQueued,
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
      l10n.songInfoCover('${cover['source']}'),
      [
        cover['status'] == 'found'
            ? l10n.songInfoCoverFound
            : l10n.songInfoNone,
        ?size,
        if (bytes != null) '${(bytes / 1024).round()} KB',
        if (cover['checked_at'] != null)
          l10n.songInfoCoverChecked('${cover['checked_at']}'),
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
    return _Section(l10n.songInfoSectionLinks, [
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
          label: l10n.songInfoMusicVideoMusicDb,
          stored: mainSong.fromMusicDb.musicVideoId,
        ),
      ],
      if (mainSong != null)
        _Field(
          'Spotify (music.db)',
          spotifyUrl ?? l10n.songInfoNone,
          link: spotifyUrl == null ? null : Uri.tryParse(spotifyUrl),
        ),
      if (hit.phoneMatch != null && hit.phoneMatch != storedVideo?.trim())
        _Field(
          l10n.songInfoYouTubeFoundOnPhone,
          hit.phoneMatch,
          link: video(hit.phoneMatch!),
          fromPlayer: fromPlayer,
        ),
      if (hit.playlistVideoId != null &&
          hit.playlistVideoId != storedVideo?.trim())
        _Field(
          l10n.songInfoYouTubeFromPlaylist,
          hit.playlistVideoId,
          link: video(hit.playlistVideoId!),
          fromPlayer: fromPlayer,
        ),
      if (hit.spotifyTrackId != null &&
          hit.spotifyTrackId != mainSong?.spotifyTrackId)
        _Field(
          l10n.songInfoSpotifyFromPlaylist,
          hit.spotifyTrackId,
          link: Uri.https('open.spotify.com', '/track/${hit.spotifyTrackId}'),
        ),
      if (hit.notFoundOnYouTube)
        _Field('YouTube', l10n.songInfoYouTubeNotFound),
      for (final other in details?.additionalVideos ?? const <DbRow>[])
        _Field(
          l10n.songInfoYouTubeOtherRelease,
          [
            '${other['video_id']}',
            switch (other['source']) {
              'folder_playlist' => l10n.songInfoFromFolderPlaylist,
              'song_merge' => l10n.songInfoFromSongMerge,
              final source => '$source',
            },
            if (other['added_at'] != null) '${other['added_at']}',
          ].join(' · '),
          link: video('${other['video_id']}'),
          fromPlayer: fromPlayer,
        ),
      for (final bad in details?.badVideos ?? const <DbRow>[])
        _Field(
          l10n.songInfoYouTubeRejected,
          [
            '${bad['video_id']}',
            switch (bad['reason']) {
              'wrong_for_song' => l10n.songInfoWrongVideo,
              'no_video_for_song' => l10n.songInfoMarkedNA,
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
      null || '' => l10n.songInfoNone,
      'N/A' => l10n.songInfoNotOnYouTube,
      _ => '$value',
    };
    final newValue = correction?.newValue as String?;
    return _Field(
      label,
      removed ? l10n.songInfoRemovedFromYouTube('$stored') : shown(stored),
      link: stored == null || stored == 'N/A' ? null : youTubeWatchUri(stored),
      fromPlayer: fromPlayer && column == 'youtube_video_id',
      correction: correction == null
          ? null
          : correction.sent
          ? l10n.songInfoLinkCorrectionSent(shown(newValue))
          : l10n.songInfoLinkCorrectionWaiting(shown(newValue)),
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
        hint: musicVideo
            ? l10n.songInfoVideoLinkHint
            : l10n.songInfoVideoLinkOrNAHint,
        initial: shown == null || shown.isEmpty ? '' : shown,
      ),
    );
    if (text == null) return;
    final value = parseYouTubeLinkInput(text, allowNotOnYouTube: !musicVideo);
    if (value == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.songInfoNotYouTubeLink)),
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
          _sameValue(newValue, stored)
              ? l10n.songInfoBackToMusicDbLink
              : l10n.songInfoLinkInUse,
        ),
      ),
    );
  }

  Widget _moodsSection(BuildContext context, SongDetails? details) {
    final moods = MoodLibraryScope.maybeOf(context);
    final inMoods = moods == null
        ? const <Mood>[]
        : [
            ...moods.globalMoods,
            ...moods.userMoods,
          ].where((m) => m.has(widget.hit)).toList();
    final tags = [
      for (final tag in details?.tags ?? const <({String name, String kind})>[])
        if (tag.kind != 'mood') tag,
    ];
    return _Section(l10n.songInfoSectionMoodsAndTags, [
      _Chips(l10n.songInfoMoods, [
        for (final mood in inMoods)
          mood.global
              ? l10n.songInfoMoodGlobal(mood.name)
              : mood.phoneOnly
              ? l10n.songInfoMoodOwnPhoneOnly(mood.name)
              : l10n.songInfoMoodOwn(mood.name),
      ]),
      _Chips(l10n.songInfoTags, [
        for (final tag in tags)
          tag.kind == 'marker' ? tag.name : '${tag.name} (${tag.kind})',
      ]),
    ]);
  }

  Widget _phoneSection() {
    final hit = _hit;
    final track = widget.track;
    return _Section(l10n.songInfoSectionPhone, [
      // Empty until a song restored after a restart is played.
      if (track != null && track.source.isNotEmpty)
        track.serverFileId != null
            ? _Field(
                l10n.songInfoPlayedFrom,
                l10n.songInfoFromServer(track.source),
              )
            : track.isStream
            ? _Field(
                l10n.songInfoPlayedFrom,
                'YouTube${track.youtubeVideoId == null ? '' : ': ${track.youtubeVideoId}'}',
                link: track.youtubeVideoId == null
                    ? null
                    : youTubeWatchUri(track.youtubeVideoId!),
                fromPlayer: true,
              )
            : _Field(
                l10n.songInfoPlayedFrom,
                l10n.songInfoFromFile(track.source),
              ),
      if (track != null && track.source.isNotEmpty)
        _Field(l10n.songInfoQuality, _playingQuality(track, hit)),
      if (track == null && hit.youtubeVideoId != null)
        if (YouTubeLibraryScope.maybeOf(context)
                ?.cachedFileOf(hit.youtubeVideoId!)
            case final copy?)
          _Field(
            l10n.songInfoYouTubeCopy,
            fileQuality(copy.path, fromYouTube: true),
          ),
      if (hit.inMainDatabase)
        _Field(
          l10n.songInfoServerFile,
          hit.serverFile?.path ?? l10n.songInfoNone,
        ),
      if (hit.phoneFiles.isEmpty) _Field(l10n.songInfoFiles, l10n.songInfoNone),
      for (final file in hit.phoneFiles) ...[
        _Field(l10n.songInfoFile, file.filePath),
        _Field(l10n.songInfoFormat, fileQuality(file.filePath)),
        _Field(
          l10n.songInfoFileTags,
          [
            file.title,
            ?file.artist,
            ?file.album,
            ?file.year?.toString(),
          ].join(' · '),
        ),
        if (file.pending)
          _Field('MusicDatabase', l10n.songInfoNotYetInMusicDatabase),
      ],
    ]);
  }

  /// "Jakość" of what the player plays: the YouTube stream's own format and bitrate, or a file's
  /// format with its average bitrate (its size over the player's length); a server stream only
  /// by its file's format.
  String _playingQuality(NowPlaying track, SearchHit hit) {
    if (track.streamQuality case final quality?) return quality;
    if (track.isStream) {
      return fileQuality(hit.serverFile?.path ?? Uri.parse(track.source).path);
    }
    int? size;
    try {
      size = File(track.source).lengthSync();
    } on FileSystemException catch (e) {
      debugPrint('Reading the size of the playing file failed: $e');
    }
    return fileQuality(
      track.source,
      sizeBytes: size,
      duration: PlayerScope.maybeOf(context)?.duration,
      fromYouTube: track.youtubeVideoId != null,
    );
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

/// Names MusicDatabase would take for one artist (its `normalize()`).
bool _sameArtistName(Object? a, Object? b) =>
    normalizeForSearch('${a ?? ''}') == normalizeForSearch('${b ?? ''}');

bool _sameValue(Object? a, Object? b) =>
    a == null || b == null ? a == b : '$a' == '$b';

String? _shown(_Kind? kind, Object? value) => switch (kind) {
  _Kind.albumType => _albumTypes[value] ?? _text(value),
  // A value the phone doesn't know yet counts as a song (SongKind.of), but is shown as it is.
  _Kind.songKind =>
    SongKind.of(value) == SongKind.fullAlbum
        ? l10n.songInfoYes
        : _text(value) == null
        ? l10n.songInfoNo
        : l10n.songInfoNoWithValue('$value'),
  _Kind.language => _text(value) == null ? null : languageNames('$value'),
  _ => _text(value),
};

/// [_Kind.language]: music.db's ISO 639-3 codes, shown and typed as names (`language_codes.dart`).
enum _Kind { text, required, number, albumType, songKind, language }

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
    'language': _Kind.language,
    'genre': _Kind.text,
    'kind': _Kind.songKind,
    'track_number': _Kind.number,
    'disc_number': _Kind.number,
    'title_latin': _Kind.text,
    'covered_title': _Kind.text,
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

Map<String, String> get _songLabels => {
  'id': l10n.songInfoLabelMusicDatabaseId,
  'artist_id': l10n.songInfoLabelSongArtist,
  'covered_artist_id': l10n.songInfoCoverOf,
  'title': l10n.songInfoLabelTitle,
  'title_latin': l10n.songInfoLabelTitleLatin,
  'covered_title': l10n.songInfoLabelCoveredTitle,
  'album': l10n.songInfoLabelAlbum,
  'year': l10n.songInfoLabelYear,
  'language': l10n.songInfoLabelLanguage,
  'genre': l10n.songInfoLabelGenre,
  'kind': l10n.songInfoLabelFullAlbum,
  'track_number': l10n.songInfoLabelTrackNumber,
  'disc_number': l10n.songInfoLabelDiscNumber,
};

Map<String, String> get _artistLabels => {
  'id': 'ID',
  'name': l10n.songInfoLabelName,
  'name_latin': l10n.songInfoLabelNameLatin,
  'origin': l10n.songInfoLabelOrigin,
  'synonyms': l10n.songInfoLabelSynonyms,
};

Map<String, String> get _albumLabels => {
  'id': l10n.songInfoLabelAlbumId,
  'title': l10n.songInfoLabelTitle,
  'title_latin': l10n.songInfoLabelTitleLatin,
  'year': l10n.songInfoLabelYear,
  'type': l10n.songInfoLabelAlbumType,
  'musicbrainz_release_group_id': 'MusicBrainz',
  'itunes_collection_id': 'iTunes',
  'deezer_album_id': 'Deezer',
  'spotify_album_id': 'Spotify',
};

Map<String, String> get _albumTypes => {
  'album': l10n.songInfoAlbumTypeAlbum,
  'ep': l10n.songInfoAlbumTypeEp,
  'single': l10n.songInfoAlbumTypeSingle,
  'compilation': l10n.songInfoAlbumTypeCompilation,
  'soundtrack': l10n.songInfoAlbumTypeSoundtrack,
};

/// A correction of a field waiting for MusicDatabase or sent, with the value it gives.
String _correctionNote(FieldCorrection correction, String value) =>
    correction.sent
    ? l10n.songInfoCorrectionSent(value)
    : l10n.songInfoCorrectionWaiting(value);

/// An option of a [SimpleDialog] with a line saying what it does.
class _ChoiceOption extends StatelessWidget {
  const _ChoiceOption(this.title, this.subtitle, {required this.onPressed});

  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SimpleDialogOption(
    onPressed: onPressed,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: AppFontSize.small,
            color: context.palette.textSecondary,
          ),
        ),
      ],
    ),
  );
}

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
    this.trailing,
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

  /// In place of the pencil (e.g. a switch).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final messenger = ScaffoldMessenger.of(context);
    final player = fromPlayer ? PlayerScope.of(context) : null;
    return InkWell(
      onTap: link == null ? null : () => _openLink(link!, player: player),
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: value!));
        messenger.showSnackBar(SnackBar(content: Text(l10n.songInfoCopied)));
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
            ?trailing,
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
            Text(
              l10n.songInfoNone,
              style: const TextStyle(fontSize: AppFontSize.small),
            )
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
