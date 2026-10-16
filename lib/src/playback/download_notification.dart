import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android notification "Pobieranie utworów" (`DownloadService.kt`, a `dataSync` foreground
/// service): while it shows, Android neither freezes nor readily kills the app, so downloads go
/// on with the screen off. Missing (tests, iOS): nothing happens.
class DownloadNotification {
  const DownloadNotification();

  static const _channel = MethodChannel('music_database_app/downloads');

  /// Shows or updates it: [done] of [total] songs, [title] the one downloading now.
  Future<void> show({
    required int done,
    required int total,
    required String title,
  }) => _call('show', {'done': done, 'total': total, 'title': title});

  Future<void> hide() => _call('hide');

  Future<void> _call(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // No Android side here.
    } catch (e) {
      debugPrint('Download notification ($method) failed: $e');
    }
  }
}
