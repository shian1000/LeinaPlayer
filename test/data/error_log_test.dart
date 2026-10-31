import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/error_log.dart';
import 'package:music_database_app/src/data/problem_report.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  late Directory dir;
  late DateTime now;

  ErrorLog newLog() => ErrorLog(directory: () async => dir, now: () => now);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('error_log_test');
    now = DateTime(2026, 10, 21, 20, 15, 30);
  });

  tearDown(() async => dir.delete(recursive: true));

  test('kept in a file across restarts, multi-line messages too', () async {
    final log = newLog();
    log.record('Loading playlists failed: SocketException');
    now = now.add(const Duration(minutes: 1));
    log.record('Błąd ekranu: boom\n#0 something\n#1 else');
    await log.flush();

    final again = newLog();
    await again.load();
    expect(again.entries.map((e) => e.message), [
      'Loading playlists failed: SocketException',
      'Błąd ekranu: boom\n#0 something\n#1 else',
    ]);
    expect(again.entries.first.at, DateTime(2026, 10, 21, 20, 15, 30));
    expect(again.text, contains('2026-10-21 20:16:30 Błąd ekranu: boom'));
  });

  test('what was recorded before the file was read stays', () async {
    final first = newLog()..record('old');
    await first.flush();
    final log = newLog()..record('early in start-up');
    await log.load();
    expect(log.entries.map((e) => e.message), ['old', 'early in start-up']);
  });

  test(
    'entries older than two weeks and past the size limit are dropped',
    () async {
      final log = newLog()..record('old one');
      now = now.add(ErrorLog.keepFor + const Duration(minutes: 1));
      log.record('new one');
      expect(log.entries.map((e) => e.message), ['new one']);

      final big = 'x' * 1000;
      for (var i = 0; i < 600; i++) {
        log.record('$i $big');
      }
      expect(log.text.length, lessThanOrEqualTo(ErrorLog.maxBytes));
      expect(log.entries.last.message, startsWith('599 '));
    },
  );

  test('tokens, passwords and keys are cut out', () {
    expect(
      ErrorLog.scrub('PUT /inbox?token=abc123def failed'),
      'PUT /inbox?token=… failed',
    );
    expect(
      ErrorLog.scrub('{"username":"x","password":"tajne"}'),
      '{"username":"x","password":"…"}',
    );
    expect(
      ErrorLog.scrub('Authorization: Bearer eyJhbGciOi.x.y'),
      'Authorization: …',
    );
    expect(ErrorLog.scrub('header Bearer abc.def'), 'header Bearer …');
    expect(
      ErrorLog.scrub('search?key=AIzaSyXYZ&q=kino'),
      'search?key=…&q=kino',
    );
    expect(ErrorLog.scrub('Nothing secret here'), 'Nothing secret here');
  });

  test('server addresses become the kind of network', () {
    expect(
      ErrorLog.scrub(
        'Playlist sync on http://100.101.102.103:8002/ failed: SocketException: '
        'Connection refused, address = 100.101.102.103, port = 49530',
      ),
      'Playlist sync on http://<Tailscale>:8002/ failed: SocketException: '
      'Connection refused, address = <Tailscale>, port = 49530',
    );
    expect(
      ErrorLog.scrub('http://192.168.1.20:8002/ and 10.0.0.5 and 172.20.1.1'),
      'http://<sieć domowa>:8002/ and <sieć domowa> and <sieć domowa>',
    );
    expect(ErrorLog.scrub('address = 8.8.8.8'), 'address = <IP>');
    expect(
      ErrorLog.scrub('http://serwer.tail1234.ts.net:8002/ [fd7a:115c:a1e0::1]'),
      'http://<Tailscale>:8002/ <Tailscale>',
    );
    expect(
      ErrorLog.scrub('http://jethro.local:8002/ fe80::1%wlan0'),
      'http://<sieć domowa>:8002/ <sieć domowa>',
    );
    expect(
      ErrorLog.scrub(
        'Syncing later-links on http://<Tailscale>:8002/users/jan.kowalski/later-links?since=18 '
        'and /users/jan/folders',
      ),
      'Syncing later-links on http://<Tailscale>:8002/users/<konto>/later-links?since=18 '
      'and /users/<konto>/folders',
    );
    expect(
      ErrorLog.scrub(
        'Playing https://rr4---sn-abc.googlevideo.com/videoplayback?expire=1&ip=83.1.2.3'
        '&cpn=xyz failed: Connection aborted',
      ),
      'Playing https://<googlevideo> failed: Connection aborted',
    );
    const kept =
        'Asking itunes for a cover failed: Failed host lookup: \'itunes.apple.com\' '
        'TimeoutException after 0:00:08.000000 (app.dart:1590) wersja 1.0.0';
    expect(ErrorLog.scrub(kept), kept);
  });

  test(
    'addresses in a file written before scrubbing are cut on reading',
    () async {
      final dir = await Directory.systemTemp.createTemp('error_log_ip');
      addTearDown(() => dir.delete(recursive: true));
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      await File('${dir.path}/error_log.txt').writeAsString(
        '${now.year}-${two(now.month)}-${two(now.day)} 10:00:00 '
        'Sync on http://100.101.102.103:8002/ failed\n',
      );
      final log = ErrorLog(directory: () async => dir, now: () => now);
      await log.load();
      expect(
        log.entries.single.message,
        'Sync on http://<Tailscale>:8002/ failed',
      );
    },
  );

  test('clear empties memory and the file', () async {
    final log = newLog()..record('something');
    await log.flush();
    await log.clear();
    expect(log.entries, isEmpty);
    final again = newLog();
    await again.load();
    expect(again.entries, isEmpty);
  });

  test('the report: version, phone, description, log', () {
    final report = problemReport(
      package: PackageInfo(
        appName: 'Leina Radio',
        packageName: 'x',
        version: '1.0.0',
        buildNumber: '72',
      ),
      device: (
        manufacturer: 'HUAWEI',
        model: 'SNE-LX1',
        android: '10 (API 29)',
      ),
      description: '  Nie gra utwór z YouTube  ',
      log: '2026-10-21 20:15:30 Playing failed',
      at: now,
      commit: '86f9fa9',
    );
    expect(report, contains('Wersja: 1.0.0, kompilacja 72, 86f9fa9'));
    expect(report, contains('Telefon: HUAWEI SNE-LX1'));
    expect(report, contains('Android: 10 (API 29)'));
    expect(report, contains('Co się stało:\nNie gra utwór z YouTube\n'));
    expect(report, contains('2026-10-21 20:15:30 Playing failed'));

    final empty = problemReport(
      package: PackageInfo(
        appName: 'Leina Radio',
        packageName: 'x',
        version: '1.0.0',
        buildNumber: '72',
      ),
      device: (manufacturer: null, model: null, android: null),
      description: '',
      log: '',
      at: now,
      commit: '',
    );
    expect(empty, contains('Telefon: nieznany'));
    expect(empty, contains('(nie opisano)'));
    expect(empty, contains('(pusty)'));
  });
}
