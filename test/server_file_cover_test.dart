import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/playback/track_player.dart';

/// An MP3 with an ID3v2 tag of [tagSize] bytes (after its header), then [audio] bytes of audio.
Uint8List _mp3({int tagSize = 300, int audio = 5000}) {
  final size = [
    (tagSize >> 21) & 0x7f,
    (tagSize >> 14) & 0x7f,
    (tagSize >> 7) & 0x7f,
    tagSize & 0x7f,
  ];
  return Uint8List.fromList([
    ...'ID3'.codeUnits,
    4,
    0,
    0,
    ...size,
    ...List.filled(tagSize, 1),
    ...List.filled(audio, 2),
  ]);
}

void main() {
  late HttpServer server;
  late Uint8List file;
  late bool honourRange;
  late List<String?> ranges;

  setUp(() async {
    file = _mp3();
    honourRange = true;
    ranges = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      final response = request.response;
      if (request.uri.path != '/library/42') {
        response.statusCode = HttpStatus.notFound;
        response.close();
        return;
      }
      final range = request.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      final match = RegExp(r'^bytes=0-(\d+)$').firstMatch(range ?? '');
      if (honourRange && match != null) {
        final last = int.parse(match.group(1)!).clamp(0, file.length - 1);
        response.statusCode = HttpStatus.partialContent;
        response.add(file.sublist(0, last + 1));
      } else {
        response.add(file);
      }
      response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Uri at(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  test('only the ID3 tag is fetched, not the song', () async {
    final head = await fetchServerFileHead(at('/library/42'));
    expect(head, hasLength(310));
    expect(head!.last, 1);
    expect(ranges, ['bytes=0-9', 'bytes=0-309']);
  });

  test('a server ignoring the range still gives just the tag', () async {
    honourRange = false;
    expect(await fetchServerFileHead(at('/library/42')), hasLength(310));
  });

  test('a file without an ID3 tag or one the server lacks has none', () async {
    file = Uint8List.fromList(List.filled(100, 2));
    expect(await fetchServerFileHead(at('/library/42')), isNull);
    expect(await fetchServerFileHead(at('/library/9')), isNull);
  });

  test('an unreachable server is an error, not "no cover"', () {
    expect(
      fetchServerFileHead(Uri.parse('http://127.0.0.1:1/library/42')),
      throwsA(isA<SocketException>()),
    );
  });

  test('the tag length counts the header and a footer', () {
    expect(id3TagLength(_mp3(tagSize: 103086)), 103096);
    expect(id3TagLength([...'ID3'.codeUnits, 4, 0, 0x10, 0, 0, 1, 0]), 148);
    expect(id3TagLength('RIFF......'.codeUnits), isNull);
  });
}
