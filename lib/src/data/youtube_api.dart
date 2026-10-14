import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Why a YouTube Data API call failed. [quota]: the project's daily limit is used up (it
/// resets at midnight Pacific time); [unauthorized]: the access token was refused.
class YouTubeApiException implements Exception {
  const YouTubeApiException(
    this.message, {
    this.quota = false,
    this.unauthorized = false,
    this.offline = false,
    this.playlistGone = false,
  });

  final String message;
  final bool quota;
  final bool unauthorized;
  final bool offline;

  /// The playlist videos were being added to isn't on YouTube any more.
  final bool playlistGone;

  @override
  String toString() => message;
}

/// The two YouTube Data API v3 calls the phone makes: a new playlist and a video added to it
/// (MusicDatabase's `create_playlist()` / `add_video_to_playlist()` in
/// `manage_youtube_playlists.py`). Each costs 50 of the project's 10 000 daily units, so about
/// 200 songs a day. Searching never goes through the API — the phone's own matcher does it.
class YouTubeApi {
  YouTubeApi({Uri? base, this.timeout = const Duration(seconds: 20)})
    : _base = base ?? Uri.parse('https://www.googleapis.com/youtube/v3/');

  final Uri _base;
  final Duration timeout;

  /// A new unlisted playlist (user's choice: shareable by link, not listed on the channel);
  /// returns its id.
  Future<String> createPlaylist(
    String token, {
    required String title,
    String description = '',
  }) async {
    try {
      final answer = await _post(token, 'playlists', {
        'snippet': {'title': title, 'description': description},
        'status': {'privacyStatus': 'unlisted'},
      });
      return answer['id']! as String;
    } on _HttpFailure catch (e) {
      throw e.toApiException();
    }
  }

  /// Adds [videoId] at the end of [playlistId]. Returns `false` when YouTube doesn't have the
  /// video (removed, private): that song is skipped. Retries what MusicDatabase retries (409,
  /// 500, 503 — YouTube answers 409 to inserts sent too quickly one after another).
  Future<bool> addVideo(String token, String playlistId, String videoId) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await _post(token, 'playlistItems', {
          'snippet': {
            'playlistId': playlistId,
            'resourceId': {'kind': 'youtube#video', 'videoId': videoId},
          },
        });
        return true;
      } on _HttpFailure catch (e) {
        if (e.status == HttpStatus.notFound && e.reason == 'videoNotFound') {
          return false;
        }
        if (const {409, 500, 503}.contains(e.status) && attempt < 2) {
          await Future<void>.delayed(Duration(seconds: 1 + attempt));
          continue;
        }
        throw e.toApiException();
      }
    }
  }

  Future<Map<String, Object?>> _post(
    String token,
    String resource,
    Map<String, Object?> body,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(
            _base.resolveUri(
              Uri(
                path: resource,
                queryParameters: {'part': body.keys.join(',')},
              ),
            ),
          )
          .timeout(timeout);
      final bytes = utf8.encode(jsonEncode(body));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(timeout);
      final text = await utf8.decodeStream(response).timeout(timeout);
      if (response.statusCode == HttpStatus.ok) {
        return jsonDecode(text) as Map<String, Object?>;
      }
      throw _HttpFailure(response.statusCode, text);
    } on _HttpFailure {
      rethrow;
    } on Exception catch (e) {
      debugPrint('YouTube API $resource failed: $e');
      throw const YouTubeApiException(
        'Brak połączenia z YouTube',
        offline: true,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class _HttpFailure implements Exception {
  _HttpFailure(this.status, this.body);
  final int status;
  final String body;

  /// The first `error.errors[].reason`, e.g. `quotaExceeded`.
  late final String? reason = () {
    try {
      final error = (jsonDecode(body) as Map)['error'] as Map;
      return ((error['errors'] as List).first as Map)['reason'] as String?;
    } catch (_) {
      return null;
    }
  }();

  YouTubeApiException toApiException() {
    debugPrint('YouTube API HTTP $status: $body');
    if (status == HttpStatus.unauthorized) {
      return const YouTubeApiException(
        'Google nie przyjął logowania — spróbuj ponownie',
        unauthorized: true,
      );
    }
    if (reason == 'quotaExceeded' || reason == 'dailyLimitExceeded') {
      return const YouTubeApiException(
        'Wyczerpany dzienny limit YouTube — dokończ jutro',
        quota: true,
      );
    }
    if (reason == 'playlistNotFound') {
      return const YouTubeApiException(
        'Tej playlisty nie ma już na YouTube',
        playlistGone: true,
      );
    }
    if (reason == 'youtubeSignupRequired') {
      return const YouTubeApiException(
        'To konto Google nie ma kanału YouTube — załóż go w aplikacji YouTube',
      );
    }
    if (reason == 'accessNotConfigured' || reason == 'SERVICE_DISABLED') {
      return const YouTubeApiException(
        'YouTube Data API nie jest włączone w projekcie Google Cloud',
      );
    }
    return YouTubeApiException('YouTube odpowiedział: HTTP $status');
  }
}
