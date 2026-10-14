import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which of the two configured addresses a download used.
enum DatabaseSource { remote, local }

/// Keeps a local copy of MusicDatabase's SQLite files, downloaded from the addresses set under
/// "Ustawienia › Źródła muzyki › Baza danych". See `docs/decisions/0002-database-download.md`.
///
/// Two addresses can be set: a remote one (reachable from anywhere, e.g. over Tailscale) and a
/// local one, used only while the phone is on the saved home Wi-Fi ([localWifi]). If the local
/// server can't be reached there, the remote address is tried as well.
class DatabaseSync extends ChangeNotifier {
  DatabaseSync({
    Future<Directory> Function()? storageRoot,
    DateTime Function()? now,
    Future<String?> Function()? currentWifi,
    Future<String?> Function()? currentWifiIp,
  }) : _storageRoot = storageRoot ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now,
       _currentWifi = currentWifi ?? readCurrentWifiName,
       _currentWifiIp = currentWifiIp ?? readCurrentWifiIp;

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

  final Future<Directory> Function() _storageRoot;
  final DateTime Function() _now;
  final Future<String?> Function() _currentWifi;
  final Future<String?> Function() _currentWifiIp;

  Uri? _remoteUrl;
  Uri? _localUrl;
  String? _localWifi;
  DateTime? _lastSync;
  DatabaseSource? _lastSource;
  bool _downloading = false;
  String? _lastError;

  /// Address used outside the home Wi-Fi; `null` if not set.
  Uri? get remoteUrl => _remoteUrl;

  /// Address used on the home Wi-Fi; `null` if not set.
  Uri? get localUrl => _localUrl;

  /// Name (SSID) of the home Wi-Fi; `null` if not set.
  String? get localWifi => _localWifi;

  /// Whether any address is usable at all, so "Pobierz teraz" makes sense.
  bool get hasSource =>
      _remoteUrl != null || (_localUrl != null && _localWifi != null);

  /// When both files were last downloaded successfully, and from which address.
  DateTime? get lastSync => _lastSync;
  DatabaseSource? get lastSource => _lastSource;
  bool get downloading => _downloading;

  /// Why the most recent download failed, in Polish for display; `null` after a success.
  String? get lastError => _lastError;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _remoteUrl = _parse(prefs.getString(_remoteUrlKey));
    _localUrl = _parse(prefs.getString(_localUrlKey));
    _localWifi = prefs.getString(_localWifiKey);
    final ms = prefs.getInt(_lastSyncKey);
    _lastSync = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
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
        'Nieprawidłowy adres (np. http://serwer:8000/)',
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
  /// today. A failed attempt doesn't count, so the next start tries again.
  Future<void> syncIfDue() async {
    final last = _lastSync;
    final now = _now();
    final doneToday =
        last != null &&
        last.year == now.year &&
        last.month == now.month &&
        last.day == now.day;
    if (!hasSource || doneToday) return;
    await syncNow();
  }

  /// Downloads all files; returns whether it succeeded. The previous copy stays in place
  /// until all new files have arrived and look like SQLite databases, so a half-finished
  /// download never leaves the files out of step with each other.
  Future<bool> syncNow() async {
    if (!hasSource || _downloading) return false;
    _downloading = true;
    _lastError = null;
    notifyListeners();
    try {
      final attempts = await _attempts();
      if (attempts.isEmpty) {
        throw const _SyncFailure(
          'Telefon nie jest w sieci lokalnej, a adres zdalny nie jest ustawiony',
        );
      }
      Object? failure;
      for (final (source, url) in attempts) {
        try {
          await _downloadAll(url);
          _lastSync = _now();
          _lastSource = source;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(_lastSyncKey, _lastSync!.millisecondsSinceEpoch);
          await prefs.setString(_lastSourceKey, source.name);
          return true;
        } catch (e) {
          failure = e;
        }
      }
      throw failure!;
    } catch (e) {
      _lastError = _describe(e);
      return false;
    } finally {
      _downloading = false;
      notifyListeners();
    }
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

  Future<void> _downloadAll(Uri base) async {
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
