import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/app_updates.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late HttpServer gitHub;
  late List<String> requests;
  late int status;
  late Map<String, Object?> latest;
  late DateTime now;
  late int installed;

  Map<String, Object?> release(String tag, {List<String>? assets}) => {
    'tag_name': tag,
    'html_url': 'https://github.com/owner/repo/releases/tag/$tag',
    'body': '- Nowość\n- Poprawka\n',
    'assets': [
      for (final name in assets ?? ['LeinaRadio-$tag.apk'])
        {
          'name': name,
          'browser_download_url':
              'https://github.com/owner/repo/releases/download/$tag/$name',
        },
    ],
  };

  AppUpdates newUpdates({String repo = 'owner/repo'}) => AppUpdates(
    repo: repo,
    installedBuild: () async => installed,
    apiBase: Uri.parse('http://127.0.0.1:${gitHub.port}/'),
    now: () => now,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    requests = [];
    status = HttpStatus.ok;
    latest = release('1.0.0+58');
    now = DateTime(2026, 10, 21, 9);
    installed = 57;
    gitHub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    gitHub.listen((request) {
      requests.add('${request.method} ${request.uri.path}');
      request.response.statusCode = status;
      request.response.write(jsonEncode(latest));
      request.response.close();
    });
  });

  tearDown(() async {
    await gitHub.close(force: true);
  });

  test('a newer release is offered until answered "Później"', () async {
    final updates = newUpdates();
    await updates.load();
    await updates.check();

    expect(requests, ['GET /repos/owner/repo/releases/latest']);
    final found = updates.available!;
    expect(found.version, '1.0.0');
    expect(found.buildNumber, 58);
    expect(found.label, '1.0.0 (58)');
    expect(
      found.apkUrl.toString(),
      'https://github.com/owner/repo/releases/download/1.0.0+58/LeinaRadio-1.0.0+58.apk',
    );
    expect(found.notes, '- Nowość\n- Poprawka');
    expect(updates.shouldOffer, isTrue);

    await updates.dismiss();
    expect(updates.shouldOffer, isFalse);
    expect(updates.available, isNotNull);

    // Remembered across restarts, also without asking GitHub again.
    final again = newUpdates();
    await again.load();
    expect(again.available?.buildNumber, 58);
    expect(again.shouldOffer, isFalse);

    // A still newer release is offered again.
    latest = release('1.0.1+60');
    await again.check();
    expect(again.shouldOffer, isTrue);
  });

  test('nothing is offered for the installed build or an older one', () async {
    installed = 58;
    final updates = newUpdates();
    await updates.load();
    await updates.check();
    expect(updates.available, isNull);
    expect(updates.problem, isNull);
    expect(updates.lastCheck, now);

    installed = 60;
    await updates.check();
    expect(updates.available, isNull);
  });

  test('a release without a build number or an APK is ignored', () async {
    final updates = newUpdates();
    await updates.load();
    for (final bad in [
      release('1.0.0'),
      release('nightly'),
      release('1.0.0+58', assets: ['notes.txt']),
    ]) {
      latest = bad;
      await updates.check();
      expect(updates.available, isNull, reason: '${bad['tag_name']}');
    }

    latest = release('v1.0.0+58', assets: ['notes.txt', 'Leina.APK']);
    await updates.check();
    expect(updates.available?.apkUrl.pathSegments.last, 'Leina.APK');
  });

  test('a repository with no release yet is no problem', () async {
    status = HttpStatus.notFound;
    final updates = newUpdates();
    await updates.load();
    await updates.check();
    expect(updates.available, isNull);
    expect(updates.problem, isNull);
  });

  test('GitHub refusing is reported, not taken for no connection', () async {
    status = HttpStatus.forbidden;
    final updates = newUpdates();
    await updates.load();
    await updates.check();
    expect(updates.problem, contains('HTTP 403'));
    expect(updates.lastCheck, isNull);
  });

  test('checked once a day, unless switched off', () async {
    final updates = newUpdates();
    await updates.load();
    await updates.checkIfDue();
    await updates.checkIfDue();
    expect(requests, hasLength(1));

    now = DateTime(2026, 10, 22, 8);
    await updates.checkIfDue();
    expect(requests, hasLength(2));

    await updates.setAutoCheck(false);
    now = DateTime(2026, 10, 23, 8);
    await updates.checkIfDue();
    expect(requests, hasLength(2));

    // "Sprawdź teraz" still works.
    await updates.check();
    expect(requests, hasLength(3));

    final restarted = newUpdates();
    await restarted.load();
    expect(restarted.autoCheck, isFalse);
  });

  test('a build without a repository never asks', () async {
    final updates = newUpdates(repo: '');
    await updates.load();
    expect(updates.configured, isFalse);
    await updates.checkIfDue();
    await updates.check();
    expect(requests, isEmpty);
  });
}
