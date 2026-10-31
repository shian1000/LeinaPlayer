import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One line of the [ErrorLog].
class ErrorLogEntry {
  const ErrorLogEntry(this.at, this.message);

  final DateTime at;
  final String message;

  String get line {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}:${two(at.second)} '
        '${message.replaceAll('\n', '\n    ')}';
  }
}

/// What went wrong lately, kept on the phone for "Zgłoś problem" (sharing checklist 4.3): every
/// `debugPrint` (the app reports its failures that way — "Loading … failed: …") and every
/// uncaught error, in `<support dir>/error_log.txt`. Entries older than [keepFor] and anything
/// past [maxBytes] are dropped; secrets are cut out before anything is stored ([scrub]).
/// Nothing leaves the phone unless the user sends a report through "Udostępnij".
class ErrorLog extends ChangeNotifier {
  ErrorLog({Future<Directory> Function()? directory, DateTime Function()? now})
    : _directory = directory ?? getApplicationSupportDirectory,
      _now = now ?? DateTime.now;

  /// The app's log, set up in `main.dart`.
  static final instance = ErrorLog();

  static const keepFor = Duration(days: 14);
  static const maxBytes = 500 * 1024;
  static const _fileName = 'error_log.txt';
  static final _lineStart = RegExp(
    r'^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d) ',
  );

  final Future<Directory> Function() _directory;
  final DateTime Function() _now;

  List<ErrorLogEntry> _entries = [];
  final _pending = <ErrorLogEntry>[];
  Future<void> _writes = Future.value();
  Timer? _flushSoon;

  /// Oldest first.
  List<ErrorLogEntry> get entries => List.unmodifiable(_entries);

  /// Tokens, passwords and API keys are replaced with "…", IP addresses and the names of
  /// Tailscale / home-network machines with the kind of network, and the account's name in
  /// `/users/<name>` and YouTube's signed stream addresses with placeholders, before a message
  /// is kept.
  static String scrub(String message) => message
      // Before the IPs: the stream's query carries the phone's IP and session ids.
      .replaceAll(_googleVideo, 'https://<googlevideo>')
      .replaceAllMapped(_userPath, (m) => '${m[1]}<konto>')
      // The whole header value: "Bearer <token>" must go with it.
      .replaceAllMapped(
        RegExp(
          r'(authorization["\x27]?\s*[:=]\s*)[^\n"\x27,;}]+',
          caseSensitive: false,
        ),
        (m) => '${m[1]}…',
      )
      .replaceAllMapped(
        RegExp(r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+'),
        (m) => '${m[1]} …',
      )
      .replaceAllMapped(
        RegExp(
          r'(token|password|haslo|hasło|secret|api[_-]?key|key)'
          r'(["\x27]?\s*[:=]\s*["\x27]?)([^\s"\x27&,;)}\]…]+)',
          caseSensitive: false,
        ),
        (m) => '${m[1]}${m[2]}…',
      )
      .replaceAllMapped(_ipv4, (m) => _ipv4Label(m))
      .replaceAll(_tailscaleName, '<Tailscale>')
      .replaceAll(_tailscaleIpv6, '<Tailscale>')
      .replaceAll(_localIpv6, '<sieć domowa>')
      .replaceAll(_localName, '<sieć domowa>');

  // A server's address tells whoever gets the report where the sender's server is (sharing
  // checklist 4.3); which kind of network it was is enough to diagnose. Public services'
  // names (itunes.apple.com…) stay.
  static final _ipv4 = RegExp(
    r'(?<![\d.])(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?![\d.]*\d)',
  );
  static final _googleVideo = RegExp(
    r'https?://[A-Za-z0-9.-]*\.googlevideo\.com/\S*',
    caseSensitive: false,
  );
  // The report goes to someone else, who doesn't need to know the sender's login.
  static final _userPath = RegExp(r'(/users/)[^/?#\s]+');
  static final _tailscaleName = RegExp(
    r'\b[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.ts\.net\b',
    caseSensitive: false,
  );
  static final _tailscaleIpv6 = RegExp(
    r'\[?fd7a:115c:a1e0:[0-9a-f:]*\]?',
    caseSensitive: false,
  );
  static final _localIpv6 = RegExp(
    r'\[?\b(fe80|f[cd][0-9a-f]{2}):[0-9a-f:%a-z]*\]?',
    caseSensitive: false,
  );
  static final _localName = RegExp(
    r'\b[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.(local|lan|home|internal|home\.arpa)\b',
    caseSensitive: false,
  );

  static String _ipv4Label(Match m) {
    final b = [for (var i = 1; i <= 4; i++) int.parse(m[i]!)];
    if (b.any((n) => n > 255)) return m[0]!;
    if (b[0] == 100 && b[1] >= 64 && b[1] < 128) return '<Tailscale>';
    if (b[0] == 10 ||
        b[0] == 127 ||
        (b[0] == 172 && b[1] >= 16 && b[1] < 32) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 169 && b[1] == 254)) {
      return '<sieć domowa>';
    }
    return '<IP>';
  }

  /// Reads the file, dropping what's too old or too much.
  Future<void> load() async {
    final file = await _file();
    if (!await file.exists()) return;
    final text = await file.readAsString();
    // Anything recorded before the file was read (early in start-up) stays, after it.
    _entries = [..._parse(text), ..._entries];
    _prune();
    notifyListeners();
  }

  /// Keeps [message] (now): in memory at once, in the file shortly after.
  void record(String message) {
    final entry = ErrorLogEntry(_now(), scrub(message.trim()));
    if (entry.message.isEmpty) return;
    _entries.add(entry);
    _pending.add(entry);
    _prune();
    notifyListeners();
    _flushSoon ??= Timer(const Duration(milliseconds: 500), () {
      _flushSoon = null;
      flush();
    });
  }

  /// Writes what [record] kept so far — rewriting the file when [_prune] dropped lines.
  Future<void> flush() {
    final done = _writes.then((_) async {
      if (_pending.isEmpty) return;
      _pending.clear();
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        _entries.map((e) => '${e.line}\n').join(),
        flush: true,
      );
    });
    _writes = done.catchError((Object _) {});
    return done;
  }

  Future<void> clear() async {
    _entries = [];
    _pending.clear();
    notifyListeners();
    _writes = _writes.then((_) async {
      final file = await _file();
      if (await file.exists()) await file.delete();
    });
    await _writes;
  }

  /// The whole log as text, newest last.
  String get text => _entries.map((e) => e.line).join('\n');

  void _prune() {
    final since = _now().subtract(keepFor);
    _entries.removeWhere((e) => e.at.isBefore(since));
    var size = _entries.fold<int>(0, (n, e) => n + e.line.length + 1);
    while (size > maxBytes && _entries.isNotEmpty) {
      size -= _entries.removeAt(0).line.length + 1;
    }
  }

  static List<ErrorLogEntry> _parse(String text) {
    final entries = <ErrorLogEntry>[];
    for (final line in text.split('\n')) {
      final m = _lineStart.firstMatch(line);
      if (m != null) {
        entries.add(
          ErrorLogEntry(
            DateTime(
              int.parse(m[1]!),
              int.parse(m[2]!),
              int.parse(m[3]!),
              int.parse(m[4]!),
              int.parse(m[5]!),
              int.parse(m[6]!),
            ),
            // Lines written before addresses were scrubbed get it on reading.
            scrub(line.substring(m.end)),
          ),
        );
      } else if (line.startsWith('    ') && entries.isNotEmpty) {
        final last = entries.removeLast();
        entries.add(
          ErrorLogEntry(
            last.at,
            '${last.message}\n${scrub(line.substring(4))}',
          ),
        );
      }
    }
    return entries;
  }

  Future<File> _file() async => File('${(await _directory()).path}/$_fileName');

  /// Sends every `debugPrint` and uncaught error to [instance] too (from `main`).
  static void captureApp() {
    final print = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      print(message, wrapWidth: wrapWidth);
      if (message != null) instance.record(message);
    };
    final flutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterError?.call(details);
      instance.record(
        'Błąd ekranu: ${details.exceptionAsString()}\n'
        '${details.stack?.toString().split('\n').take(8).join('\n') ?? ''}',
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      instance.record(
        'Nieobsłużony błąd: $error\n'
        '${stack.toString().split('\n').take(8).join('\n')}',
      );
      return false;
    };
  }
}
