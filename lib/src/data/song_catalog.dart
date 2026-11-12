import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'cover_credit.dart';
import 'database_sync.dart';
import 'feat_credit.dart';
import 'latin_names.dart';
import 'playlist_library.dart';
import 'project_names.dart';
import 'song_requests.dart';
import 'text_normalizer.dart';
import 'version_names.dart';
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

/// YouTube links of a song the user set by hand in "Informacje o utworze" — sent to MusicDatabase
/// as field corrections (`Outbox.correctField`), and used on the phone meanwhile
/// ([CatalogSong.withUserLinks]). `null` leaves music.db's value; otherwise the value as music.db
/// would store it: a video id, "" (no link) or, for [video] only, "N/A".
class UserYouTubeLinks {
  const UserYouTubeLinks({this.video, this.musicVideo});

  /// For `songs.youtube_video_id`.
  final String? video;

  /// For `songs.music_video_youtube_id`.
  final String? musicVideo;

  @override
  bool operator ==(Object other) =>
      other is UserYouTubeLinks &&
      other.video == video &&
      other.musicVideo == musicVideo;

  @override
  int get hashCode => Object.hash(video, musicVideo);
}

/// The song's audio file in the music library on MusicDatabase's server: a row of the
/// downloaded `files.db` (MusicDatabase's `files_index.py`), played over HTTP as
/// `GET /library/<id>` (hand-off `musicdatabase-server-files.md`).
class ServerFile {
  const ServerFile({required this.id, required this.path, this.duration});

  /// `files.id`; never reused for another file.
  final int id;

  /// Relative to the library folder, with `/` separators ("Artist/Album/01 Song.mp3").
  final String path;

  /// `files.duration_s`; `null` when the index couldn't read it.
  final Duration? duration;

  String get fileName => path.split('/').last;
}

/// What a row of `songs` is (`songs.kind`, hand-off `musicdatabase-song-kind.md`).
enum SongKind {
  /// An ordinary song: `NULL`, and any value the phone doesn't know yet (MusicDatabase may add
  /// some, e.g. a live set).
  song,

  /// `'full_album'`: a whole album in one recording (a "full album" video, the album in one
  /// file) — filed under the album it plays. Left out of the radio, Odkrywaj and other
  /// automatic picks.
  fullAlbum;

  static SongKind of(Object? value) =>
      value == fullAlbumValue ? fullAlbum : song;

  /// `songs.kind` of a [fullAlbum].
  static const fullAlbumValue = 'full_album';
}

/// The genres in `songs.genre`: comma-separated, the main one first, each once.
List<String> genresOf(String? genre) => [
  ...{
    for (final part in (genre ?? '').split(','))
      if (part.trim() case final name when name.isNotEmpty) name,
  },
];

/// The artists in a song's label ("A, B feat. C" → A, B, C).
List<String> artistNamesOf(String label) => [
  ...{
    for (final part in label.split(
      RegExp(r',| feat\. | ft\. | & ', caseSensitive: false),
    ))
      if (part.trim() case final name when name.isNotEmpty) name,
  },
];

typedef _SearchNames = ({
  String? titleLatin,
  String? albumLatin,
  List<String> artistNames,
  List<String> synonyms,
  List<String> origins,
});

/// One row of MusicDatabase's `songs` table, with its artists already joined in.
class CatalogSong {
  CatalogSong({
    required this.id,
    required this.title,
    required this.artistLabel,
    this.album,
    this.year,
    this.language,
    String? genre,
    this.kind = SongKind.song,
    String? youtubeVideoId,
    String? musicVideoId,
    this.spotifyTrackId,
    MatchTarget? youTubeTarget,
    List<String> artistNames = const [],
    List<String> origins = const [],
    List<String> synonyms = const [],
    String? titleLatin,
    String? albumLatin,
    this.artistLatin,
    this.coverOf,
    this.version,
    this.project,
    this.serverFile,
  }) : countries = [
         ...{
           for (final origin in origins)
             if (origin.split(' - ').first.trim() case final country
                 when country.isNotEmpty)
               country,
         },
       ],
       genres = genresOf(genre),
       titleLatin = latinFormOf(title, titleLatin),
       albumLatin = latinFormOf(album, albumLatin),
       youTubeTarget =
           youTubeTarget ??
           MatchTarget(
             title: title,
             mainArtists: [MatchArtist(artistLabel)],
             fullAlbum: kind == SongKind.fullAlbum,
             coverOf: coverOf?.name,
             version: version?.marker,
           ),
       youtubeVideoId = _videoIdOf(youtubeVideoId),
       youTube = _youTubeLinkOf(youtubeVideoId),
       musicVideoId = _videoIdOf(musicVideoId),
       userLinks = null,
       _fromMusicDb = null,
       _names = (
         titleLatin: titleLatin,
         albumLatin: albumLatin,
         artistNames: artistNames,
         synonyms: synonyms,
         origins: origins,
       );

  /// [song] with the YouTube links the user set on the phone ([links]) in place of music.db's.
  CatalogSong._withUserLinks(CatalogSong song, UserYouTubeLinks links)
    : id = song.id,
      title = song.title,
      artistLabel = song.artistLabel,
      album = song.album,
      titleLatin = song.titleLatin,
      artistLatin = song.artistLatin,
      coverOf = song.coverOf,
      version = song.version,
      project = song.project,
      albumLatin = song.albumLatin,
      year = song.year,
      language = song.language,
      genres = song.genres,
      kind = song.kind,
      countries = song.countries,
      youtubeVideoId = links.video == null
          ? song.youtubeVideoId
          : _videoIdOf(links.video),
      youTube = links.video == null
          ? song.youTube
          : _youTubeLinkOf(links.video),
      musicVideoId = links.musicVideo == null
          ? song.musicVideoId
          : _videoIdOf(links.musicVideo),
      spotifyTrackId = song.spotifyTrackId,
      serverFile = song.serverFile,
      youTubeTarget = song.youTubeTarget,
      userLinks = links,
      _fromMusicDb = song,
      _names = null;

  static String? _videoIdOf(String? value) =>
      const {null, '', 'N/A'}.contains(value) ? null : value;

  static YouTubeLink _youTubeLinkOf(String? value) => switch (value) {
    null || '' => YouTubeLink.unknown,
    'N/A' => YouTubeLink.notOnYouTube,
    _ => YouTubeLink.linked,
  };

  /// The song with the user's own YouTube links in place of music.db's, or as music.db has it
  /// with `null`.
  CatalogSong withUserLinks(UserYouTubeLinks? links) {
    final song = fromMusicDb;
    return links == null ? song : CatalogSong._withUserLinks(song, links);
  }

  /// The song as music.db has it, without [userLinks].
  CatalogSong get fromMusicDb => _fromMusicDb ?? this;
  final CatalogSong? _fromMusicDb;

  /// The YouTube links the user set in "Informacje o utworze", used in place of music.db's
  /// until a downloaded music.db changes the value they correct; `null` for music.db's own.
  final UserYouTubeLinks? userLinks;

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

  /// What this song is a cover of, `null` for most songs. A covered artist is never one of
  /// its artists: [artistLabel] stays the performer.
  final CoverOf? coverOf;

  /// What kind of version of another song this row is (live, a remix…), `null` for most songs
  /// (and before music.db has the columns). [title] stays without the marker.
  final SongVersion? version;

  /// The name of the project this recording was made for (`songs.project_id`, MusicDatabase's
  /// migration 0019: Tiny Desk, Męskie Granie), `null` for most songs and before the column.
  /// [title] and [artistLabel] stay without it.
  final String? project;
  final int? year;
  final String? language;

  /// `songs.genre` split into its genres, the main one first; empty without one (or before
  /// music.db has the column — hand-off `musicdatabase-genres.md`).
  final List<String> genres;

  /// `songs.kind`: an ordinary song, or a whole album in one recording.
  final SongKind kind;

  bool get isFullAlbum => kind == SongKind.fullAlbum;

  /// The countries its artists come from: the first part of each `artists.origin` ("Kraj -
  /// Region - Miasto"), for Wyszukaj's "Przeglądaj".
  final List<String> countries;

  /// Set only when [youTube] is [YouTubeLink.linked].
  final String? youtubeVideoId;

  /// `songs.youtube_video_id` as stored: the video id, "N/A" or `null`.
  String? get youtubeValue =>
      youtubeVideoId ?? (youTube == YouTubeLink.notOnYouTube ? 'N/A' : null);

  /// The song's music video (`songs.music_video_youtube_id`), when it has one apart from
  /// [youtubeVideoId] — which is the audio the phone plays. Only opened in YouTube.
  final String? musicVideoId;

  /// The song's Spotify track, when MusicDatabase's `spotify_url` (set by hand) is a track page —
  /// it may also be an album page, which isn't the song.
  final String? spotifyTrackId;
  final YouTubeLink youTube;

  /// The song's file on MusicDatabase's server (`files.db`), `null` when it has none or the
  /// server shares no `files.db`.
  final ServerFile? serverFile;

  /// What to look for when the phone searches YouTube for this song itself.
  final MatchTarget youTubeTarget;

  /// The names the texts below are made from, as music.db gives them; `null` with
  /// [_fromMusicDb], which has the texts. The texts are made on first use: normalizing every
  /// song's names as music.db loaded held the restored queue up for seconds on a slow phone.
  final _SearchNames? _names;

  late final String _normalizedTitle =
      _fromMusicDb?._normalizedTitle ?? normalizeForSearch(title);

  /// Every name the song's artists go by (label, each artist, synonyms), normalized — for
  /// matching a file's "artist" against this song in [SongCatalog.findExact].
  late final Set<String> _normalizedArtists =
      _fromMusicDb?._normalizedArtists ?? _artistTexts(_names!);

  Set<String> _artistTexts(_SearchNames names) => {
    normalizeForSearch(artistLabel),
    for (final name in [...names.artistNames, ...names.synonyms])
      normalizeForSearch(name),
  };

  /// Normalized text of each [SearchField], indexed by `SearchField.index`.
  late final List<String> _fieldTexts =
      _fromMusicDb?._fieldTexts ?? _fieldTextsOf(_names!);

  List<String> _fieldTextsOf(_SearchNames names) => [
    for (final field in SearchField.values)
      normalizeForSearch(switch (field) {
        SearchField.title => [
          title,
          ?names.titleLatin,
          ?coverOf?.searchText,
          ?version?.marker,
        ].join(' '),
        SearchField.artist => [
          if (names.artistNames.isEmpty) artistLabel else ...names.artistNames,
          ...names.synonyms,
          ?artistLatin,
        ].join(' '),
        SearchField.album =>
          album == null ? null : [album, ?names.albumLatin].join(' '),
        SearchField.year => year?.toString(),
        // "Unknown" is MusicDatabase's placeholder, not a language to find songs by.
        SearchField.language => language == 'Unknown' ? null : language,
        SearchField.origin => names.origins.join(' '),
        // Moods change while the song doesn't: SongCatalog adds them when searching.
        SearchField.mood => null,
      }),
  ];

  String _textFor(Set<SearchField> fields) => [
    for (final field in SearchField.values)
      if (fields.contains(field) && _fieldTexts[field.index].isNotEmpty)
        _fieldTexts[field.index],
  ].join(' ');
}

enum CatalogStatus { notLoaded, loading, ready, noDatabase, error }

/// What [SongCatalog] reads from music.db and files.db at once.
typedef _CatalogRead = ({
  List<CatalogSong> songs,
  BadVideos badVideos,
  Map<String, int> additionalVideos,
  Map<String, Duration> videoDurations,
  List<Project> projects,
  RejectedSongRequests rejected,
  Map<int, int?> idChanges,
  String? filesError,
});

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
  SongCatalog(this._sync) {
    _sync.addListener(_onSyncChanged);
    _loadSearchFields();
  }

  static const _searchFieldsKey = 'search.fields';

  final DatabaseSync _sync;

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

  List<PlaylistTrack> Function(String query)? _moodTracks;

  /// Where [moodTracksFor] gets its songs.
  void setMoodTracks(List<PlaylistTrack> Function(String query) moodTracks) =>
      _moodTracks = moodTracks;

  /// Songs not in music.db that moods hold, for [query] (`SearchField.mood`).
  List<PlaylistTrack> moodTracksFor(String query) =>
      _moodTracks?.call(query) ?? const [];

  /// A mood was made, renamed or got other songs: search sees it from the next keystroke.
  void moodsChanged() => _searchTexts = null;

  CatalogStatus get status => _status;

  BadVideos _badVideos = BadVideos.none;

  /// Videos MusicDatabase found bad (`bad_youtube_videos`).
  BadVideos get badVideos => _badVideos;

  Map<String, Duration> _videoDurations = const {};

  /// How long YouTube video [videoId] is, as MusicDatabase asked YouTube
  /// (`youtube_video_durations`, hand-off `video-durations-for-musicdatabaseapp.md`); `null`:
  /// unknown — a live stream, a gone video, one not asked about yet, or an older music.db.
  Duration? videoDuration(String? videoId) =>
      videoId == null ? null : _videoDurations[videoId];

  /// music.db's `projects` dictionary, for reading the project a name says it's from
  /// ([findByName]); empty before MusicDatabase's migration 0019.
  List<Project> _projects = const [];

  Map<String, int> _additionalVideos = const {};

  /// Other uploads of the same recording MusicDatabase knows (`additional_youtube_videos`,
  /// hand-off `additional-videos-for-musicdatabaseapp.md`), by video id: the song id. Only for
  /// recognising a video ([findByYouTubeId]), never a song's link.
  Map<String, int> get additionalVideos =>
      UnmodifiableMapView(_additionalVideos);

  RejectedSongRequests _rejectedSongRequests = RejectedSongRequests.none;

  /// Songs MusicDatabase's owner doesn't want added (`rejected_song_requests`): not asked for
  /// again ([SongRequest]).
  RejectedSongRequests get rejectedSongRequests => _rejectedSongRequests;

  /// When the `music.db` now loaded was downloaded (`DatabaseSync.lastSync` at load time).
  DateTime? get loadedSyncTime => _loadedSyncTime;
  int get songCount => _songs.length;

  /// Every song of music.db, in no particular order (Odkrywaj picks from them).
  List<CatalogSong> get songs => UnmodifiableListView(_songs);

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
        _additionalVideos = const {};
        _videoDurations = const {};
        _projects = const [];
        _rejectedSongRequests = RejectedSongRequests.none;
        _status = CatalogStatus.noDatabase;
      } else {
        final read = await _readInBackground(
          file.path,
          (await _sync.localFile('files.db')).path,
        );
        // Logged here: a background isolate's debugPrint doesn't reach the error log.
        if (read.filesError case final error?) {
          debugPrint('Reading files.db failed: $error');
        }
        // All at once, with the indexes below: a search between two awaits would otherwise
        // read the new songs through the old search texts.
        _songs = read.songs;
        _badVideos = read.badVideos;
        _additionalVideos = read.additionalVideos;
        _videoDurations = read.videoDurations;
        _projects = read.projects;
        _rejectedSongRequests = read.rejected;
        _idChanges = read.idChanges;
        _searchTexts = null;
        _byTitle = null;
        _byMarkedTitle = null;
        _artistByName = null;
        _byYouTubeId = null;
        _byId = null;
        _versionsByOriginal = null;
        _status = CatalogStatus.ready;
      }
      _loadedSyncTime = syncTime;
    } catch (e) {
      debugPrint('Loading music.db failed: $e');
      _songs = const [];
      _badVideos = BadVideos.none;
      _additionalVideos = const {};
      _videoDurations = const {};
      _projects = const [];
      _rejectedSongRequests = RejectedSongRequests.none;
      _status = CatalogStatus.error;
    } finally {
      _searchTexts = null;
      _byTitle = null;
      _byMarkedTitle = null;
      _artistByName = null;
      _byYouTubeId = null;
      _byId = null;
      _versionsByOriginal = null;
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

  /// Read in a background isolate (a static closure: nothing of this catalog goes along), with
  /// SQLite called directly: through sqflite every row crossed the platform channel and was
  /// decoded on the main isolate, in one queue with everything else the app reads at start.
  /// The result comes back without being copied ([Isolate.run] ends with `Isolate.exit`).
  static Future<_CatalogRead> _readInBackground(
    String musicDb,
    String filesDb,
  ) => Isolate.run(() => _readCatalog(musicDb, filesDb));

  static Future<_CatalogRead> _readCatalog(
    String musicDb,
    String filesDb,
  ) async {
    // files.db in an isolate of its own, read while music.db is: its query alone took a slow
    // phone 150 ms.
    final serverFilesRead = Isolate.run(() => _readServerFiles(filesDb));
    final db = sqlite3.open(musicDb, mode: OpenMode.readOnly);
    try {
      final tables = {
        for (final row in db.select(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ))
          row['name']! as String,
      };
      final songRows = _querySongs(db, tables);
      final badVideos = _readBadVideos(db, tables);
      final additionalVideos = _readAdditionalVideos(db, tables);
      final videoDurations = _readVideoDurations(db, tables);
      final projects = _readProjects(db);
      final rejected = RejectedSongRequests.read(db);
      final idChanges = _readIdChanges(db, tables);
      final serverFiles = await serverFilesRead;
      return (
        songs: _songsOf(songRows, serverFiles.files),
        badVideos: badVideos,
        additionalVideos: additionalVideos,
        videoDurations: videoDurations,
        projects: projects,
        rejected: rejected,
        idChanges: idChanges,
        filesError: serverFiles.error,
      );
    } finally {
      db.close();
    }
  }

  /// `files.db`'s files of each song, the largest one when a song has several; empty when there's
  /// no `files.db` or it can't be read (with [error]) — the songs still load, only without server
  /// files.
  static ({Map<int, ServerFile> files, String? error}) _readServerFiles(
    String path,
  ) {
    if (!File(path).existsSync()) return (files: const {}, error: null);
    try {
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        final duration = _hasColumn(db, 'files', 'duration_s')
            ? 'duration_s'
            : 'NULL';
        final found = <int, ServerFile>{};
        for (final row in db.select(
          'SELECT id, path, song_id, $duration AS duration_s FROM files '
          'WHERE song_id IS NOT NULL ORDER BY size DESC, id',
        )) {
          final seconds = row['duration_s'] as int?;
          found.putIfAbsent(
            row['song_id']! as int,
            () => ServerFile(
              id: row['id']! as int,
              path: row['path']! as String,
              duration: seconds == null || seconds <= 0
                  ? null
                  : Duration(seconds: seconds),
            ),
          );
        }
        return (files: found, error: null);
      } finally {
        db.close();
      }
    } catch (e) {
      return (files: const {}, error: '$e');
    }
  }

  /// `songs` with their artists, as rows, and each song's additional artists.
  static ({ResultSet rows, Map<int, List<_Artist>> extra}) _querySongs(
    Database db,
    Set<String> tables,
  ) {
    // Older databases have no youtube_video_id / spotify_url / music_video_youtube_id column.
    final columns = {
      for (final c in db.select('PRAGMA table_info(songs)')) c['name'],
    };
    String column(String name) => columns.contains(name) ? 's.$name' : 'NULL';
    final artistLatin = _hasColumn(db, 'artists', 'name_latin')
        ? 'a.name_latin'
        : 'NULL';
    // Before MusicDatabase's Latin forms (hand-off musicdatabase-latin-names.md) and its
    // albums table, the columns aren't there.
    final albumLatin =
        columns.contains('album_id') && _hasColumn(db, 'albums', 'title_latin')
        ? '(SELECT al.title_latin FROM albums al WHERE al.id = s.album_id)'
        : 'NULL';
    // Before MusicDatabase's migrations 0020 and 0021 the columns aren't there.
    final covers = columns.contains('covered_artist_id');
    // Before its migration 0019 neither songs.project_id nor projects is there.
    final project =
        columns.contains('project_id') && _hasColumn(db, 'projects', 'name')
        ? '(SELECT p.name FROM projects p WHERE p.id = s.project_id)'
        : 'NULL';
    final rows = db.select(
      '''
        SELECT s.id, s.title, s.album, s.year, s.language,
               ${column('youtube_video_id')} AS youtube_video_id,
               ${column('music_video_youtube_id')} AS music_video_youtube_id,
               ${column('spotify_url')} AS spotify_url,
               ${column('title_latin')} AS title_latin,
               ${column('genre')} AS genre,
               ${column('kind')} AS kind,
               $albumLatin AS album_latin,
               ${column('covered_title')} AS covered_title,
               ${column('version_kind')} AS version_kind,
               ${column('version_label')} AS version_label,
               ${column('version_of')} AS version_of,
               $project AS project,
               ${covers ? 'c.name' : 'NULL'} AS covered_name,
               ${covers ? 'c.synonyms' : 'NULL'} AS covered_synonyms,
               ${covers && artistLatin != 'NULL' ? 'c.name_latin' : 'NULL'} AS covered_latin,
               a.name AS artist, a.origin, a.synonyms, $artistLatin AS name_latin
        FROM songs s JOIN artists a ON a.id = s.artist_id
        ${covers ? 'LEFT JOIN artists c ON c.id = s.covered_artist_id' : ''}''',
    );
    return (rows: rows, extra: _readAdditionalArtists(db, tables, artistLatin));
  }

  static List<CatalogSong> _songsOf(
    ({ResultSet rows, Map<int, List<_Artist>> extra}) query,
    Map<int, ServerFile> serverFiles,
  ) => [
    for (final row in query.rows)
      _song(row, [
        _artistOf(row, 'main'),
        ...?query.extra[row['id']! as int],
      ], serverFiles[row['id']! as int]),
  ];

  static CatalogSong _song(
    Map<String, Object?> row,
    List<_Artist> artists,
    ServerFile? serverFile,
  ) {
    String? present(String? s) => s == null || s.trim().isEmpty ? null : s;
    final otherNames = [
      for (final a in artists) ...[?present(a.synonyms), ?present(a.nameLatin)],
    ];
    final covered = _coverOfRow(row);
    final version = _versionOfRow(row);
    return CatalogSong(
      id: row['id']! as int,
      title: row['title']! as String,
      album: row['album'] as String?,
      year: row['year'] as int?,
      language: present(row['language'] as String?),
      genre: row['genre'] as String?,
      kind: SongKind.of(row['kind']),
      youtubeVideoId: (row['youtube_video_id'] as String?)?.trim(),
      musicVideoId: (row['music_video_youtube_id'] as String?)?.trim(),
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
        fullAlbum: SongKind.of(row['kind']) == SongKind.fullAlbum,
        coverOf: covered?.name,
        version: version?.marker,
      ),
      artistLabel: _artistLabel(artists),
      artistNames: [for (final a in artists) a.name],
      origins: [for (final a in artists) ?present(a.origin)],
      synonyms: otherNames,
      titleLatin: row['title_latin'] as String?,
      albumLatin: row['album_latin'] as String?,
      artistLatin: _artistLatinLabel(artists),
      coverOf: covered,
      version: version,
      project: row['project'] as String?,
      serverFile: serverFile,
    );
  }

  /// Before MusicDatabase's migration 0022 the columns aren't there: no versions.
  static SongVersion? _versionOfRow(Map<String, Object?> row) {
    final kind = (row['version_kind'] as String?)?.trim();
    if (kind == null || kind.isEmpty) return null;
    return SongVersion(
      VersionKind.of(kind),
      label: (row['version_label'] as String?)?.trim(),
      originalId: row['version_of'] as int?,
    );
  }

  static CoverOf? _coverOfRow(Map<String, Object?> row) {
    final name = row['covered_name'] as String?;
    if (name == null) {
      final title = (row['covered_title'] as String?)?.trim();
      return title == null || title.isEmpty ? null : CoverOf(title);
    }
    return CoverOf(
      name,
      latinFormOf(name, row['covered_latin'] as String?) ??
          (hasNonLatinLetters(name)
              ? latinSynonym(row['covered_synonyms'] as String?)
              : null),
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

  static bool _hasColumn(Database db, String table, String column) =>
      db.select('PRAGMA table_info($table)').any((c) => c['name'] == column);

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

  /// `song_id_changes`: what each old id became when MusicDatabase merged or renumbered a song
  /// (`null`: deleted); empty for databases before that table.
  static Map<int, int?> _readIdChanges(Database db, Set<String> tables) {
    if (!tables.contains('song_id_changes')) return const {};
    return {
      for (final row in db.select(
        'SELECT old_song_id, new_song_id FROM song_id_changes '
        'ORDER BY changed_at',
      ))
        row['old_song_id']! as int: row['new_song_id'] as int?,
    };
  }

  /// `bad_youtube_videos`; none in a music.db from before MusicDatabase's migration 0010.
  static BadVideos _readBadVideos(Database db, Set<String> tables) {
    if (!tables.contains('bad_youtube_videos')) return BadVideos.none;
    final everySong = <String>{};
    final forSong = <int, Set<String>>{};
    for (final row in db.select(
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
  }

  /// `additional_youtube_videos` (MusicDatabase's migration 0018); empty before it.
  static Map<String, int> _readAdditionalVideos(
    Database db,
    Set<String> tables,
  ) {
    if (!tables.contains('additional_youtube_videos')) return const {};
    return {
      for (final row in db.select(
        'SELECT video_id, song_id FROM additional_youtube_videos',
      ))
        if ((row['video_id'] as String?)?.trim() case final video?
            when video.isNotEmpty)
          video: row['song_id']! as int,
    };
  }

  /// `youtube_video_durations` (MusicDatabase's migration 0017); empty before it.
  static Map<String, Duration> _readVideoDurations(
    Database db,
    Set<String> tables,
  ) {
    if (!tables.contains('youtube_video_durations')) return const {};
    return {
      for (final row in db.select(
        'SELECT video_id, duration_s FROM youtube_video_durations '
        'WHERE duration_s > 0',
      ))
        row['video_id']! as String: Duration(
          seconds: row['duration_s']! as int,
        ),
    };
  }

  /// `projects` (MusicDatabase's migration 0019); empty before it.
  static List<Project> _readProjects(Database db) {
    if (!_hasColumn(db, 'projects', 'name')) return const [];
    return [
      for (final row in db.select(
        'SELECT name, aliases, channels FROM projects ORDER BY id',
      ))
        Project(
          row['name']! as String,
          aliases: row['aliases'] as String?,
          channels: row['channels'] as String?,
        ),
    ];
  }

  /// `additional_song_artists` (role `main` or `feat`) per song id; empty for databases created
  /// before that table existed.
  static Map<int, List<_Artist>> _readAdditionalArtists(
    Database db,
    Set<String> tables,
    String nameLatin,
  ) {
    if (!tables.contains('additional_song_artists')) return const {};
    final rows = db.select('''
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
  Map<String, List<CatalogSong>>? _byMarkedTitle;
  Map<String, String?>? _artistByName;
  Map<String, CatalogSong>? _byYouTubeId;

  /// The song this YouTube video is: the one music.db links to it, else the one music.db lists
  /// it as another upload of (unless marked wrong for that song); `null` when neither.
  CatalogSong? findByYouTubeId(String videoId) {
    if (findByOwnYouTubeId(videoId) case final song?) return song;
    final id = _additionalVideos[videoId];
    if (id == null || _badVideos.isWrongFor(id, videoId)) return null;
    return byId(id);
  }

  /// The song whose own link (`songs.youtube_video_id`) is this video, or `null` — for what is
  /// about the link itself (a dead link, a bad mark), where another upload doesn't count.
  CatalogSong? findByOwnYouTubeId(String videoId) => (_byYouTubeId ??= {
    for (final song in _songs)
      if (song.youtubeVideoId != null) song.youtubeVideoId!: song,
  })[videoId];

  /// The song with this `songs.id`, or `null`.
  CatalogSong? byId(int id) =>
      (_byId ??= {for (final song in _songs) song.id: song})[id];
  Map<int, CatalogSong>? _byId;
  Map<int, int?> _idChanges = const {};

  /// The song that has, or once had, this `songs.id` (MusicDatabase merged or renumbered it
  /// since — kept by plays and other phone data); `null` when it's gone.
  CatalogSong? current(int id) {
    for (var hops = 0; hops < 10; hops++) {
      if (byId(id) case final song?) return song;
      if (_idChanges[id] case final next?) {
        id = next;
      } else {
        return null;
      }
    }
    return null;
  }

  /// The other versions of [song] (Informacje o utworze's "Inne wersje"): the original it's a
  /// version of and that original's other versions, or, for an original, its versions; empty
  /// for a version whose original music.db doesn't have, and for most songs.
  List<CatalogSong> otherVersionsOf(CatalogSong song) {
    final originalId = song.version == null
        ? song.id
        : song.version!.originalId;
    if (originalId == null) return const [];
    final versions = _versionsByOriginal ??= () {
      final index = <int, List<CatalogSong>>{};
      for (final version in _songs) {
        if (version.version?.originalId case final id?) {
          (index[id] ??= []).add(version);
        }
      }
      for (final list in index.values) {
        list.sort((a, b) => compareNames(a.version!.marker, b.version!.marker));
      }
      return index;
    }();
    return [
      if (originalId != song.id) ?byId(originalId),
      for (final version in versions[originalId] ?? const <CatalogSong>[])
        if (version.id != song.id) version,
    ];
  }

  Map<int, List<CatalogSong>>? _versionsByOriginal;

  /// The song with exactly this title and artist (both compared after normalization, so case,
  /// accents and punctuation don't matter), or `null`. The artist may be any of the song's
  /// artists, the whole "A, B feat. C" label, or one of the artists' other names. Names read
  /// from elsewhere go through [findByName], which tries this first. A title with a cover credit
  /// ("Creep (Radiohead cover)") is also a song music.db marks as a cover, titled without it —
  /// only such a song: "Radiohead - Creep (cover)" uploaded by a fan isn't Radiohead's row.
  /// Versions are kept apart as [_titled] says: "Boję się (Live)" is only a live "Boję się".
  /// Only songs of [project] count (`null`: of no project) — [findByName] reads it from the names.
  CatalogSong? findExact({
    required String title,
    required String artist,
    String? project,
  }) {
    final normalizedArtist = normalizeForSearch(artist);
    if (normalizedArtist.isEmpty) return null;
    bool byArtist(CatalogSong s) =>
        s._normalizedArtists.contains(normalizedArtist);
    if (_titled(title, project).where(byArtist).firstOrNull case final exact?) {
      return exact;
    }
    final credit = readCoverCredit(title);
    if (credit == null) return null;
    final performer = credit.performer == null
        ? null
        : normalizeForSearch(credit.performer!);
    return _titled(credit.title, project)
        .where(
          (s) =>
              s.coverOf != null &&
              (byArtist(s) || s._normalizedArtists.contains(performer)),
        )
        .firstOrNull;
  }

  /// The songs [title] may name, in the order to try them — a lite version of MusicDatabase's
  /// rule for versions in `songs_for_entry()` (`src/utils/common/song_kinds.py`; ADR 0003): a
  /// title marking a version ([readVersion]) names only versions of that kind, the same marker
  /// first, and rows still titled with the marker (not looked at by MusicDatabase's "Find
  /// versions" yet); any other title never names a version. A plain "(Version)" may be anything
  /// ("Taylor's Version"), so it narrows nothing: such a version first, then songs titled so.
  /// A title with the marker run on, no bracket or dash ("Dancing Shoes KAMP! REMIX"), can't be
  /// cut by [readVersion]; it names the version whose title and marker together read so, after
  /// any song titled so.
  /// Projects the same way: only songs of [project] (`songs.project_id`), and for `null` only
  /// songs of none — a Męskie Granie recording isn't the studio song of that title.
  List<CatalogSong> _titled(String title, String? project) {
    final byTitle = _byTitle ??= () {
      final index = <String, List<CatalogSong>>{};
      for (final song in _songs) {
        (index[song._normalizedTitle] ??= []).add(song);
      }
      return index;
    }();
    Iterable<CatalogSong> titledSo(String title) =>
        (byTitle[normalizeForSearch(title)] ?? const <CatalogSong>[]).where(
          (song) => song.project == project,
        );
    final titled = [
      for (final song in titledSo(title))
        if (song.version == null) song,
    ];
    final wanted = readVersion(title);
    if (wanted == null) {
      final byMarkedTitle = _byMarkedTitle ??= () {
        final index = <String, List<CatalogSong>>{};
        for (final song in _songs) {
          if (song.version case final version?) {
            final key = normalizeForSearch('${song.title} ${version.marker}');
            (index[key] ??= []).add(song);
          }
        }
        return index;
      }();
      return [
        ...titled,
        ...?byMarkedTitle[normalizeForSearch(title)]?.where(
          (song) => song.project == project,
        ),
      ];
    }
    final marker = normalizeForSearch(wanted.label ?? wanted.kind.label);
    final versions = [
      for (final song in titledSo(wanted.title))
        if (song.version?.kind == wanted.kind) song,
    ];
    return [
      ...versions.where((s) => s.version!.markerKey == marker),
      ...titled,
      if (wanted.kind != VersionKind.other)
        ...versions.where((s) => s.version!.markerKey != marker),
    ];
  }

  /// The song a title and artist read from somewhere else name (a video title, a playlist, a
  /// file's tags): [findExact], else with the featured-artist credits left out of the title
  /// ("Tamagotchi feat. Dawid Podsiadło" is music.db's "Tamagotchi" — [withoutFeatCredits]) or
  /// the artist ("Organek feat. Ralph Kaminski" is music.db's "Ørganek"), else read the other
  /// way round, for an upload titled "Title - Artist" ("skeletons - easy life" read as artist
  /// "skeletons"). A joined credit, "Dawid Podsiadło i Kaśka Sochacka", names the song crediting
  /// each of them ([_byEveryArtist]). Any other marker still keeps a track apart: "(Bonus track)"
  /// may be another recording, and "(Live)" names only a live version. A project the names
  /// say they're from ([readProject]: "Boys (Like a Version)", "Kaunas Acoustics : Liūdni
  /// slibinai") is cut out of them and names only that project's songs; names that say none
  /// never name a project's song — a lite version of MusicDatabase's `songs_for_entry(...,
  /// project)`, which doesn't guess either: a song of no project may be that recording not
  /// marked yet, and nothing in its names tells.
  CatalogSong? findByName({required String title, required String artist}) {
    final reading = readProject(artist, title, _projects);
    final project = reading?.project.name;
    final pairs = reading == null
        ? [(title, artist), (artist, title)]
        : [(reading.title, reading.artist), (reading.artist, reading.title)];
    for (final (title, artist) in pairs) {
      final bareTitle = withoutFeatCredits(title);
      final bareArtist = withoutFeatCredits(artist);
      final song =
          findExact(title: title, artist: artist, project: project) ??
          (bareTitle == null
              ? null
              : findExact(
                  title: bareTitle,
                  artist: artist,
                  project: project,
                )) ??
          (bareArtist == null
              ? null
              : findExact(
                  title: bareTitle ?? title,
                  artist: bareArtist,
                  project: project,
                )) ??
          _byEveryArtist(bareTitle ?? title, bareArtist ?? artist, project);
      if (song != null) return song;
    }
    return null;
  }

  /// The song titled [title] that credits every artist of the joined credit [artist]
  /// ([artistCreditParts]), or whose artists' names stand side by side in it without a
  /// separator ("Fisz Emade Tworzywo", the trio's channel, is Fisz, Emade and Tworzywo
  /// Sztuczne, "Tworzywo" by its synonym); nothing for a credit of one artist, or naming someone
  /// the song doesn't credit — "Simon & Garfunkel" stays a name of its own.
  CatalogSong? _byEveryArtist(String title, String artist, String? project) {
    final parts = artistCreditParts(artist)?.map(normalizeForSearch).toList();
    if (parts != null) {
      if (parts.any((part) => part.isEmpty)) return null;
      return _titled(
        title,
        project,
      ).where((s) => parts.every(s._normalizedArtists.contains)).firstOrNull;
    }
    final words = normalizeForSearch(artist).split(' ');
    if (words.length < 2) return null;
    return _titled(
      title,
      project,
    ).where((s) => _namesInRow(words, s._normalizedArtists)).firstOrNull;
  }

  /// music.db's name of the artist that goes by [name]: its name, its Latin form or one of its
  /// `artists.synonyms` (a channel name — "familyboombox" is "Бумбокс"), compared after
  /// normalization. `null` when no artist goes by it, or more than one does.
  String? artistNamed(String name) {
    final byName = _artistByName ??= () {
      final index = <String, String?>{};
      for (final song in _songs) {
        final target = song.youTubeTarget;
        for (final artist in [...target.mainArtists, ...target.featArtists]) {
          for (final other in artist.names) {
            final key = normalizeForSearch(other);
            if (key.isEmpty) continue;
            index[key] = index.containsKey(key) && index[key] != artist.name
                ? null
                : artist.name;
          }
        }
      }
      return index;
    }();
    return byName[normalizeForSearch(name)];
  }

  /// Songs whose selected [searchFields] together contain every word of [query] (after
  /// normalization), best matches first: exact title, then title starting with the query, then
  /// title containing it, then the rest; alphabetical within each group. [fields] instead of
  /// [searchFields] (a dynamic playlist's own) aren't cached.
  List<CatalogSong> search(String query, {Set<SearchField>? fields}) {
    final normalizedQuery = normalizeForSearch(query);
    if (normalizedQuery.isEmpty) return const [];
    final words = normalizedQuery.split(' ');
    final searched = fields ?? _searchFields;
    final moodNames = searched.contains(SearchField.mood) ? _moodNames : null;
    List<String> textsFor() => [
      for (final song in _songs)
        moodNames == null
            ? song._textFor(searched)
            : '${song._textFor(searched)} '
                  '${normalizeForSearch(moodNames(song.id))}',
    ];
    final texts = fields == null ? _searchTexts ??= textsFor() : textsFor();
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

  /// `null` in widget tests that don't set it up.
  static SongCatalog? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SongCatalogScope>()?.notifier;
}

/// [words] (from [from] on) are two or more of [names] one after another, nothing left over:
/// "fisz emade tworzywo" of {"fisz", "emade", "tworzywo", …}.
bool _namesInRow(
  List<String> words,
  Set<String> names, [
  int from = 0,
  int count = 0,
]) {
  if (from == words.length) return count >= 2;
  for (var end = from + 1; end <= words.length; end++) {
    if (names.contains(words.sublist(from, end).join(' ')) &&
        _namesInRow(words, names, end, count + 1)) {
      return true;
    }
  }
  return false;
}
