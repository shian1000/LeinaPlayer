import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../theme_controller.dart';
import '../widgets/cover_filters.dart';
import 'combined_search.dart';
import 'database_sync.dart' show readCurrentWifiIp;
import 'local_library.dart';
import 'source_settings.dart';
import 'text_normalizer.dart';

/// The song whose cover is wanted: what identifies its album, plus what the per-song sources
/// (the phone file, the YouTube video) need.
class CoverRequest {
  CoverRequest({
    required this.artist,
    required this.title,
    String? album,
    this.videoId,
    this.filePath,
    required this.seed,
    this.searchable = true,
  }) : album = realAlbum(album);

  factory CoverRequest.of(SearchHit hit) => CoverRequest(
    artist: hit.youTubeTarget.mainArtists.firstOrNull?.name ?? hit.artistLabel,
    title: hit.title,
    album: hit.album,
    videoId: hit.youtubeVideoId ?? hit.playlistVideoId,
    filePath: hit.phoneFiles.firstOrNull?.filePath,
    seed: hit.coverSeed,
  );

  factory CoverRequest.ofFile(LocalSong song) => CoverRequest(
    artist: song.artist ?? '',
    title: song.title,
    album: song.album,
    filePath: song.filePath,
    seed: song.filePath,
    searchable: song.artist != null,
  );

  /// Main artist (the first one).
  final String artist;
  final String title;

  /// `null` also for MusicDatabase's "Singles" placeholder: those songs aren't one album.
  final String? album;
  final String? videoId;
  final String? filePath;

  /// Seed for the placeholder cover shown until (or instead of) a real one.
  final String seed;

  /// Whether iTunes/Deezer may be asked; off for a bare YouTube video, whose title isn't a
  /// song title.
  final bool searchable;

  /// The same song, now known to play from [id].
  CoverRequest withVideo(String id) => id == videoId
      ? this
      : CoverRequest(
          artist: artist,
          title: title,
          album: album,
          videoId: id,
          filePath: filePath,
          seed: seed,
          searchable: searchable,
        );

  /// What iTunes/Deezer are asked about: the album, or the song when there's none. A cover
  /// belongs to the album, so all its songs share one lookup.
  late final String lookupKey = album != null
      ? 'album:${normalizeForSearch(artist)}|${normalizeForSearch(album)}'
      : 'song:${normalizeForSearch(artist)}|${normalizeForSearch(title)}';

  /// Requests with the same identity get the same cover.
  late final String identity = '$lookupKey|$videoId|$filePath|$searchable';

  /// [album] if it's really one album, else `null`.
  static String? realAlbum(String? album) {
    final a = album?.trim() ?? '';
    // MusicDatabase files singles and unmatched covers under SINGLES_ALBUM; some files carry a
    // YouTube address as their album tag.
    if (a.isEmpty || a == 'Singles' || a.contains('youtube.com')) return null;
    return a;
  }
}

/// A source's cover: the size lists use and the one for the full player.
class CoverUrls {
  const CoverUrls(this.small, this.large);

  final String small;
  final String large;
}

typedef GetJson = Future<Object?> Function(Uri uri);

/// Image bytes, `null` for 404 (e.g. a video without a high-resolution thumbnail).
typedef GetBytes = Future<Uint8List?> Function(Uri uri);

/// Album covers from the user's [CoverSource]s, in their order (ADR 0003 lite logic: MusicDatabase
/// has no covers yet — see `docs/handoffs/musicdatabase-albums-and-covers.md`).
///
/// - A phone file's own cover is read from the file each time (kept in memory while recent).
/// - iTunes/Deezer answers are remembered per album in `local.db` (`cover_lookups`), a "no cover"
///   for 30 days, so each album is asked once; these services limit how often they may be asked.
/// - Downloaded images (iTunes, Deezer, YouTube thumbnails) are kept in `<support
///   dir>/cover_cache/` (`cover_cache`) up to the user's MB limit, least recently shown going
///   first. Lists use ~250 px images, the full player ~600 px.
class AlbumCovers extends ChangeNotifier {
  AlbumCovers(
    this._database,
    this._settings, {
    Future<Directory> Function()? storageRoot,
    DateTime Function()? now,
    GetJson? getJson,
    GetBytes? getBytes,
    Future<bool> Function()? onWifi,
    Future<Uint8List?> Function(String path)? readEmbedded,
  }) : _storageRoot = storageRoot ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now,
       _getJson = getJson ?? _httpGetJson,
       _getBytes = getBytes ?? _httpGetBytes,
       _onWifi = onWifi ?? _wifiConnected,
       _readEmbedded = readEmbedded ?? _readEmbeddedCover {
    _sourcesSeen = _sourcesSignature();
    _settings.addListener(_onSettings);
  }

  final Future<Database> Function() _database;
  final SourceSettings _settings;
  final Future<Directory> Function() _storageRoot;
  final DateTime Function() _now;
  final GetJson _getJson;
  final GetBytes _getBytes;
  final Future<bool> Function() _onWifi;
  final Future<Uint8List?> Function(String path) _readEmbedded;

  static const _retryMissingAfter = Duration(days: 30);

  /// Saving "last shown" on every scroll would be a write per row; once an hour is enough to
  /// order the cache.
  static const _touchEvery = Duration(hours: 1);

  final _lookups = <String, _Lookup>{};
  final _cache = <String, _CacheEntry>{};
  final _pendingLookups = <String, Future<_Lookup?>>{};
  final _pendingImages = <String, Future<File?>>{};

  /// What [resolve] last found per song and size, so a newly built cover shows at once instead
  /// of a frame of placeholder while it's worked out again.
  final _resolved = <String, ImageProvider>{};

  /// Images that don't exist (404) — e.g. YouTube's high-resolution thumbnail of an old video —
  /// so they aren't asked for every time the player opens. Kept in `cover_lookups`.
  final _missingImages = <String, DateTime>{};
  static const _missingImageSource = 'missing_image';

  /// iTunes allows about 20 searches a minute.
  final _itunes = _Throttle(const Duration(seconds: 3));
  final _deezer = _Throttle(const Duration(milliseconds: 150));
  final _downloads = _Throttle(Duration.zero, parallel: 4);

  /// A source that just failed (offline, rate limit) is skipped for a while.
  final _pausedUntil = <CoverSource, DateTime>{};

  /// Whether each phone file has a cover, and the recent ones' bytes (same bytes object → same
  /// image in Flutter's image cache).
  final _hasEmbedded = <String, bool>{};
  final _embedded = <String, Uint8List>{};
  static const _embeddedKeepBytes = 20 * 1024 * 1024;

  int _fileCounter = 0;
  ({bool wifi, DateTime at})? _wifi;
  String _sourcesSeen = '';
  bool _loaded = false;
  Future<void>? _loading;

  int get cachedCount => _cache.length;
  int get cachedBytes => _cache.values.fold(0, (sum, e) => sum + e.sizeBytes);
  int get _limitBytes => _settings.coverCacheLimitMb * 1024 * 1024;

  Future<Directory> _cacheDir() async =>
      Directory('${(await _storageRoot()).path}/cover_cache')
          .create(recursive: true);

  Future<void> load() async {
    final db = await _database();
    for (final row in await db.query('cover_lookups')) {
      final checkedAt = DateTime.fromMillisecondsSinceEpoch(
        row['checked_at']! as int,
      );
      if (row['source'] == _missingImageSource) {
        _missingImages[row['cover_key']! as String] = checkedAt;
        continue;
      }
      final small = row['small_url'] as String?;
      final large = row['large_url'] as String?;
      _lookups['${row['cover_key']}|${row['source']}'] = _Lookup(
        small == null ? null : CoverUrls(small, large ?? small),
        checkedAt,
      );
    }
    final dir = await _cacheDir();
    for (final row in await db.query('cover_cache')) {
      _cache[row['url']! as String] = _CacheEntry(
        File('${dir.path}/${row['file_name']}'),
        row['size_bytes']! as int,
        DateTime.fromMillisecondsSinceEpoch(row['last_used_at']! as int),
      );
    }
    _loaded = true;
    await _trim();
  }

  static String _resolvedKey(CoverRequest request, bool large) =>
      '${request.identity}|$large';

  /// The cover [resolve] found last time, without waiting; `null` when not known yet.
  ImageProvider? known(CoverRequest request, {bool large = false}) =>
      _resolved[_resolvedKey(request, large)];

  /// The cover for [request] from the first switched-on source that has one; `null` → the
  /// placeholder. [wanted] is asked before each slow step, so rows scrolled away stop waiting
  /// for iTunes.
  Future<ImageProvider?> resolve(
    CoverRequest request, {
    bool large = false,
    bool Function()? wanted,
  }) async {
    final image = await _resolve(request, large, wanted);
    final key = _resolvedKey(request, large);
    // Re-inserted, so the map's order is least recently resolved first.
    _resolved.remove(key);
    if (image != null) {
      _resolved[key] = image;
      if (_resolved.length > 600) _resolved.remove(_resolved.keys.first);
    }
    return image;
  }

  Future<ImageProvider?> _resolve(
    CoverRequest request,
    bool large,
    bool Function()? wanted,
  ) async {
    final stillWanted = wanted ?? () => true;
    if (!_loaded) {
      try {
        await (_loading ??= load());
      } catch (e) {
        _loading = null;
        debugPrint('Loading album covers failed: $e');
        return null;
      }
    }
    for (final source in _settings.activeCoverSources) {
      if (!stillWanted()) return null;
      try {
        final image = await _from(source, request, large, stillWanted);
        if (image != null) return image;
      } catch (e) {
        debugPrint('Cover from ${source.name} failed: $e');
      }
    }
    return null;
  }

  Future<ImageProvider?> _from(
    CoverSource source,
    CoverRequest request,
    bool large,
    bool Function() wanted,
  ) async {
    switch (source) {
      case CoverSource.server:
        return null;
      case CoverSource.file:
        final path = request.filePath;
        if (path == null) return null;
        final bytes = await _embeddedCover(path);
        return bytes == null ? null : MemoryImage(bytes);
      case CoverSource.itunes || CoverSource.deezer:
        if (!request.searchable) return null;
        final lookup = await _lookup(source, request, wanted);
        final urls = lookup?.urls;
        if (urls == null) return null;
        return _image(large ? urls.large : urls.small, wanted);
      case CoverSource.youtube:
        final id = request.videoId;
        if (id == null) return null;
        final small = 'https://i.ytimg.com/vi/$id/mqdefault.jpg';
        // hqdefault/sddefault are 4:3 with black bars, so the fallback is the small one.
        return large
            ? await _image(
                    'https://i.ytimg.com/vi/$id/maxresdefault.jpg',
                    wanted,
                  ) ??
                  await _image(small, wanted)
            : _image(small, wanted);
    }
  }

  Future<Uint8List?> _embeddedCover(String path) async {
    final kept = _embedded.remove(path);
    if (kept != null) return _embedded[path] = kept;
    if (_hasEmbedded[path] == false) return null;
    final bytes = await _readEmbedded(path);
    _hasEmbedded[path] = bytes != null;
    if (bytes == null) return null;
    _embedded[path] = bytes;
    var total = _embedded.values.fold(0, (sum, b) => sum + b.length);
    while (total > _embeddedKeepBytes && _embedded.length > 1) {
      total -= _embedded.remove(_embedded.keys.first)!.length;
    }
    return bytes;
  }

  /// What [source] says about [request]'s album; `null` when it can't be asked now.
  Future<_Lookup?> _lookup(
    CoverSource source,
    CoverRequest request,
    bool Function() wanted,
  ) {
    final key = '${request.lookupKey}|${source.name}';
    final known = _lookups[key];
    if (known != null &&
        (known.urls != null ||
            _now().difference(known.checkedAt) < _retryMissingAfter)) {
      return Future.value(known);
    }
    return _pendingLookups[key] ??= _askSource(source, request, key, wanted)
        .whenComplete(() {
          // Not `=> remove(key)`: that returns this very future, which would then wait on itself.
          _pendingLookups.remove(key);
        });
  }

  Future<_Lookup?> _askSource(
    CoverSource source,
    CoverRequest request,
    String key,
    bool Function() wanted,
  ) async {
    final paused = _pausedUntil[source];
    if (paused != null && _now().isBefore(paused)) return null;
    if (!await _networkAllowed()) return null;
    final throttle = source == CoverSource.itunes ? _itunes : _deezer;
    final ({CoverUrls? urls})? answer;
    try {
      answer = await throttle.run(() async {
        final urls = source == CoverSource.itunes
            ? await lookUpItunes(request, _getJson)
            : await lookUpDeezer(request, _getJson);
        return (urls: urls);
      }, wanted);
    } catch (e) {
      debugPrint('Asking ${source.name} for a cover failed: $e');
      _pausedUntil[source] = _now().add(const Duration(minutes: 1));
      return null;
    }
    if (answer == null) return null;
    final lookup = _Lookup(answer.urls, _now());
    _lookups[key] = lookup;
    await (await _database()).insert('cover_lookups', {
      'cover_key': request.lookupKey,
      'source': source.name,
      'small_url': answer.urls?.small,
      'large_url': answer.urls?.large,
      'checked_at': lookup.checkedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return lookup;
  }

  Future<ImageProvider?> _image(String url, bool Function() wanted) async {
    final entry = _cache[url];
    if (entry != null) {
      if (await entry.file.exists()) {
        await _touch(url, entry);
        return FileImage(entry.file);
      }
      await _forget(url);
    }
    if (!await _networkAllowed()) return null;
    final file = await (_pendingImages[url] ??= _download(url, wanted)
        .whenComplete(() {
          _pendingImages.remove(url);
        }));
    return file == null ? null : FileImage(file);
  }

  Future<File?> _download(String url, bool Function() wanted) async {
    final missing = _missingImages[url];
    if (missing != null && _now().difference(missing) < _retryMissingAfter) {
      return null;
    }
    // A dropped request (row scrolled away) and a 404 both come back as null; only the 404 is
    // remembered.
    var asked = false;
    final bytes = await _downloads.run(() {
      asked = true;
      return _getBytes(Uri.parse(url));
    }, wanted);
    if (asked && bytes == null) await _rememberMissing(url);
    if (bytes == null || bytes.isEmpty) return null;
    final now = _now();
    final name = '${now.microsecondsSinceEpoch}_${_fileCounter++}.img';
    final file = File('${(await _cacheDir()).path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    _cache[url] = _CacheEntry(file, bytes.length, now);
    await (await _database()).insert('cover_cache', {
      'url': url,
      'file_name': name,
      'size_bytes': bytes.length,
      'last_used_at': now.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _trim(keep: url);
    return _cache.containsKey(url) ? file : null;
  }

  Future<void> _touch(String url, _CacheEntry entry) async {
    final now = _now();
    if (now.difference(entry.lastUsed) < _touchEvery) return;
    entry.lastUsed = now;
    await (await _database()).update(
      'cover_cache',
      {'last_used_at': now.millisecondsSinceEpoch},
      where: 'url = ?',
      whereArgs: [url],
    );
  }

  /// Drops the least recently shown images beyond the limit (never [keep], just downloaded).
  Future<void> _trim({String? keep}) async {
    var total = cachedBytes;
    if (total <= _limitBytes) return;
    final oldestFirst = _cache.entries.toList()
      ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    for (final MapEntry(key: url, value: entry) in oldestFirst) {
      if (total <= _limitBytes) break;
      if (url == keep) continue;
      total -= entry.sizeBytes;
      await _forget(url);
    }
  }

  Future<void> _rememberMissing(String url) async {
    final now = _now();
    _missingImages[url] = now;
    await (await _database()).insert('cover_lookups', {
      'cover_key': url,
      'source': _missingImageSource,
      'checked_at': now.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _forget(String url) async {
    final entry = _cache.remove(url);
    if (entry != null) {
      _resolved.removeWhere(
        (_, image) => image is FileImage && image.file.path == entry.file.path,
      );
    }
    if (entry != null && await entry.file.exists()) await entry.file.delete();
    await (await _database()).delete(
      'cover_cache',
      where: 'url = ?',
      whereArgs: [url],
    );
  }

  /// The cover's main colour, for the player's background; `null` when there's no cover.
  Future<Color?> colorOf(CoverRequest request) async {
    final known = _colors[request.identity];
    if (known != null) return known.color;
    final image = await resolve(request);
    final color = image == null ? null : await _mainColor(image);
    _colors[request.identity] = (color: color);
    if (_colors.length > 300) _colors.remove(_colors.keys.first);
    return color;
  }

  final _colors = <String, ({Color? color})>{};

  /// The large cover as a file, for the media notification and the lock screen (they take an
  /// address, not image bytes), with the user's [filter]; `null` when there's no cover.
  Future<Uri?> artFile(
    CoverRequest request, {
    CoverFilter filter = CoverFilter.none,
    Color color = ThemeController.defaultMonochromeColor,
    double strength = 1,
    Color? background,
  }) async {
    final image = await resolve(request, large: true);
    if (image == null) return null;
    if (filter != CoverFilter.none && strength > 0) {
      final filtered = await loadUiImage(
        FilteredImage(
          image,
          filter: filter,
          // The notification's own maximum; the lock screen scales it up.
          size: 512,
          color: color,
          dot: 4,
          seed: request.seed.hashCode,
          strength: strength,
          background: background,
        ),
      );
      final ByteData? png;
      try {
        png = await filtered.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        filtered.dispose();
      }
      return _writeArt(png!.buffer.asUint8List());
    }
    if (image is FileImage) return image.file.uri;
    if (image is MemoryImage) return _writeArt(image.bytes);
    return null;
  }

  /// Written out one at a time — the notification shows one song. A new name each time, so the
  /// notification doesn't keep showing a picture it loaded before under the same address.
  Future<Uri> _writeArt(Uint8List bytes) async {
    final dir = await Directory(
      '${(await _storageRoot()).path}/now_playing_art',
    ).create(recursive: true);
    await for (final old in dir.list()) {
      if (old is File) await old.delete();
    }
    final file = File(
      '${dir.path}/${_now().microsecondsSinceEpoch}_${_fileCounter++}.img',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.uri;
  }

  /// Deletes the downloaded images and what the services said (so they're asked again).
  Future<void> clear() async {
    final db = await _database();
    await db.delete('cover_cache');
    await db.delete('cover_lookups');
    _cache.clear();
    _lookups.clear();
    _hasEmbedded.clear();
    _embedded.clear();
    _colors.clear();
    _resolved.clear();
    _missingImages.clear();
    final dir = await _cacheDir();
    await for (final file in dir.list()) {
      if (file is File) await file.delete();
    }
    notifyListeners();
  }

  Future<bool> _networkAllowed() async {
    if (!_settings.coverWifiOnly) return true;
    final known = _wifi;
    final now = _now();
    if (known != null && now.difference(known.at).inSeconds < 20) {
      return known.wifi;
    }
    final wifi = await _onWifi();
    _wifi = (wifi: wifi, at: now);
    return wifi;
  }

  String _sourcesSignature() =>
      '${_settings.activeCoverSources.map((s) => s.name).join(',')}|'
      '${_settings.coverWifiOnly}';

  /// Covers on screen are worked out again when the sources change; a lower limit trims now.
  void _onSettings() {
    final sources = _sourcesSignature();
    if (sources != _sourcesSeen) {
      _sourcesSeen = sources;
      _wifi = null;
      _resolved.clear();
      _colors.clear();
      notifyListeners();
    }
    if (_loaded && cachedBytes > _limitBytes) {
      _trim().catchError(
        (Object e) => debugPrint('Trimming covers failed: $e'),
      );
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    super.dispose();
  }

  static Future<bool> _wifiConnected() async =>
      await readCurrentWifiIp() != null;
}

class _Lookup {
  const _Lookup(this.urls, this.checkedAt);

  /// `null`: the source has no cover for it.
  final CoverUrls? urls;
  final DateTime checkedAt;
}

class _CacheEntry {
  _CacheEntry(this.file, this.sizeBytes, this.lastUsed);

  final File file;
  final int sizeBytes;
  DateTime lastUsed;
}

/// Runs tasks at most [parallel] at a time and [gap] apart, newest first (the rows on screen
/// now); a task no longer [wanted] is dropped with `null`.
class _Throttle {
  _Throttle(this.gap, {this.parallel = 1});

  final Duration gap;
  final int parallel;
  final _waiting =
      <
        ({
          bool Function() wanted,
          Future<void> Function() start,
          void Function() drop,
        })
      >[];
  int _running = 0;
  DateTime _lastStart = DateTime(0);

  Future<T?> run<T>(Future<T> Function() task, bool Function() wanted) {
    final done = Completer<T?>();
    _waiting.add((
      wanted: wanted,
      start: () async {
        try {
          done.complete(await task());
        } catch (e, s) {
          done.completeError(e, s);
        }
      },
      drop: () => done.complete(null),
    ));
    _pump();
    return done.future;
  }

  Future<void> _pump() async {
    while (_running < parallel && _waiting.isNotEmpty) {
      final job = _waiting.removeLast();
      if (!job.wanted()) {
        job.drop();
        continue;
      }
      _running++;
      final wait = gap - DateTime.now().difference(_lastStart);
      _lastStart = DateTime.now().add(wait.isNegative ? Duration.zero : wait);
      unawaited(() async {
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        await job.start();
        _running--;
        unawaited(_pump());
      }());
    }
  }
}

/// Average of a 24×24 copy, weighted towards saturated, mid-light pixels — a dark or white
/// border shouldn't make a colourful cover grey.
Future<Color?> _mainColor(ImageProvider provider) async {
  final image = await loadUiImage(ResizeImage(provider, width: 24, height: 24));
  final ByteData? data;
  try {
    data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  } finally {
    image.dispose();
  }
  if (data == null) return null;
  var r = 0.0, g = 0.0, b = 0.0, total = 0.0;
  for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
    final pr = data.getUint8(i), pg = data.getUint8(i + 1);
    final pb = data.getUint8(i + 2);
    final hi = [pr, pg, pb].reduce((a, b) => a > b ? a : b);
    final lo = [pr, pg, pb].reduce((a, b) => a < b ? a : b);
    final saturation = hi == 0 ? 0.0 : (hi - lo) / hi;
    final light = (hi + lo) / 510;
    final weight =
        (0.05 + saturation * saturation) *
        (light < 0.1 || light > 0.92 ? 0.1 : 1.0);
    r += pr * weight;
    g += pg * weight;
    b += pb * weight;
    total += weight;
  }
  if (total == 0) return null;
  return Color.fromARGB(
    255,
    (r / total).round(),
    (g / total).round(),
    (b / total).round(),
  );
}

/// iTunes Search API (MusicDatabase's `itunes_fetcher.py` uses it for albums): the album, or the
/// song's album when there's no album. Only an exact-enough title and artist match counts.
Future<CoverUrls?> lookUpItunes(CoverRequest r, GetJson get) async {
  final album = r.album;
  final json = await get(
    Uri.https('itunes.apple.com', '/search', {
      'term': '${r.artist} ${album ?? r.title}',
      'entity': album != null ? 'album' : 'song',
      'limit': '15',
    }),
  );
  final results = json is Map ? json['results'] : null;
  for (final item in results is List ? results : const []) {
    if (item is! Map) continue;
    final name = album != null ? item['collectionName'] : item['trackName'];
    final artist = item['artistName'];
    final art = item['artworkUrl100'];
    if (name is! String || artist is! String || art is! String) continue;
    if (!sameTitle(_withoutReleaseType(name), album ?? r.title) ||
        !sameArtist(artist, r.artist)) {
      continue;
    }
    return CoverUrls(
      art.replaceFirst('100x100bb', '250x250bb'),
      art.replaceFirst('100x100bb', '600x600bb'),
    );
  }
  return null;
}

/// Deezer's search API: the album, or the song's album when there's no album.
Future<CoverUrls?> lookUpDeezer(CoverRequest r, GetJson get) async {
  final album = r.album;
  Future<CoverUrls?> search(String query) async {
    final json = await get(
      Uri.https('api.deezer.com', album != null ? '/search/album' : '/search', {
        'q': query,
        'limit': '15',
      }),
    );
    if (json is! Map) return null;
    // Over its quota Deezer answers 200 with an error object.
    if (json['error'] != null) throw HttpException('Deezer: ${json['error']}');
    final data = json['data'];
    for (final item in data is List ? data : const []) {
      if (item is! Map) continue;
      final name = item['title'];
      final artist = item['artist'] is Map ? item['artist']['name'] : null;
      final art = album != null ? item : item['album'];
      if (name is! String || artist is! String || art is! Map) continue;
      final small = art['cover_medium'];
      final large = art['cover_big'];
      if (small is! String || large is! String) continue;
      if (sameTitle(name, album ?? r.title) && sameArtist(artist, r.artist)) {
        return CoverUrls(small, large);
      }
    }
    return null;
  }

  final name = album ?? r.title;
  return await search(
        'artist:"${r.artist}" ${album != null ? 'album' : 'track'}:"$name"',
      ) ??
      await search('${r.artist} $name');
}

/// "Ray of Light" matches "Ray of Light (Remastered)", not "Ray of Lightning".
bool sameTitle(String a, String b) {
  final na = normalizeForSearch(a);
  final nb = normalizeForSearch(b);
  if (na.isEmpty || nb.isEmpty) return false;
  return na == nb || na.startsWith('$nb ') || nb.startsWith('$na ');
}

/// "Hey" matches "Hey & Kortez" or "Kortez, Hey", not "Hey Violet".
bool sameArtist(String a, String b) {
  final na = normalizeForSearch(a);
  final nb = normalizeForSearch(b);
  if (na.isEmpty || nb.isEmpty) return false;
  return na == nb ||
      _artistParts(a).contains(nb) ||
      _artistParts(b).contains(na);
}

final _artistSeparators = RegExp(
  r'\s*(?:&|,|;|/|\+|\bfeat\b\.?|\bft\b\.?|\bfeaturing\b|\bx\b|\band\b|\bi\b)\s*',
  caseSensitive: false,
);

Set<String> _artistParts(String name) => {
  for (final part in name.split(_artistSeparators))
    if (normalizeForSearch(part).isNotEmpty) normalizeForSearch(part),
};

String _withoutReleaseType(String name) =>
    name.replaceFirst(RegExp(r' - (Single|EP)$'), '');

Future<Object?> _httpGetJson(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final response = await (await client.getUrl(uri))
        .close()
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return jsonDecode(await response.transform(utf8.decoder).join());
  } finally {
    client.close(force: true);
  }
}

Future<Uint8List?> _httpGetBytes(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final response = await (await client.getUrl(uri))
        .close()
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    client.close(force: true);
  }
}

/// The file's front cover (else its largest picture); parsed off the UI thread — some files
/// carry multi-MB images.
Future<Uint8List?> _readEmbeddedCover(String path) => Isolate.run(() {
  try {
    final pictures = readMetadata(File(path), getImage: true).pictures;
    if (pictures.isEmpty) return null;
    final front = pictures
        .where((p) => p.pictureType == PictureType.coverFront)
        .firstOrNull;
    return (front ??
            pictures.reduce((a, b) => a.bytes.length >= b.bytes.length ? a : b))
        .bytes;
  } catch (_) {
    return null;
  }
});

/// Makes the [AlbumCovers] reachable from any screen.
class AlbumCoversScope extends InheritedNotifier<AlbumCovers> {
  const AlbumCoversScope({
    super.key,
    required AlbumCovers super.notifier,
    required super.child,
  });

  static AlbumCovers of(BuildContext context) => maybeOf(context)!;

  /// `null` where no scope is set up (widget tests): covers stay placeholders.
  static AlbumCovers? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AlbumCoversScope>()?.notifier;
}
