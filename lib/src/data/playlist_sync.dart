import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'custom_covers.dart';

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

/// One answer of MusicDatabase's account endpoints: the HTTP status and its JSON body, if any.
typedef SyncAnswer = ({int status, Object? body});

/// The user's playlists on MusicDatabase's sharing server
/// ([ADR 0007](../../../docs/decisions/0007-playlist-sync.md); the server side is MusicDatabase's
/// `docs/handoffs/playlists-for-musicdatabaseapp.md`), or — with [collection] `moods` — their
/// moods, which follow the same rules ([ADR 0008](../../../docs/decisions/0008-moods.md)). Only
/// HTTP: what to send and what to do with the answers is [PlaylistLibrary.sync]'s and
/// `MoodLibrary.sync`'s.
class PlaylistSyncClient {
  PlaylistSyncClient(
    this.server,
    this.userName,
    this.token, {
    this.collection = 'playlists',
  }) : _client = HttpClient()..connectionTimeout = connectTimeout;

  static const connectTimeout = Duration(seconds: 8);

  /// A 5000-track playlist is ~1.5 MB of JSON; on a slow mobile connection that takes a while.
  static const answerTimeout = Duration(seconds: 30);

  final Uri server;
  final String userName;
  final String token;
  final String collection;
  final HttpClient _client;

  Uri _uri(String path, [Map<String, String>? query]) => server
      .resolve('/users/${Uri.encodeComponent(userName)}/$collection$path')
      .replace(queryParameters: query);

  /// With [limit], at most that many (MusicDatabase says whether `more` are left).
  Future<SyncAnswer> changedSince(int revision, {int? limit}) => _call(
    'GET',
    _uri('', {'since': '$revision', if (limit != null) 'limit': '$limit'}),
  );

  /// Several items at once (the listening stats' plays).
  Future<SyncAnswer> post(Map<String, Object?> body) =>
      _call('POST', _uri(''), body);

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

  Uri _coverUri(String hash) =>
      server.resolve('/users/${Uri.encodeComponent(userName)}/covers/$hash');

  /// Uploads a cover picture ([ADR 0009](../../../docs/decisions/0009-cover-sync.md)); 200 or
  /// 201 when MusicDatabase has it.
  Future<int> putCover(
    String hash,
    List<int> bytes, {
    required bool jpeg,
  }) async {
    final request = await _client
        .openUrl('PUT', _coverUri(hash))
        .timeout(connectTimeout);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType('image', jpeg ? 'jpeg' : 'png');
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close().timeout(answerTimeout);
    await response.drain<void>().timeout(answerTimeout);
    return response.statusCode;
  }

  /// Downloads a cover picture: its bytes when MusicDatabase has it (200), else `null`.
  Future<({List<int> bytes, bool jpeg})?> getCover(String hash) async {
    final request = await _client
        .openUrl('GET', _coverUri(hash))
        .timeout(connectTimeout);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close().timeout(answerTimeout);
    final bytes = await response
        .fold(BytesBuilder(copy: false), (b, chunk) => b..add(chunk))
        .timeout(answerTimeout);
    if (response.statusCode != HttpStatus.ok) return null;
    return (
      bytes: bytes.takeBytes(),
      jpeg: response.headers.contentType?.subType == 'jpeg',
    );
  }

  /// The user as MusicDatabase sees them now: `{"username", "permissions": [...]}`.
  Future<SyncAnswer> user() =>
      _call('GET', server.resolve('/users/${Uri.encodeComponent(userName)}'));

  /// `PUT` (add) or `DELETE` (remove) [songId] in the global mood [moodId]; needs the
  /// `edit_global_moods` permission.
  Future<SyncAnswer> changeGlobalMood(int moodId, int songId, bool add) =>
      _call(
        add ? 'PUT' : 'DELETE',
        server.resolve('/global-moods/$moodId/songs/$songId'),
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
        debugPrint('Sync: bad JSON from $uri: $e');
      }
    }
    return (status: response.statusCode, body: decoded);
  }

  void close() => _client.close(force: true);
}

/// MusicDatabase refused a PUT naming a cover it has no picture of yet.
bool isCoverMissing(SyncAnswer answer) =>
    answer.status == HttpStatus.badRequest &&
    answer.body is Map &&
    (answer.body! as Map)['error'] == 'cover_missing';

/// PUTs [body] (a playlist, mood or global mood cover with its `cover` hash) as [id]. The
/// picture is uploaded only when MusicDatabase says it hasn't got it, then the PUT goes once
/// more — most PUTs keep a cover sent before. A picture lost on the phone isn't named, so the
/// stored cover stays — unless the key is [required] (a global mood's cover), which stays refused.
Future<SyncAnswer> putWithCover(
  PlaylistSyncClient client,
  CustomCovers? covers,
  String id,
  Map<String, Object?> body, {
  bool required = false,
}) async {
  final answer = await client.put(id, body);
  final hash = body['cover'];
  if (!isCoverMissing(answer) || hash is! String) return answer;
  final picture = await covers?.read(hash);
  if (picture == null) {
    return required ? answer : client.put(id, {...body}..remove('cover'));
  }
  final status = await client.putCover(hash, picture.bytes, jpeg: picture.jpeg);
  if (status != HttpStatus.ok && status != HttpStatus.created) {
    debugPrint('Uploading cover $hash: HTTP $status');
    return answer;
  }
  return client.put(id, body);
}

/// Downloads the covers among [hashes] the phone hasn't got; one that fails waits for the
/// next sync.
Future<void> fetchCovers(
  PlaylistSyncClient client,
  CustomCovers? covers,
  Iterable<String> hashes,
) async {
  if (covers == null) return;
  for (final hash in hashes.toSet()) {
    if (covers.fileFor(hash) != null) continue;
    try {
      final picture = await client.getCover(hash);
      if (picture == null) continue;
      await covers.store(hash, picture.bytes, jpeg: picture.jpeg);
    } catch (e) {
      debugPrint('Downloading cover $hash failed: $e');
    }
  }
}

/// How the last [PlaylistLibrary.sync] went.
class PlaylistSyncResult {
  const PlaylistSyncResult({required this.at, this.problem});

  final DateTime at;

  /// Why something is still waiting (Polish, for display); `null` when everything went.
  final String? problem;
}
