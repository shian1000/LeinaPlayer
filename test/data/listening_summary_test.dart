import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/listening_log.dart';
import 'package:music_database_app/src/data/listening_summary.dart';

var _uid = 0;

Listen _play(String title, DateTime at, {String artist = 'Kino'}) => Listen(
  uid: '${_uid++}',
  startedAt: at,
  title: title,
  artist: artist,
  source: ListenSource.phone,
  listened: const Duration(minutes: 3),
);

void main() {
  test('seasons are whole months; winter runs into the next year', () {
    final winter = SummaryPeriod.seasonOf(DateTime(2026, 1, 20));
    expect((winter.from, winter.to), (DateTime(2025, 12), DateTime(2026, 3)));
    expect(winter.title, 'Zima 2025/26');
    expect(winter.yourTitle, 'Twoja zima 2025/26');
    expect(SummaryPeriod.seasonOf(DateTime(2026, 12, 3)).title, 'Zima 2026/27');
    final summer = SummaryPeriod.seasonOf(DateTime(2026, 8, 31, 23));
    expect((summer.from, summer.to), (DateTime(2026, 6), DateTime(2026, 9)));
    expect(summer.yourTitle, 'Twoje lato 2026');
    expect(SummaryPeriod.year(2026).yourTitle, 'Twój rok 2026');
    expect(summer.inProgress(DateTime(2026, 8, 31)), isTrue);
    expect(summer.inProgress(DateTime(2026, 9)), isFalse);
  });

  test('the periods with plays, newest first, a year before its seasons', () {
    final periods = SummaryPeriod.available([
      _play('a', DateTime(2025, 12, 24)),
      _play('b', DateTime(2026, 7, 1)),
      _play('c', DateTime(2026, 7, 2)),
    ]);
    expect(
      [for (final p in periods) p.title],
      ['Rok 2026', 'Lato 2026', 'Zima 2025/26', 'Rok 2025'],
    );
  });

  test('months of the period and the artists new in it', () {
    final listens = [
      _play('Old', DateTime(2026, 5, 1)),
      _play('Kukushka', DateTime(2026, 6, 2)),
      _play('Kukushka', DateTime(2026, 8, 30)),
      _play('Big Talk', DateTime(2026, 8, 30), artist: 'SOFY'),
      _play('Later', DateTime(2026, 9, 2), artist: 'Mata'),
    ];
    final summer = ListeningSummary.of(
      listens,
      SummaryPeriod.seasonOf(DateTime(2026, 7)),
    );
    expect(summer.stats.plays, 3);
    expect([for (final m in summer.months) m.listened.inMinutes], [3, 0, 6]);
    expect([for (final a in summer.newArtists!) a.name], ['SOFY']);

    // Nothing before spring: no way to tell what's new.
    final spring = ListeningSummary.of(
      listens,
      SummaryPeriod.seasonOf(DateTime(2026, 4)),
    );
    expect(spring.newArtists, isNull);
  });
}
