import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database_sync.dart';
import 'latin_names.dart';
import 'text_normalizer.dart';
import 'youtube_matcher.dart';

/// What song search can look at, chosen with the filter icon on the Wyszukaj tab.
enum SearchField {
  title('Tytuł'),

  /// Main and additional (`additional_song_artists`) artists, including their other names
  /// (`artists.synonyms`, e.g. channel names).
  artist('Wykonawca'),
  album('Album'),
  year('Rok'),
  language('Język'),

  /// `artists.origin` of all the song's artists ("Kraj - Region - Miasto").
  origin('Pochodzenie wykonawcy'),

  /// The names of the moods the song is in (global and the user's own; see
  /// [SongCatalog.setMoodNames]), so typing a mood lists its songs.
  mood('Nastrój');

  const SearchField(this.label);

  final String label;

  static const defaults = {title, artist, album, mood};
}

/// How well a (normalized) title matches the (normalized) query, lower is better: exact title,
/// then title starting with the query, then title containing it, then anything else (the query
/// matched other fields). Shared by MusicDatabase and phone results so they sort the same way.
int titleMatchRank(String normalizedTitle, String normalizedQuery) {
  if (normalizedTitle == normalizedQuery) return 0;
  if (normalizedTitle.startsWith(normalizedQuery)) return 1;
  if (normalizedTitle.contains(normalizedQuery)) return 2;
  return 3;
}

/// What MusicDatabase knows about a song on YouTube (`songs.youtube_video_id`).
enum YouTubeLink {
  /// A video id is stored.
  linked,

  /// Nothing stored — the song may still be found by searching YouTube.
  unknown,

  /// Marked by hand as not on YouTube at all (MusicDatabase's `NO_VIDEO_SENTINEL`, "N/A").
  notOnYouTube,

  /// Not stored, and the phone searched YouTube lately without finding it
  /// (`YouTubeLibrary.notFoundSong` / `notFoundTrack`); a tap searches again.
  notFound,
}

/// One row of MusicDatabase's `songs` table, with its artists already joined in.
class CatalogSong {
  CatalogSong({
    required this.id,
    required this.title,
    required this.artistLabel,
    this.album,
    this.year,
    this.language,
    String? youtubeVideoId,
    this.spotifyTrackId,
    MatchTarget? youTubeTarget,
    List<String> artistNames = const [],
    List<String> origins = const [],
    List<String> synonyms = const [],
    String? titleLatin,
    String? albumLatin,
    this.artistLatin,
  }) : titleLatin = latinFormOf(title, titleLatin),
       albumLatin = latinFormOf(album, albumLatin),
       youTubeTarget =
           youTubeTarget ??
           MatchTarget(title: title, mainArtists: [MatchArtist(artistLabel)]),
       youtubeVideoId = const {null, '', 'N/A'}.contains(youtubeVideoId)
           ? null
           : youtubeVideoId,
       youTube = switch (youtubeVideoId) {
         null || '' => YouTubeLink.unknown,
         'N/A' => YouTubeLink.notOnYouTube,
         _ => YouTubeLink.linked,
       },
       _normalizedTitle = normalizeForSearch(title),
       _normalizedArtists = {
         normalizeForSearch(artistLabel),
         for (final name in [...artistNames, ...synonyms])
           normalizeForSearch(name),
       },
       _fieldTexts = [
         for (final field in SearchField.values)
           normalizeForSearch(switch (field) {
             SearchField.title => [title, ?titleLatin].join(' '),
             SearchField.artist => [
               if (artistNames.isEmpty) artistLabel else ...artistNames,
               ...synonyms,
               ?artistLatin,
             ].join(' '),
             SearchField.album =>
               album == null ? null : [album, ?albumLatin].join(' '),
             SearchField.year => year?.toString(),
             // "Unknown" is MusicDatabase's placeholder, not a language to find songs by.
             SearchField.language => language == 'Unknown' ? null : language,
             SearchField.origin => origins.join(' '),
             // Moods change while the song doesn't: SongCatalog adds them when searching.
             SearchField.mood => null,
           }),
       ];

  final int id;
  final String title;

  /// Main artist(s), then featured ones: "A, B feat. C".
  final String artistLabel;
  final String? album;

  /// The Latin form of [title] (`songs.title_latin`), when the title is in another alphabet.
  final String? titleLatin;

  /// [artistLabel] with each artist's Latin form (`artists.name_latin`, else a Latin synonym),
  /// when some artist is in another alphabet and all of them have one.
  final String? artistLatin;

  /// The Latin form of [album] (`albums.title_latin` of `songs.album_id`).
  final String? albumLatin;
  final int? year;
  final String? language;

  /// Set only when [youTube] is [YouTubeLink.linked].
  final String? youtubeVideoId;

  /// The song's Spotify track, when MusicDatabase's `spotify_url` (set by hand) is a track page —
  /// it may also be an album page, which isn't the song.
  final String? spotifyTrackId;
  final YouTubeLink youTube;

  /// What to look for when the phone searches YouTube for this song itself.
  final MatchTarget youTubeTarget;

  final String _normalizedTitle;

  /// Every name the song's artists go by (label, each artist, synonyms), normalized — for
  /// matching a file's "artist" against this song in [SongCatalog.findExact].
  final Set<String> _normalizedArtists;

  /// Normalized text of each [SearchField], indexed by `SearchField.index`.
  final List<String> _fieldTexts;

  String _textFor(Set<SearchField> fields) => [
    for (final field in SearchField.values)
      if (fields.contains(field) && _fieldTexts[field.index].isNotEmpty)
        _fieldTexts[field.index],
  ].join(' ');
}

enum CatalogStatus { notLoaded, loading, ready, noDatabase, error }

/// Read-only, in-memory copy of the songs in the downloaded `music.db`, for search.
///
/// The whole table is loaded once (a few thousand rows) and filtered in Dart, which keeps every
/// keystroke cheap on the old test phone and lets search use the same normalization as
/// MusicDatabase instead of SQLite's ASCII-only `LIKE`. The file is opened read-only and closed
/// right after reading, so [DatabaseSync] can swap it at any time; a finished download triggers
/// a reload.
/// YouTube videos MusicDatabase found bad (music.db's `bad_youtube_videos`, its handoff
/// `bad-videos-for-musicdatabaseapp.md`): [everySong] are removed or don't play (treated like a
/// video YouTube removed), [forSong] are wrong for that `songs.id` only.
class BadVideos {
  const BadVideos({this.everySong = const {}, this.forSong = const {}});

  static const none = BadVideos();

  final Set<String> everySong;
  final Map<int, Set<String>> forSong;

  bool isWrongFor(int songId, String videoId) =>
      forSong[songId]?.contains(videoId) ?? false;
}

class SongCatalog extends ChangeNotifier {
  SongCatalog(this._sync, {this.factoryOverride}) {
    _sync.addListener(_onSyncChanged);
    _loadSearchFields();
  }

  static const _searchFieldsKey = 'search.fields';

  final DatabaseSync _sync;

  /// SQLite implementation to use instead of sqflite's global `databaseFactory` (which is looked
  /// up only when reading, so tests can also swap the global one).
  final DatabaseFactory? factoryOverride;

  CatalogStatus _status = CatalogStatus.notLoaded;
  List<CatalogSong> _songs = const [];
  DateTime? _loadedSyncTime;
  Future<void>? _loading;

  Set<SearchField> _searchFields = SearchField.defaults;

  /// Each song's searchable text for [_searchFields], rebuilt only when the fields, the songs
  /// or the moods change rather than on every keystroke.
  List<String>? _searchTexts;

  String Function(int songId)? _moodNames;

  /// Where [SearchField.mood] gets the names of the moods a song is in.
  void setMoodNames(String Function(int songId) moodNames) {
    _moodNames = moodNames;
    _searchTexts = null;
  }

  /// A mood was made, renamed or got other songs: search sees it from the next keystroke.
  void moodsChanged() => _searchTexts = null;

  CatalogStatus get status => _status;

  BadVideos _badVideos = BadVideos.none;

  /// Videos MusicDatabase found bad (`bad_youtube_videos`).
  BadVideos get badVideos => _badVideos;

  /// When the `music.db` now loaded was downloaded (`DatabaseSync.lastSync` at load time).
  DateTime? get loadedSyncTime => _loadedSyncTime;
  int get songCount => _songs.length;

  /// Fields the search looks at; never empty.
  Set<SearchField> get searchFields => _searchFields;

  Future<void> _loadSearchFields() async {
    try {
      final stored = (await SharedPreferences.getInstance()).getStringList(
        _searchFieldsKey,
      );
      final fields = {
        for (final name in stored ?? const <String>[])
          ...SearchField.values.where((f) => f.name == name),
      };
      // Saved before moods could be searched, unchanged from the defaults then.
      if (setEquals(fields, const {
        SearchField.title,
        SearchField.artist,
        SearchField.album,
      })) {
        fields.add(SearchField.mood);
      }
      if (fields.isNotEmpty) {
        _searchFields = fields;
        _searchTexts = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Loading search fields failed: $e');
    }
  }

  /// Changes which fields search looks at; an empty set is ignored (search needs at least one).
  Future<void> setSearchFields(Set<SearchField> fields) async {
    if (fields.isEmpty) return;
    _searchFields = Set.unmodifiable(fields);
    _searchTexts = null;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setStringList(
      _searchFieldsKey,
      [for (final f in fields) f.name],
    );
  }

  /// Loads the catalog unless it's already loaded or loading.
  Future<void> ensureLoaded() {
    if (_status == CatalogStatus.ready || _status == CatalogStatus.noDatabase) {
      return Future.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    _status = CatalogStatus.loading;
    notifyListeners();
    try {
      final syncTime = _sync.lastSync;
      final file = await _sync.localFile('music.db');
      if (!await file.exists()) {
        _songs = const [];
        _badVideos = BadVideos.none;
        _status = CatalogStatus.noDatabase;
      } else {
        _songs = await _readSongs(file);
        _badVideos = await _readBadVideos(file);
        _status = CatalogStatus.ready;
      }
      _loadedSyncTime = syncTime;
    } catch (e) {
      debugPrint('Loading music.db failed: $e');
      _songs = const [];
      _badVideos = BadVideos.none;
      _status = CatalogStatus.error;
    } finally {
      _searchTexts = null;
      _byTitle = null;
      _byYouTubeId = null;
      _byId = null;
      _loading = null;
      notifyListeners();
    }
  }

  void _onSyncChanged() {
    final loadedBefore =
        _status == CatalogStatus.ready ||
        _status == CatalogStatus.noDatabase ||
        _status == CatalogStatus.error;
    if (loadedBefore &&
        _sync.lastSync != _loadedSyncTime &&
        !_sync.downloading) {
      _loading ??= _load();
    }
  }

  Future<List<CatalogSong>> _readSongs(File file) async {
    final db = await (factoryOverride ?? databaseFactory).openDatabase(
      file.path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      // Older databases have no youtube_video_id / spotify_url column.
      final columns = {
        for (final c in await db.rawQuery('PRAGMA table_info(songs)'))
          c['name'],
      };
      String column(String name) => columns.contains(name) ? 's.$name' : 'NULL';
      final artistLatin = await _hasColumn(db, 'artists', 'name_latin')
          ? 'a.name_latin'
          : 'NULL';
      // Before MusicDatabase's Latin forms (hand-off musicdatabase-latin-names.md) and its
      // albums table, the columns aren't there.
      final albumLatin =
          columns.contains('album_id') &&
              await _hasColumn(db, 'albums', 'title_latin')
          ? '(SELECT al.title_latin FROM albums al WHERE al.id = s.album_id)'
          : 'NULL';
      final rows = await db.rawQuery('''
        SELECT s.id, s.title, s.album, s.year, s.language,
               ${column('youtube_video_id')} AS youtube_video_id,
               ${column('spotify_url')} AS spotify_url,
               ${column('title_latin')} AS title_latin,
               $albumLatin AS album_latin,
               a.name AS artist, a.origin, a.synonyms, $artistLatin AS name_latin
        FROM songs s JOIN artists a ON a.id = s.artist_id''');
      final extra = await _readAdditionalArtists(db, artistLatin);
      return [
        for (final row in rows)
          _song(row, [_artistOf(row, 'main'), ...?extra[row['id']! as int]]),
      ];
    } finally {
      await db.close();
    }
  }

  static CatalogSong _song(Map<String, Object?> row, List<_Artist> artists) {
    String? present(String? s) => s == null || s.trim().isEmpty ? null : s;
    final otherNames = [
      for (final a in artists) ...[?present(a.synonyms), ?present(a.nameLatin)],
    ];
    return CatalogSong(
      id: row['id']! as int,
      title: row['title']! as String,
      album: row['album'] as String?,
      year: row['year'] as int?,
      language: present(row['language'] as String?),
      youtubeVideoId: (row['youtube_video_id'] as String?)?.trim(),
      spotifyTrackId: _spotifyTrackId(row['spotify_url'] as String?),
      youTubeTarget: MatchTarget(
        title: row['title']! as String,
        mainArtists: [
          for (final a in artists)
            if (a.role == 'main') MatchArtist(a.name, _otherNames(a)),
        ],
        featArtists: [
          for (final a in artists)
            if (a.role == 'feat') MatchArtist(a.name, _otherNames(a)),
        ],
      ),
      artistLabel: _artistLabel(artists),
      artistNames: [for (final a in artists) a.name],
      origins: [for (final a in artists) ?present(a.origin)],
      synonyms: otherNames,
      titleLatin: row['title_latin'] as String?,
      albumLatin: row['album_latin'] as String?,
      artistLatin: _artistLatinLabel(artists),
    );
  }

  /// `artists.synonyms` with `name_latin` added, as one comma-separated list.
  static String? _otherNames(_Artist a) => [
    for (final s in [a.synonyms, a.nameLatin])
      if (s != null && s.trim().isNotEmpty) s,
  ].join(', ');

  /// [_artistLabel] in Latin letters: each artist's `name_latin`, else (for a name in another
  /// alphabet) its first Latin synonym; `null` when no artist needs one, or one has none.
  static String? _artistLatinLabel(List<_Artist> artists) {
    if (!artists.any((a) => hasNonLatinLetters(a.name))) return null;
    final latin = <_Artist>[];
    for (final a in artists) {
      final name =
          latinFormOf(a.name, a.nameLatin) ??
          (hasNonLatinLetters(a.name) ? latinSynonym(a.synonyms) : a.name);
      if (name == null) return null;
      latin.add((
        role: a.role,
        name: name,
        origin: a.origin,
        synonyms: a.synonyms,
        nameLatin: null,
      ));
    }
    return _artistLabel(latin);
  }

  static Future<bool> _hasColumn(
    Database db,
    String table,
    String column,
  ) async =>
      (await db.rawQuery('PRAGMA table_info($table)'))
          .any((c) => c['name'] == column);

  static String? _spotifyTrackId(String? url) => url == null
      ? null
      : RegExp(r'open\.spotify\.com/(?:intl-[\w-]+/)?track/([A-Za-z0-9]{22})')
            .firstMatch(url)
            ?.group(1);

  static _Artist _artistOf(Map<String, Object?> row, String role) => (
    role: role,
    name: (row['artist'] ?? row['name'])! as String,
    origin: row['origin'] as String?,
    synonyms: row['synonyms'] as String?,
    nameLatin: row['name_latin'] as String?,
  );

  /// `bad_youtube_videos`; none in a music.db from before MusicDatabase's migration 0010.
  Future<BadVideos> _readBadVideos(File file) async {
    final db = await (factoryOverride ?? databaseFactory).openDatabase(
      file.path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final hasTable = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' "
        "AND name = 'bad_youtube_videos'",
      );
      if (hasTable.isEmpty) return BadVideos.none;
      final everySong = <String>{};
      final forSong = <int, Set<String>>{};
      for (final row in await db.rawQuery(
        'SELECT video_id, song_id FROM bad_youtube_videos',
      )) {
        final video = (row['video_id'] as String?)?.trim();
        if (video == null || video.isEmpty) continue;
        final song = row['song_id'] as int?;
        if (song == null) {
          everySong.add(video);
        } else {
          (forSong[song] ??= {}).add(video);
        }
      }
      return BadVideos(everySong: everySong, forSong: forSong);
    } finally {
      await db.close();
    }
  }

  /// `additional_song_artists` (role `main` or `feat`) per song id; empty for databases created
  /// before that table existed.
  Future<Map<int, List<_Artist>>> _readAdditionalArtists(
    Database db,
    String nameLatin,
  ) async {
    final hasTable = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'additional_song_artists'",
    );
    if (hasTable.isEmpty) return const {};
    final rows = await db.rawQuery('''
      SELECT x.song_id, x.role, a.name, a.origin, a.synonyms,
             $nameLatin AS name_latin
      FROM additional_song_artists x JOIN artists a ON a.id = x.artist_id
      ORDER BY x.song_id, a.name''');
    final result = <int, List<_Artist>>{};
    for (final row in rows) {
      (result[row['song_id']! as int] ??= []).add(
        _artistOf(row, row['role']! as String),
      );
    }
    return result;
  }

  /// "Main, Other main feat. Guest, Guest 2" — the first entry is the song's own artist.
  static String _artistLabel(List<_Artist> artists) {
    final mains = [
      for (final a in artists)
        if (a.role == 'main') a.name,
    ];
    final feats = [
      for (final a in artists)
        if (a.role == 'feat') a.name,
    ];
    final label = mains.join(', ');
    return feats.isEmpty ? label : '$label feat. ${feats.join(', ')}';
  }

  Map<String, List<CatalogSong>>? _byTitle;
  Map<String, CatalogSong>? _byYouTubeId;

  /// The song MusicDatabase links to this YouTube video, or `null`.
  CatalogSong? findByYouTubeId(String videoId) => (_byYouTubeId ??= {
    for (final song in _songs)
      if (song.youtubeVideoId != null) song.youtubeVideoId!: song,
  })[videoId];

  /// The song with this `songs.id`, or `null`.
  CatalogSong? byId(int id) =>
      (_byId ??= {for (final song in _songs) song.id: song})[id];
  Map<int, CatalogSong>? _byId;

  /// The song with exactly this title and artist (both compared after normalization, so case,
  /// accents and punctuation don't matter), or `null`. The artist may be any of the song's
  /// artists, the whole "A, B feat. C" label, or one of the artists' other names. Used to tell
  /// whether a music file on the phone is already in MusicDatabase.
  CatalogSong? findExact({required String title, required String artist}) {
    final byTitle = _byTitle ??= () {
      final index = <String, List<CatalogSong>>{};
      for (final song in _songs) {
        (index[song._normalizedTitle] ??= []).add(song);
      }
      return index;
    }();
    final normalizedArtist = normalizeForSearch(artist);
    if (normalizedArtist.isEmpty) return null;
    return byTitle[normalizeForSearch(title)]
        ?.where((s) => s._normalizedArtists.contains(normalizedArtist))
        .firstOrNull;
  }

  /// Songs whose selected [searchFields] together contain every word of [query] (after
  /// normalization), best matches first: exact title, then title starting with the query, then
  /// title containing it, then the rest; alphabetical within each group.
  List<CatalogSong> search(String query) {
    final normalizedQuery = normalizeForSearch(query);
    if (normalizedQuery.isEmpty) return const [];
    final words = normalizedQuery.split(' ');
    final moodNames = _searchFields.contains(SearchField.mood)
        ? _moodNames
        : null;
    final texts = _searchTexts ??= [
      for (final song in _songs)
        moodNames == null
            ? song._textFor(_searchFields)
            : '${song._textFor(_searchFields)} '
                  '${normalizeForSearch(moodNames(song.id))}',
    ];
    final hits = [
      for (var i = 0; i < _songs.length; i++)
        if (words.every(texts[i].contains)) _songs[i],
    ];
    int rank(CatalogSong s) =>
        titleMatchRank(s._normalizedTitle, normalizedQuery);

    hits.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0
          ? byRank
          : a._normalizedTitle.compareTo(b._normalizedTitle);
    });
    return hits;
  }

  @override
  void dispose() {
    _sync.removeListener(_onSyncChanged);
    super.dispose();
  }
}

typedef _Artist = ({
  String role,
  String name,
  String? origin,
  String? synonyms,
  String? nameLatin,
});

/// Makes the [SongCatalog] reachable from any screen.
class SongCatalogScope extends InheritedNotifier<SongCatalog> {
  const SongCatalogScope({
    super.key,
    required SongCatalog super.notifier,
    required super.child,
  });

  static SongCatalog of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SongCatalogScope>()!.notifier!;
}
