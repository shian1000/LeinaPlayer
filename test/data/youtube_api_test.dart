import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/youtube_api.dart';

void main() {
  late HttpServer server;
  late YouTubeApi api;
  final requests = <({String path, Map<String, String> query, Object? body})>[];

  /// What the next requests are answered with, in turn; then 200 `{"id": "X"}`.
  final answers = <(int, Object?)>[];

  Map<String, Object?> error(String reason) => {
    'error': {
      'errors': [
        {'reason': reason},
      ],
    },
  };

  setUp(() async {
    requests.clear();
    answers.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      requests.add((
        path: request.uri.path,
        query: request.uri.queryParameters,
        body: body.isEmpty ? null : jsonDecode(body),
      ));
      expect(request.headers.value('authorization'), 'Bearer tok');
      final (status, answer) = answers.isEmpty
          ? (200, {'id': 'X'})
          : answers.removeAt(0);
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(answer));
      await request.response.close();
    });
    api = YouTubeApi(base: Uri.parse('http://127.0.0.1:${server.port}/v3/'));
  });

  tearDown(() => server.close(force: true));

  test('creates an unlisted playlist', () async {
    answers.add((200, {'id': 'PLnew'}));
    expect(await api.createPlaylist('tok', title: 'Moja'), 'PLnew');
    final sent = requests.single;
    expect(sent.path, '/v3/playlists');
    expect(sent.query['part'], 'snippet,status');
    expect(sent.body, {
      'snippet': {'title': 'Moja', 'description': ''},
      'status': {'privacyStatus': 'unlisted'},
    });
  });

  test('adds a video', () async {
    expect(await api.addVideo('tok', 'PL1', 'vid'), isTrue);
    final sent = requests.single;
    expect(sent.path, '/v3/playlistItems');
    expect(sent.query['part'], 'snippet');
    expect(sent.body, {
      'snippet': {
        'playlistId': 'PL1',
        'resourceId': {'kind': 'youtube#video', 'videoId': 'vid'},
      },
    });
  });

  test('a video YouTube does not have is skipped', () async {
    answers.add((404, error('videoNotFound')));
    expect(await api.addVideo('tok', 'PL1', 'vid'), isFalse);
  });

  test('retries a conflict', () async {
    answers.add((409, error('SERVICE_UNAVAILABLE')));
    expect(await api.addVideo('tok', 'PL1', 'vid'), isTrue);
    expect(requests, hasLength(2));
  });

  test(
    'tells the daily limit, a refused token and a deleted playlist apart',
    () async {
      answers.add((403, error('quotaExceeded')));
      await expectLater(
        api.addVideo('tok', 'PL1', 'vid'),
        throwsA(
          isA<YouTubeApiException>().having((e) => e.quota, 'quota', true),
        ),
      );
      answers.add((401, error('authError')));
      await expectLater(
        api.createPlaylist('tok', title: 'x'),
        throwsA(
          isA<YouTubeApiException>().having(
            (e) => e.unauthorized,
            'unauthorized',
            true,
          ),
        ),
      );
      answers.add((404, error('playlistNotFound')));
      await expectLater(
        api.addVideo('tok', 'PL1', 'vid'),
        throwsA(
          isA<YouTubeApiException>().having(
            (e) => e.playlistGone,
            'playlistGone',
            true,
          ),
        ),
      );
    },
  );

  test('no connection', () async {
    await server.close(force: true);
    await expectLater(
      api.addVideo('tok', 'PL1', 'vid'),
      throwsA(
        isA<YouTubeApiException>().having((e) => e.offline, 'offline', true),
      ),
    );
  });
}
