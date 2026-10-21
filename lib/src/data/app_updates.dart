import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_errors.dart';

/// The GitHub repository whose releases carry this app's APK, `<owner>/<repo>`, set at build
/// time from the git-ignored `tool/release.env` (`tool/build_release_apk.sh`). Empty in a build
/// without it — someone else's: their APK is signed with another key and couldn't install the
/// owner's releases anyway, so there is nothing to offer.
const updateRepo = String.fromEnvironment('UPDATE_REPO');

const _buildNumber = String.fromEnvironment('BUILD_NUMBER');

/// The build number (the commit count, `tool/build_info.sh`) of the running app: BUILD_NUMBER
/// from `tool/build_release_apk.sh`, else derived from Android's [versionCode] — which
/// `android/app/build.gradle.kts` sets to build × 10 + variant, so it isn't the build number.
String buildNumberOf(String versionCode) {
  if (_buildNumber.isNotEmpty) return _buildNumber;
  final code = int.tryParse(versionCode);
  return code != null && Platform.isAndroid ? '${code ~/ 10}' : versionCode;
}

/// Which APK is installed, from the last digit of Android's [versionCode]
/// (`android/app/build.gradle.kts`): `true` the universal one, `false` a split one, `null` when
/// unknown (not Android, or a build from before that numbering).
bool? isUniversalApk(String versionCode) {
  final code = int.tryParse(versionCode);
  if (code == null || !Platform.isAndroid || code < 100) return null;
  return switch (code % 10) {
    9 => true,
    1 || 2 || 4 => false,
    _ => null,
  };
}

/// The Android ABI name the running app was built for, as in the split APKs' file names.
String? get currentAndroidAbi => switch (Abi.current()) {
  Abi.androidArm64 => 'arm64-v8a',
  Abi.androidArm => 'armeabi-v7a',
  Abi.androidX64 => 'x86_64',
  _ => null,
};

/// The split APKs' ABI names (`app-<abi>-release.apk`, `tool/prepare_release.sh`).
const _abis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

/// A newer release found on GitHub.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.pageUrl,
    required this.notes,
  });

  /// `1.0.0` of the tag `1.0.0+58`.
  final String version;

  /// `58` of the tag `1.0.0+58` — compared with the installed build's number.
  final int buildNumber;

  /// The release's APK for this phone's CPU ([abi] in its name), else its universal one (no
  /// ABI in the name); downloaded by the browser, which hands it to Android's installer (no
  /// install permission in the app — owner's choice).
  final Uri apkUrl;

  final Uri pageUrl;

  /// The release's description as written on GitHub.
  final String notes;

  String get label => '$version ($buildNumber)';

  Map<String, Object?> toJson() => {
    'version': version,
    'build': buildNumber,
    'apk': apkUrl.toString(),
    'page': pageUrl.toString(),
    'notes': notes,
  };

  static AppRelease fromJson(Map<String, Object?> json) => AppRelease(
    version: json['version']! as String,
    buildNumber: json['build']! as int,
    apkUrl: Uri.parse(json['apk']! as String),
    pageUrl: Uri.parse(json['page']! as String),
    notes: json['notes'] as String? ?? '',
  );

  /// The release in GitHub's `releases/latest` answer, or `null` when its tag isn't
  /// `<version>+<build>` or it has no APK this phone ([abi]) can install.
  static AppRelease? fromGitHub(Map<String, Object?> json, {String? abi}) {
    final tag = RegExp(r'^v?([0-9][0-9A-Za-z.\-]*)\+([0-9]+)$')
        .firstMatch(json['tag_name'] as String? ?? '');
    if (tag == null) return null;
    final apks = <String, String>{
      for (final asset in json['assets'] as List? ?? const [])
        if (asset is Map &&
            (asset['name'] as String? ?? '').toLowerCase().endsWith('.apk') &&
            asset['browser_download_url'] is String)
          (asset['name'] as String).toLowerCase():
              asset['browser_download_url'] as String,
    };
    final forAbi = abi == null
        ? null
        : apks.entries.where((e) => e.key.contains(abi)).firstOrNull;
    final universal = apks.entries
        .where((e) => !_abis.any(e.key.contains))
        .firstOrNull;
    final apk = (forAbi ?? universal)?.value;
    if (apk == null) return null;
    return AppRelease(
      version: tag.group(1)!,
      buildNumber: int.parse(tag.group(2)!),
      apkUrl: Uri.parse(apk),
      pageUrl: Uri.parse(json['html_url'] as String? ?? apk),
      // GitHub keeps the description as typed in the browser, with \r\n line ends.
      notes: (json['body'] as String? ?? '').replaceAll('\r\n', '\n').trim(),
    );
  }
}

/// Checks the app's GitHub releases for a newer build: once a day on start or return to the
/// app (unless switched off — Ustawienia › Informacje i pomoc), and on request. A newer one is
/// offered once in a dialog ([shouldOffer], [dismiss]) and stays shown in Informacje i pomoc.
class AppUpdates extends ChangeNotifier {
  AppUpdates({
    this.repo = updateRepo,
    required this.installedBuild,
    Uri? apiBase,
    DateTime Function()? now,
    String? abi,
  }) : abi = abi ?? currentAndroidAbi,
       _apiBase = apiBase ?? Uri.parse('https://api.github.com/'),
       _now = now ?? DateTime.now;

  static const _autoKey = 'updates.auto_check';
  static const _lastCheckKey = 'updates.last_check_ms';
  static const _latestKey = 'updates.latest';
  static const _dismissedKey = 'updates.dismissed_build';

  /// `<owner>/<repo>` whose releases are checked; empty = no checks ([configured]).
  final String repo;

  /// The installed build's number ([buildNumberOf]).
  final Future<int> Function() installedBuild;

  /// This phone's CPU, picking the release's APK ([currentAndroidAbi]).
  final String? abi;
  final Uri _apiBase;
  final DateTime Function() _now;

  bool _autoCheck = true;
  DateTime? _lastCheck;
  AppRelease? _latest;
  int? _installed;
  int? _dismissed;
  bool _checking = false;
  String? _problem;

  /// Whether this build knows where its releases are; without it nothing is checked or shown.
  bool get configured => repo.isNotEmpty;

  bool get autoCheck => _autoCheck;
  bool get checking => _checking;
  DateTime? get lastCheck => _lastCheck;

  /// Why the last check failed (Polish, for display); `null` when it went or before the first.
  String? get problem => _problem;

  /// The newest release when it's newer than the installed build.
  AppRelease? get available {
    final latest = _latest;
    final installed = _installed;
    if (latest == null || installed == null) return null;
    return latest.buildNumber > installed ? latest : null;
  }

  /// A newer release the user hasn't answered "Później" to yet.
  bool get shouldOffer {
    final release = available;
    return release != null && release.buildNumber != _dismissed;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _autoCheck = prefs.getBool(_autoKey) ?? true;
    final last = prefs.getInt(_lastCheckKey);
    _lastCheck = last == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(last);
    _dismissed = prefs.getInt(_dismissedKey);
    final latest = prefs.getString(_latestKey);
    if (latest != null) {
      try {
        _latest = AppRelease.fromJson(
          (jsonDecode(latest) as Map).cast<String, Object?>(),
        );
      } catch (_) {
        _latest = null;
      }
    }
    _installed = await installedBuild();
    notifyListeners();
  }

  Future<void> setAutoCheck(bool value) async {
    _autoCheck = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_autoKey, value);
  }

  /// "Później": no more dialogs for this release; it stays in Informacje i pomoc.
  Future<void> dismiss() async {
    final release = available;
    if (release == null) return;
    _dismissed = release.buildNumber;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(
      _dismissedKey,
      release.buildNumber,
    );
  }

  /// Checks unless switched off or already checked today.
  Future<void> checkIfDue() async {
    if (!configured || !_autoCheck) return;
    final last = _lastCheck;
    final now = _now();
    if (last != null &&
        last.year == now.year &&
        last.month == now.month &&
        last.day == now.day) {
      return;
    }
    await check();
  }

  /// Asks GitHub for the newest release now.
  Future<void> check() async {
    if (!configured || _checking) return;
    _checking = true;
    notifyListeners();
    try {
      final json = await _fetchLatest();
      _latest = json == null ? null : AppRelease.fromGitHub(json, abi: abi);
      _installed = await installedBuild();
      _problem = null;
      _lastCheck = _now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckKey, _lastCheck!.millisecondsSinceEpoch);
      final latest = _latest;
      if (latest == null) {
        await prefs.remove(_latestKey);
      } else {
        await prefs.setString(_latestKey, jsonEncode(latest.toJson()));
      }
    } catch (e) {
      _problem = isNetworkError(e)
          ? 'Brak połączenia z internetem'
          : 'Nie udało się sprawdzić aktualizacji ($e)';
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// GitHub's newest release, or `null` when the repository has none yet (404).
  Future<Map<String, Object?>?> _fetchLatest() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(_apiBase.resolve('repos/$repo/releases/latest'))
          .timeout(const Duration(seconds: 15));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'LeinaRadio');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == HttpStatus.notFound) return null;
      if (response.statusCode != HttpStatus.ok) {
        // Not an HttpException: that one reads as "no connection" (isNetworkError).
        throw _GitHubRefused(response.statusCode);
      }
      return (jsonDecode(body) as Map).cast<String, Object?>();
    } finally {
      client.close(force: true);
    }
  }
}

class _GitHubRefused implements Exception {
  const _GitHubRefused(this.status);

  final int status;

  @override
  String toString() => 'GitHub: HTTP $status';
}

class AppUpdatesScope extends InheritedNotifier<AppUpdates> {
  const AppUpdatesScope({
    super.key,
    required AppUpdates super.notifier,
    required super.child,
  });

  /// `null` in widget tests that don't set it up.
  static AppUpdates? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppUpdatesScope>()?.notifier;
}
