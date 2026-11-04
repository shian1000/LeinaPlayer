import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/server_trust.dart';
import 'package:music_database_app/src/playback/server_audio_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tls.dart';

void main() {
  late HttpServer server;
  late Uri base;
  final audio = List<int>.generate(1000, (i) => i % 256);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerTrust.instance.load();
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      testServerContext(),
    );
    base = Uri.parse('https://127.0.0.1:${server.port}/');
    server.listen((request) {
      final response = request.response;
      if (request.uri.path != '/library/7') {
        response.statusCode = HttpStatus.ok;
        response.write('ok');
        response.close();
        return;
      }
      response.headers.contentType = ContentType('audio', 'mpeg');
      final range = RegExp(r'bytes=(\d+)-(\d*)')
          .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
      if (range == null) {
        response.contentLength = audio.length;
        response.add(audio);
      } else {
        final start = int.parse(range[1]!);
        final end = range[2]!.isEmpty ? audio.length - 1 : int.parse(range[2]!);
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${audio.length}',
        );
        response.contentLength = end - start + 1;
        response.add(audio.sublist(start, end + 1));
      }
      response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Future<int> statusWith(HttpClient client) async {
    try {
      final response = await (await client.getUrl(base)).close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  test('the code is base32 of the SHA-256, 12 characters in groups', () {
    // Python: base64.b32encode(bytes(range(32)))[:12] — MusicDatabase's server works it out so.
    expect(codeOfDigest(List.generate(32, (i) => i)), 'AAAQ-EAYE-AUDA');
    expect(
      codeOfDigest(sha256.convert('x'.codeUnits).bytes),
      matches(RegExp(r'^[A-Z2-7]{4}-[A-Z2-7]{4}-[A-Z2-7]{4}$')),
    );
  });

  test('an own certificate is refused until it is pinned', () async {
    final trust = ServerTrust.instance;
    await expectLater(
      statusWith(trust.client()),
      throwsA(isA<HandshakeException>()),
    );

    final check = await trust.check(base);
    expect(check, isA<CertificateUnknown>());
    final unknown = check as CertificateUnknown;
    expect(unknown.code, testCertificateCode);

    await trust.pin(unknown.certificate);
    expect(await statusWith(trust.client()), HttpStatus.ok);
    expect(await trust.check(base), isA<CertificateTrusted>());
  });

  test(
    'a pinned certificate is remembered across starts and can be forgotten',
    () async {
      final trust = ServerTrust.instance;
      final unknown = await trust.check(base) as CertificateUnknown;
      await trust.pin(unknown.certificate);

      await trust.load();
      expect(trust.hasPins, isTrue);
      expect(await trust.check(base), isA<CertificateTrusted>());

      await trust.forgetAll();
      await trust.load();
      expect(trust.hasPins, isFalse);
      expect(await trust.check(base), isA<CertificateUnknown>());
    },
  );

  test('plain HTTP needs no pin, and a closed port is unreachable', () async {
    final plain = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    plain.listen((request) => request.response.close());
    final port = plain.port;
    expect(
      await ServerTrust.instance.check(Uri.parse('http://127.0.0.1:$port/')),
      isA<CertificateTrusted>(),
    );
    await plain.close(force: true);
    expect(
      await ServerTrust.instance.check(Uri.parse('http://127.0.0.1:$port/')),
      isA<CertificateUnreachable>(),
    );
  });

  group('ServerAudioSource', () {
    setUp(() async {
      final unknown =
          await ServerTrust.instance.check(base) as CertificateUnknown;
      await ServerTrust.instance.pin(unknown.certificate);
    });

    Future<List<int>> read(Stream<List<int>> stream) async => [
      for (final chunk in await stream.toList()) ...chunk,
    ];

    test('streams the whole file', () async {
      final source = ServerAudioSource(base.resolve('library/7'));
      final response = await source.request();
      expect(response.contentType, 'audio/mpeg');
      expect(response.contentLength, audio.length);
      expect(response.sourceLength, isNull);
      expect(await read(response.stream), audio);
    });

    test('passes a byte range on (end exclusive)', () async {
      final source = ServerAudioSource(base.resolve('library/7'));
      final response = await source.request(100, 200);
      expect(response.offset, 100);
      expect(response.sourceLength, audio.length);
      expect(response.contentLength, 100);
      expect(await read(response.stream), audio.sublist(100, 200));

      final tail = await source.request(900);
      expect(tail.offset, 900);
      expect(await read(tail.stream), audio.sublist(900));
    });

    test('fails on an unpinned certificate', () async {
      await ServerTrust.instance.forgetAll();
      final source = ServerAudioSource(base.resolve('library/7'));
      await expectLater(source.request(), throwsA(isA<HandshakeException>()));
    });
  });
}
