import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database_sync.dart';
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
  origin('Pochodzenie wykonawcy');

  const SearchField(this.label);

  final String label;

  static const defaults = {title, artist, album};
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
  }) : youTubeTarget =
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
             SearchField.title => title,
             SearchField.artist => [
               if (artistNames.isEmpty) artistLabel else ...artistNames,
               ...synonyms,
             ].join(' '),
             SearchField.album => album,
             SearchField.year => year?.toString(),
             // "Unknown" is MusicDatabase's placeholder, not a language to find songs by.
             SearchField.language => language == 'Unknown' ? null : language,
             SearchField.origin => origins.join(' '),
           }),
       ];

  final int id;
  final String title;

  /// Main artist(s), then featured ones: "A, B feat. C".
  final String artistLabel;
  final String? album;
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

  /// Each song's searchable text for [_searchFields], rebuilt only when the fields or the songs
  /// change rather than on every keystroke.
  List<String>? _searchTexts;

  CatalogStatus get status => _status;

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
        _status = CatalogStatus.noDatabase;
      } else {
        _songs = await _readSongs(file);
        _status = CatalogStatus.ready;
      }
      _loadedSyncTime = syncTime;
    } catch (e) {
      debugPrint('Loading music.db failed: $e');
      _songs = const [];
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
      final rows = await db.rawQuery('''
        SELECT s.id, s.title, s.album, s.year, s.language,
               ${column('youtube_video_id')} AS youtube_video_id,
               ${column('spotify_url')} AS spotify_url,
               a.name AS artist, a.origin, a.synonyms
        FROM songs s JOIN artists a ON a.id = s.artist_id''');
      final extra = await _readAdditionalArtists(db);
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
            if (a.role == 'main') MatchArtist(a.name, a.synonyms),
        ],
        featArtists: [
          for (final a in artists)
            if (a.role == 'feat') MatchArtist(a.name, a.synonyms),
        ],
      ),
      artistLabel: _artistLabel(artists),
      artistNames: [for (final a in artists) a.name],
      origins: [for (final a in artists) ?present(a.origin)],
      synonyms: [for (final a in artists) ?present(a.synonyms)],
    );
  }

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
  );

  /// `additional_song_artists` (role `main` or `feat`) per song id; empty for databases created
  /// before that table existed.
  Future<Map<int, List<_Artist>>> _readAdditionalArtists(Database db) async {
    final hasTable = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'additional_song_artists'",
    );
    if (hasTable.isEmpty) return const {};
    final rows = await db.rawQuery('''
      SELECT x.song_id, x.role, a.name, a.origin, a.synonyms
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
    final texts = _searchTexts ??= [
      for (final song in _songs) song._textFor(_searchFields),
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
