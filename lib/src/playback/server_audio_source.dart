// StreamAudioSource is just_audio's only way to feed the player bytes the app fetched itself.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';

import '../data/server_trust.dart';

/// A song streamed from MusicDatabase's server over HTTPS ([ServerTrust]). Android's player
/// fetches an `AudioSource.uri` itself and would refuse the server's own certificate, so the
/// bytes go through Dart's [HttpClient] with the pinned certificate instead; just_audio hands
/// them to the player through its local proxy. Byte ranges are passed on, so seeking works.
class ServerAudioSource extends StreamAudioSource {
  ServerAudioSource(this.uri, {super.tag});

  final Uri uri;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final client = ServerTrust.instance.client()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      final ranged = start != null || end != null;
      if (ranged) {
        // just_audio's end is exclusive, HTTP's inclusive.
        request.headers.set(
          HttpHeaders.rangeHeader,
          'bytes=${start ?? 0}-${end == null ? '' : end - 1}',
        );
      }
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final contentLength = response.contentLength >= 0
          ? response.contentLength
          : null;
      var offset = 0;
      int? sourceLength;
      final range = _contentRange.firstMatch(
        response.headers.value(HttpHeaders.contentRangeHeader) ?? '',
      );
      if (range != null) {
        offset = int.parse(range[1]!);
        sourceLength = int.tryParse(range[2]!);
      } else if (ranged) {
        // A whole file answered to a range request: its length is the source's.
        sourceLength = contentLength;
      }
      return StreamAudioResponse(
        sourceLength: ranged ? sourceLength : null,
        contentLength: contentLength,
        offset: ranged ? offset : null,
        contentType: response.headers.contentType?.mimeType ?? 'audio/mpeg',
        stream: _closingWhenDone(response, client),
      );
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  static final _contentRange = RegExp(r'^bytes (\d+)-\d+/(\d+|\*)$');

  /// [response]'s bytes, closing [client] once they're read or the player stops listening.
  static Stream<List<int>> _closingWhenDone(
    HttpClientResponse response,
    HttpClient client,
  ) async* {
    try {
      yield* response;
    } finally {
      client.close(force: true);
    }
  }
}
