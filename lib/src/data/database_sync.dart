import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Where a download came from: one of the two server addresses, or the public copy on GitHub.
enum DatabaseSource { remote, local, github }

/// Keeps a local copy of MusicDatabase's SQLite files, downloaded from the addresses set under
/// "Ustawienia › Serwer". See `docs/decisions/0002-database-download.md`.
///
/// Two addresses can be set: a remote one (reachable from anywhere, e.g. over Tailscale) and a
/// local one, used only while the phone is on the saved home Wi-Fi ([localWifi]). If the local
/// server can't be reached there, the remote address is tried as well. When no server is set or
/// none answers, the catalog comes from a GitHub Release ([gitHubRepo],
/// `docs/decisions/0014-github-database-and-request-packages.md`).
class DatabaseSync extends ChangeNotifier {
  DatabaseSync({
    Future<Directory> Function()? storageRoot,
    DateTime Function()? now,
    Future<String?> Function()? currentWifi,
    Future<String?> Function()? currentWifiIp,
    Uri Function(String repo)? gitHubRelease,
    Future<int?> Function(File musicDb)? countSongs,
  }) : _storageRoot = storageRoot ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now,
       _currentWifi = currentWifi ?? readCurrentWifiName,
       _currentWifiIp = currentWifiIp ?? readCurrentWifiIp,
       _gitHubRelease = gitHubRelease ?? gitHubReleaseUrl,
       _countSongs = countSongs ?? countSongsIn;

  static const fileNames = ['music.db', 'tag.db', ...optionalFileNames];

  /// Files an older MusicDatabase server doesn't have (it answers 404): the download goes on
  /// without them, and a copy left from before is removed.
  static const optionalFileNames = ['files.db'];

  // The remote address keeps the key from before local addresses existed, so phones that were
  // already set up keep working.
  static const _remoteUrlKey = 'database_sync.url';
  static const _localUrlKey = 'database_sync.local_url';
  static const _localWifiKey = 'database_sync.local_wifi';
  static const _lastSyncKey = 'database_sync.last_sync_ms';
  static const _lastSourceKey = 'database_sync.last_source';
  static const _gitHubRepoKey = 'database_sync.github_repo';
  static const _gitHubOnKey = 'database_sync.github_on';
  static const _serverEmptyKey = 'database_sync.server_empty';

  /// The owner's public catalog, filled in on every phone until changed or switched off — public,
  /// shared data, not anyone's private setting (ADR 0014).
  static const defaultGitHubRepo = 'shian1000/LeinaMusicDatabase';

  /// The files published on GitHub; `files.db` stays on the server (ADR 0010).
  static const gitHubFileNames = ['music.db', 'tag.db'];

  /// Where `<owner>/<repo>`'s release `database` serves its files (MusicDatabase's
  /// `docs/handoffs/public-database-for-musicdatabaseapp.md`).
  static Uri gitHubReleaseUrl(String repo) =>
      Uri.parse('https://github.com/$repo/releases/download/database/');

  final Future<Directory> Function() _storageRoot;
  final DateTime Function() _now;
  final Future<String?> Function() _currentWifi;
  final Future<String?> Function() _currentWifiIp;
  final Uri Function(String repo) _gitHubRelease;
  final Future<int?> Function(File musicDb) _countSongs;

  Uri? _remoteUrl;
  Uri? _localUrl;
  String? _localWifi;
  String _gitHubRepo = defaultGitHubRepo;
  bool _gitHubOn = true;
  bool _gitHubChosen = true;
  DateTime? _lastSync;
  DatabaseSource? _lastSource;
  bool _downloading = false;
  bool _serverEmpty = false;
  String? _lastError;

  /// Address used outside the home Wi-Fi; `null` if not set.
  Uri? get remoteUrl => _remoteUrl;

  /// Address used on the home Wi-Fi; `null` if not set.
  Uri? get localUrl => _localUrl;

  /// Name (SSID) of the home Wi-Fi; `null` if not set.
  String? get localWifi => _localWifi;

  /// `<owner>/<repo>` whose release `database` the catalog can come from (shown even while
  /// [gitHubOn] is off).
  String get gitHubRepo => _gitHubRepo;

  /// Whether the catalog may come from GitHub when no server answers.
  bool get gitHubOn => _gitHubOn;

  /// A fresh install that hasn't answered the first start's question about GitHub yet
  /// ([setGitHubOn] answers it); nothing is downloaded on its own until then. A phone that
  /// already downloaded a catalog, or set the switch, counts as having answered.
  bool get needsGitHubChoice => !_gitHubChosen;

  /// Whether a MusicDatabase server is set (the outbox, the account and "Serwer" files need one).
  bool get hasServer =>
      _remoteUrl != null || (_localUrl != null && _localWifi != null);

  /// Whether any source is usable at all, so "Pobierz teraz" makes sense.
  bool get hasSource => hasServer || _gitHubOn;

  /// When both files were last downloaded successfully, and from which address.
  DateTime? get lastSync => _lastSync;
  DatabaseSource? get lastSource => _lastSource;
  bool get downloading => _downloading;

  /// Whether the last download found the server's `music.db` without a single song while the
  /// phone's copy has some, and so kept the phone's copy (or took GitHub's) instead —
  /// `syncNow(acceptEmptyServer: true)` takes the empty one after all.
  bool get serverEmpty => _serverEmpty;

  /// Why the most recent download failed, in Polish for display; `null` after a success.
  String? get lastError => _lastError;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _remoteUrl = _parse(prefs.getString(_remoteUrlKey));
    _localUrl = _parse(prefs.getString(_localUrlKey));
    _localWifi = prefs.getString(_localWifiKey);
    _gitHubRepo = prefs.getString(_gitHubRepoKey) ?? defaultGitHubRepo;
    _gitHubOn = prefs.getBool(_gitHubOnKey) ?? true;
    _serverEmpty = prefs.getBool(_serverEmptyKey) ?? false;
    final ms = prefs.getInt(_lastSyncKey);
    _lastSync = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    _gitHubChosen = prefs.containsKey(_gitHubOnKey) || ms != null;
    _lastSource = DatabaseSource.values
        .where((s) => s.name == prefs.getString(_lastSourceKey))
        .firstOrNull;
    notifyListeners();
  }

  static Uri? _parse(String? stored) =>
      stored == null ? null : Uri.parse(stored);

  /// Saves the address used outside the home Wi-Fi; an empty string clears it.
  /// Throws [FormatException] (with a Polish message) if it isn't a usable address.
  Future<void> setRemoteUrl(String raw) async {
    _remoteUrl = await _store(_remoteUrlKey, normalizeUrl(raw)?.toString());
    _lastError = null;
    notifyListeners();
  }

  /// Saves the address used on the home Wi-Fi; an empty string clears it.
  /// Throws [FormatException] (with a Polish message) if it isn't a usable address.
  Future<void> setLocalUrl(String raw) async {
    _localUrl = await _store(_localUrlKey, normalizeUrl(raw)?.toString());
    _lastError = null;
    notifyListeners();
  }

  /// Saves the home Wi-Fi name; `null` clears it.
  Future<void> setLocalWifi(String? ssid) async {
    final value = ssid == null || ssid.trim().isEmpty ? null : ssid.trim();
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_localWifiKey);
    } else {
      await prefs.setString(_localWifiKey, value);
    }
    _localWifi = value;
    notifyListeners();
  }

  /// Saves the GitHub repository; an empty string brings back [defaultGitHubRepo].
  /// Throws [FormatException] (with a Polish message) if it isn't `<owner>/<repo>`.
  Future<void> setGitHubRepo(String raw) async {
    final repo = normalizeGitHubRepo(raw) ?? defaultGitHubRepo;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gitHubRepoKey, repo);
    _gitHubRepo = repo;
    _lastError = null;
    notifyListeners();
  }

  Future<void> setGitHubOn(bool on) async {
    await (await SharedPreferences.getInstance()).setBool(_gitHubOnKey, on);
    _gitHubOn = on;
    _gitHubChosen = true;
    _lastError = null;
    notifyListeners();
  }

  static final _repoPattern = RegExp(
    r'^([A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))/([A-Za-z0-9._-]{1,100})$',
  );

  /// `<owner>/<repo>` from what the user typed: the pair itself or a pasted link to the
  /// repository (or one of its pages); `null` for an empty input.
  static String? normalizeGitHubRepo(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    text = text.replaceFirst(
      RegExp(r'^(?:https?://)?(?:www\.)?github\.com/', caseSensitive: false),
      '',
    );
    final parts = text.split('/').where((p) => p.isNotEmpty).take(2).toList();
    if (parts.length == 2 && parts[1].endsWith('.git')) {
      parts[1] = parts[1].substring(0, parts[1].length - 4);
    }
    final match = _repoPattern.firstMatch(parts.join('/'));
    if (match == null || match.group(2) == '.' || match.group(2) == '..') {
      throw const FormatException(
        'Podaj repozytorium jako właściciel/nazwa (np. $defaultGitHubRepo)',
      );
    }
    return match.group(0);
  }

  Future<Uri?> _store(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
    return _parse(value);
  }

  /// Name of the Wi-Fi the phone is connected to right now, or `null` when it isn't on Wi-Fi or
  /// Android won't say (no location permission, or location turned off).
  Future<String?> currentWifiName() => _currentWifi();

  /// Looks for a MusicDatabase server on the phone's current Wi-Fi network: tries every address
  /// of its /24 subnet on the port (and path) of the remote address — the same server is
  /// expected to listen on both — and returns the first one that serves `music.db` as an SQLite
  /// file, or `null`. Takes a few seconds at most: 32 hosts at a time with short timeouts.
  Future<Uri?> discoverLocalServer({int? port}) async {
    final ownIp = await _currentWifiIp();
    final octets = ownIp?.split('.');
    if (ownIp == null || octets == null || octets.length != 4) return null;
    final template = _remoteUrl ?? _localUrl;
    final candidates = [
      for (var host = 1; host < 255; host++)
        if ('${octets.take(3).join('.')}.$host' != ownIp)
          Uri(
            scheme: 'http',
            host: '${octets.take(3).join('.')}.$host',
            port: port ?? template?.port ?? 8002,
            path: template?.path ?? '/',
          ),
    ];
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 700);
    try {
      for (var start = 0; start < candidates.length; start += 32) {
        final batch = candidates.sublist(
          start,
          min(start + 32, candidates.length),
        );
        final found = await Future.wait(
          batch.map((base) => _servesDatabase(client, base)),
        );
        final index = found.indexOf(true);
        if (index >= 0) return batch[index];
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Whether [base] answers `music.db` with something starting like an SQLite file. Reads only
  /// the first bytes, so probing doesn't download the whole database.
  static Future<bool> _servesDatabase(HttpClient client, Uri base) async {
    try {
      final request = await client
          .getUrl(base.resolve(fileNames.first))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      if (response.statusCode != HttpStatus.ok) {
        unawaited(response.drain<void>().catchError((_) {}));
        return false;
      }
      final head = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 2))) {
        head.addAll(chunk);
        if (head.length >= _sqliteHeader.length) break;
      }
      return head.length >= _sqliteHeader.length &&
          String.fromCharCodes(head.take(_sqliteHeader.length)) ==
              _sqliteHeader;
    } catch (_) {
      return false;
    }
  }

  /// Turns user input into the base address the files are resolved against.
  ///
  /// The scheme may be omitted (the server is expected on the tailnet or LAN, where plain HTTP
  /// is fine), and a pasted link to one of the files is accepted as its folder.
  static Uri? normalizeUrl(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw const FormatException(
        'Nieprawidłowy adres (np. http://serwer:8002/)',
      );
    }
    final segments = [...uri.pathSegments.where((s) => s.isNotEmpty)];
    if (segments.isNotEmpty && segments.last.endsWith('.db')) {
      segments.removeLast();
    }
    final path = segments.isEmpty ? '/' : '/${segments.join('/')}/';
    return uri.replace(path: path, query: null, fragment: null);
  }

  /// The once-a-day download: runs only if an address is set and nothing was downloaded yet
  /// today — and not before the first start's question ([needsGitHubChoice]). A failed attempt
  /// doesn't count, so the next start tries again.
  Future<void> syncIfDue() async {
    final last = _lastSync;
    final now = _now();
    final doneToday =
        last != null &&
        last.year == now.year &&
        last.month == now.month &&
        last.day == now.day;
    if (!hasSource || doneToday || needsGitHubChoice) return;
    await syncNow();
  }

  /// Downloads all files; returns whether it succeeded. The previous copy stays in place
  /// until all new files have arrived and look like SQLite databases, so a half-finished
  /// download never leaves the files out of step with each other. A server comes first (always
  /// the freshest); GitHub only when no server is set or none answers.
  ///
  /// A server whose `music.db` has no songs (MusicDatabase started "with an empty database")
  /// doesn't replace a copy that has some unless [acceptEmptyServer]: it is passed over like a
  /// server that doesn't answer, and [serverEmpty] tells the screen.
  Future<bool> syncNow({bool acceptEmptyServer = false}) async {
    if (!hasSource || _downloading) return false;
    _downloading = true;
    _lastError = null;
    final wasEmpty = _serverEmpty;
    _serverEmpty = false;
    notifyListeners();
    try {
      final attempts = await _attempts();
      if (attempts.isEmpty && !_gitHubOn) {
        throw const _SyncFailure(
          'Telefon nie jest w sieci lokalnej, a adres zdalny nie jest ustawiony',
        );
      }
      Object? serverFailure;
      for (final (source, url) in attempts) {
        try {
          await _downloadAll(url, acceptEmpty: acceptEmptyServer);
          await _succeeded(source);
          return true;
        } on _EmptyServer {
          _serverEmpty = true;
        } catch (e) {
          serverFailure = e;
        }
      }
      if (!_gitHubOn) {
        // The phone keeps its copy on purpose; the screen explains it through [serverEmpty].
        if (_serverEmpty) return false;
        throw serverFailure!;
      }
      try {
        await _downloadFromGitHub(_gitHubRepo);
        await _succeeded(DatabaseSource.github);
        return true;
      } catch (e) {
        _lastError = [
          if (serverFailure != null) _describe(serverFailure),
          'GitHub: ${_describeGitHub(e)}',
        ].join(' · ');
        return false;
      }
    } catch (e) {
      _lastError = _describe(e);
      return false;
    } finally {
      _downloading = false;
      if (_serverEmpty != wasEmpty) {
        await (await SharedPreferences.getInstance()).setBool(
          _serverEmptyKey,
          _serverEmpty,
        );
      }
      notifyListeners();
    }
  }

  /// How many songs [musicDb] has, or `null` when it can't be read as a music.db.
  static Future<int?> countSongsIn(
    File musicDb, {
    DatabaseFactory? factory,
  }) async {
    if (!await musicDb.exists()) return null;
    try {
      final db = await (factory ?? databaseFactory).openDatabase(
        musicDb.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      try {
        return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM songs'),
        );
      } finally {
        await db.close();
      }
    } catch (e) {
      debugPrint('Counting songs in ${musicDb.path} failed: $e');
      return null;
    }
  }

  Future<void> _succeeded(DatabaseSource source) async {
    _lastSync = _now();
    _lastSource = source;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSyncKey, _lastSync!.millisecondsSinceEpoch);
    await prefs.setString(_lastSourceKey, source.name);
  }

  /// The addresses to try now, best first: the local one on the home Wi-Fi, then the remote one.
  Future<List<(DatabaseSource, Uri)>> _attempts() async {
    final onHomeWifi =
        _localUrl != null &&
        _localWifi != null &&
        await _currentWifi() == _localWifi;
    return [
      if (onHomeWifi) (DatabaseSource.local, _localUrl!),
      if (_remoteUrl != null) (DatabaseSource.remote, _remoteUrl!),
    ];
  }

  /// MusicDatabase's server as the download reaches it now, best address first (e.g. for
  /// sending the outbox).
  Future<List<Uri>> serverAddresses() async => [
    for (final (_, url) in await _attempts()) url,
  ];

  Future<void> _downloadAll(Uri base, {required bool acceptEmpty}) async {
    final parts = <File>[];
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final dir = await databaseDirectory();
      final missing = <String>[];
      for (final name in fileNames) {
        final part = File('${dir.path}/$name.part');
        parts.add(part);
        final found = await _download(
          client,
          base.resolve(name),
          part,
          name,
          optional: optionalFileNames.contains(name),
        );
        if (!found) missing.add(name);
      }
      if (!acceptEmpty &&
          await _countSongs(parts.first) == 0 &&
          (await _countSongs(File('${dir.path}/${fileNames.first}')) ?? 0) >
              0) {
        throw const _EmptyServer();
      }
      for (var i = 0; i < fileNames.length; i++) {
        final target = File('${dir.path}/${fileNames[i]}');
        if (missing.contains(fileNames[i])) {
          if (await target.exists()) await target.delete();
        } else {
          await parts[i].rename(target.path);
        }
      }
    } catch (_) {
      for (final part in parts) {
        if (await part.exists()) await part.delete();
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// The catalog from [repo]'s release: `version.json` first, then only the files whose hash
  /// differs from the copy here. Everything downloaded must match its size and SHA-256 before
  /// any file is swapped, so the pair stays consistent even when a publish is under way (a file
  /// briefly missing, or already newer than `version.json`). `files.db` is left as it is: it only
  /// comes from a server, and is still right for that server's files.
  Future<void> _downloadFromGitHub(String repo) async {
    final base = _gitHubRelease(repo);
    final parts = <String, File>{};
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final version = _parseVersion(
        await _fetchBytes(client, base.resolve('version.json'), 'version.json'),
      );
      final dir = await databaseDirectory();
      for (final name in gitHubFileNames) {
        final (size, hash) = version[name]!;
        final current = File('${dir.path}/$name');
        if (await current.exists() &&
            await current.length() == size &&
            await _sha256Of(current) == hash) {
          continue;
        }
        final part = File('${dir.path}/$name.part');
        parts[name] = part;
        await _fetchTo(client, base.resolve(name), part, name);
        if (await part.length() != size || await _sha256Of(part) != hash) {
          throw _SyncFailure(
            '$name nie zgadza się z version.json (trwa publikacja?)',
          );
        }
        if (!await _looksLikeSqlite(part)) {
          throw _SyncFailure('$name nie jest bazą SQLite');
        }
      }
      for (final MapEntry(key: name, value: part) in parts.entries) {
        await part.rename('${dir.path}/$name');
      }
    } catch (_) {
      for (final part in parts.values) {
        if (await part.exists()) await part.delete();
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// Each published file's size and SHA-256 from `version.json`. Keys it doesn't know (e.g.
  /// `content_sha256`) are ignored; another `format` is a layout this app doesn't know.
  static Map<String, (int, String)> _parseVersion(List<int> bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const _SyncFailure('version.json jest nieczytelny');
    }
    if (json is! Map || json['format'] != 1) {
      throw const _SyncFailure(
        'nieznany format bazy — zostaje obecna kopia (zaktualizuj aplikację)',
      );
    }
    final files = json['files'];
    return {
      for (final name in gitHubFileNames)
        name: switch (files is Map ? files[name] : null) {
          {'size': final int size, 'sha256': final String hash}
              when RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash) =>
            (size, hash.toLowerCase()),
          _ => throw _SyncFailure('version.json nie opisuje $name'),
        },
    };
  }

  static Future<String> _sha256Of(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Future<List<int>> _fetchBytes(
    HttpClient client,
    Uri uri,
    String name,
  ) async {
    final response = await _get(client, uri, name);
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      bytes.addAll(chunk);
      if (bytes.length > 1 << 20) {
        throw _SyncFailure('$name jest za duży');
      }
    }
    return bytes;
  }

  static Future<void> _fetchTo(
    HttpClient client,
    Uri uri,
    File target,
    String name,
  ) async {
    final response = await _get(client, uri, name);
    final sink = target.openWrite();
    try {
      await sink.addStream(response.timeout(const Duration(seconds: 30)));
    } finally {
      await sink.close();
    }
  }

  /// A GET that follows GitHub's redirect to its file host (HttpClient does, up to 5).
  static Future<HttpClientResponse> _get(
    HttpClient client,
    Uri uri,
    String name,
  ) async {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().catchError((_) {});
      throw _SyncFailure(
        response.statusCode == HttpStatus.notFound
            ? 'brak pliku $name (repozytorium bez wydania „database” albo trwa publikacja)'
            : 'błąd ${response.statusCode} dla $name',
      );
    }
    return response;
  }

  Future<Directory> databaseDirectory() async {
    final root = await _storageRoot();
    return Directory('${root.path}/database').create(recursive: true);
  }

  /// Where a downloaded file lives (it may not exist yet).
  Future<File> localFile(String name) async =>
      File('${(await databaseDirectory()).path}/$name');

  /// Returns `false` when an [optional] file isn't on the server.
  Future<bool> _download(
    HttpClient client,
    Uri uri,
    File target,
    String name, {
    bool optional = false,
  }) async {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (optional && response.statusCode == HttpStatus.notFound) {
      await response.drain<void>();
      return false;
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw _SyncFailure(
        'Serwer zwrócił błąd ${response.statusCode} dla $name',
      );
    }
    final sink = target.openWrite();
    try {
      await sink.addStream(response.timeout(const Duration(seconds: 30)));
    } finally {
      await sink.close();
    }
    if (!await _looksLikeSqlite(target)) {
      throw _SyncFailure('$name z serwera nie jest bazą SQLite');
    }
    return true;
  }

  static const _sqliteHeader = 'SQLite format 3\u0000';

  static Future<bool> _looksLikeSqlite(File file) async {
    final raf = await file.open();
    try {
      final head = await raf.read(_sqliteHeader.length);
      return String.fromCharCodes(head) == _sqliteHeader;
    } finally {
      await raf.close();
    }
  }

  static String _describe(Object e) => switch (e) {
    _SyncFailure(:final message) => message,
    SocketException() => 'Nie można połączyć się z serwerem',
    TimeoutException() => 'Serwer nie odpowiada',
    HttpException() => 'Przerwane połączenie z serwerem',
    _ => 'Nie udało się pobrać bazy ($e)',
  };

  static String _describeGitHub(Object e) => switch (e) {
    _SyncFailure(:final message) => message,
    SocketException() => 'brak połączenia',
    TimeoutException() => 'nie odpowiada',
    HttpException() => 'przerwane połączenie',
    _ => 'nie udało się pobrać bazy ($e)',
  };
}

/// Reads the current Wi-Fi name via `network_info_plus`. Android reports it in quotes and
/// returns `<unknown ssid>` when it won't disclose it (no location permission or location off).
Future<String?> readCurrentWifiName() async {
  try {
    final raw = await NetworkInfo().getWifiName();
    if (raw == null) return null;
    final name = raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')
        ? raw.substring(1, raw.length - 1)
        : raw;
    return name.isEmpty || name == '<unknown ssid>' ? null : name;
  } catch (e) {
    debugPrint('Reading Wi-Fi name failed: $e');
    return null;
  }
}

/// The phone's IPv4 address on the current Wi-Fi, or `null` when it isn't on Wi-Fi.
Future<String?> readCurrentWifiIp() async {
  try {
    return await NetworkInfo().getWifiIP();
  } catch (e) {
    debugPrint('Reading Wi-Fi IP failed: $e');
    return null;
  }
}

class _EmptyServer implements Exception {
  const _EmptyServer();
}

class _SyncFailure implements Exception {
  const _SyncFailure(this.message);
  final String message;
}

/// Makes the [DatabaseSync] reachable from any screen.
class DatabaseSyncScope extends InheritedNotifier<DatabaseSync> {
  const DatabaseSyncScope({
    super.key,
    required DatabaseSync super.notifier,
    required super.child,
  });

  static DatabaseSync of(BuildContext context) => maybeOf(context)!;

  static DatabaseSync? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DatabaseSyncScope>()?.notifier;
}
