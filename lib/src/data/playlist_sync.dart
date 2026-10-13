import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// A new playlist id shared with MusicDatabase (`playlists.uid` on both sides): a random UUID v4.
String newPlaylistUid() {
  final random = Random.secure();
  final bytes = [for (var i = 0; i < 16; i++) random.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')]
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// One answer of MusicDatabase's playlist endpoints: the HTTP status and its JSON body, if any.
typedef SyncAnswer = ({int status, Object? body});

/// The user's playlists on MusicDatabase's sharing server
/// ([ADR 0007](../../../docs/decisions/0007-playlist-sync.md); the server side is MusicDatabase's
/// `docs/handoffs/playlists-for-musicdatabaseapp.md`). Only HTTP: what to send and what to do
/// with the answers is [PlaylistLibrary.sync]'s.
class PlaylistSyncClient {
  PlaylistSyncClient(this.server, this.userName, this.token)
    : _client = HttpClient()..connectionTimeout = connectTimeout;

  static const connectTimeout = Duration(seconds: 8);

  /// A 5000-track playlist is ~1.5 MB of JSON; on a slow mobile connection that takes a while.
  static const answerTimeout = Duration(seconds: 30);

  final Uri server;
  final String userName;
  final String token;
  final HttpClient _client;

  Uri _uri(String path, [Map<String, String>? query]) => server
      .resolve('/users/${Uri.encodeComponent(userName)}/playlists$path')
      .replace(queryParameters: query);

  Future<SyncAnswer> changedSince(int revision) =>
      _call('GET', _uri('', {'since': '$revision'}));

  Future<SyncAnswer> put(String uid, Map<String, Object?> playlist) =>
      _call('PUT', _uri('/$uid'), playlist);

  Future<SyncAnswer> delete(String uid, int baseRevision, int deletedAt) =>
      _call(
        'DELETE',
        _uri('/$uid', {
          'base_revision': '$baseRevision',
          'deleted_at': '$deletedAt',
        }),
      );

  Future<SyncAnswer> _call(
    String method,
    Uri uri, [
    Map<String, Object?>? json,
  ]) async {
    final request = await _client.openUrl(method, uri).timeout(connectTimeout);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    // MusicDatabase's server needs Content-Length (411 for a chunked body).
    final body = json == null ? const <int>[] : utf8.encode(jsonEncode(json));
    if (json != null) request.headers.contentType = ContentType.json;
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close().timeout(answerTimeout);
    final text = await utf8.decodeStream(response).timeout(answerTimeout);
    Object? decoded;
    if (response.headers.contentType?.mimeType == ContentType.json.mimeType) {
      try {
        decoded = jsonDecode(text);
      } on FormatException catch (e) {
        debugPrint('Playlist sync: bad JSON from $uri: $e');
      }
    }
    return (status: response.statusCode, body: decoded);
  }

  void close() => _client.close(force: true);
}

/// How the last [PlaylistLibrary.sync] went.
class PlaylistSyncResult {
  const PlaylistSyncResult({required this.at, this.problem});

  final DateTime at;

  /// Why something is still waiting (Polish, for display); `null` when everything went.
  final String? problem;
}
