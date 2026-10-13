import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// MusicDatabase's cover blobs (`/users/<name>/covers/<sha256>`, its `covers.py`), cut down to
/// what the phone relies on; shared by the fake playlist and mood servers.
class FakeCoverBlobs {
  final blobs = <String, List<int>>{};

  /// Answers [request] when it's for a blob ([body] is its raw body); `false` otherwise.
  bool handle(HttpRequest request, List<int> body) {
    final parts = request.uri.pathSegments;
    if (parts.length != 4 || parts[0] != 'users' || parts[2] != 'covers') {
      return false;
    }
    final hash = parts[3];
    final response = request.response;
    if (request.method == 'PUT') {
      if (sha256.convert(body).toString() != hash) {
        response.statusCode = HttpStatus.badRequest;
      } else {
        response.statusCode = blobs.containsKey(hash)
            ? HttpStatus.ok
            : HttpStatus.created;
        blobs[hash] = body;
      }
    } else if (blobs[hash] case final bytes?) {
      response.headers.contentType = ContentType('image', 'png');
      response.add(bytes);
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    response.close();
    return true;
  }

  /// The 400 MusicDatabase answers a PUT naming a cover it hasn't got, or `null` when [sent]'s
  /// cover is fine.
  Map<String, Object?>? missing(Map<String, Object?> sent) {
    final cover = sent['cover'];
    if (cover is! String || blobs.containsKey(cover)) return null;
    return {'error': 'cover_missing', 'cover': cover};
  }
}

/// The whole body of [request], for routing a blob before decoding JSON.
Future<List<int>> readBody(HttpRequest request) =>
    request.fold(<int>[], (all, chunk) => all..addAll(chunk));

/// [bytes] as JSON text.
String textOf(List<int> bytes) => utf8.decode(bytes);
