import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/listening_highlights.dart';
import 'package:music_database_app/src/data/listening_log.dart';

var _uid = 0;
final _now = DateTime(2026, 10, 16, 20);

Listen _play(
  String title,
  DateTime at, {
  String artist = 'Kino',
  int seconds = 200,
}) => Listen(
  uid: '${_uid++}',
  startedAt: at,
  title: title,
  artist: artist,
  source: ListenSource.phone,
  listened: Duration(seconds: seconds),
);

DateTime _daysAgo(num days) =>
    _now.subtract(Duration(minutes: (days * 24 * 60).round()));

List<(HighlightKind, int)> _kinds(List<Highlight> highlights) => [
  for (final h in highlights) (h.kind, h.count),
];

void main() {
  test('milestones reached this week, not before; 30 s makes a play', () {
    final highlights = ListeningHighlights.of([
      // Nine plays a month ago, the tenth this week.
      for (var i = 0; i < 9; i++) _play('Kukushka', _daysAgo(30 + i / 10)),
      _play('Kukushka', _daysAgo(2), seconds: 29),
      _play('Kukushka', _daysAgo(1)),
      // Ten plays, all a month ago.
      for (var i = 0; i < 10; i++) _play('Gruppa krovi', _daysAgo(40 + i / 10)),
    ], now: _now);
    expect(
      [
        for (final h in highlights)
          if (h.kind == HighlightKind.songMilestone) (h.song!.title, h.count),
      ],
      [('Kukushka', 10)],
    );
  });

  test('hours of all time and an artist\'s plays', () {
    final highlights = ListeningHighlights.of([
      for (var i = 0; i < 24; i++)
        _play('Song $i', _daysAgo(20 - i / 100), seconds: 140),
      _play('Last', _daysAgo(0.5), seconds: 300),
    ], now: _now);
    // 24 × 140 s + 300 s = 1 h 1 min, the hour passed with the last play.
    expect(_kinds(highlights), [
      (HighlightKind.hours, 1),
      (HighlightKind.artistMilestone, 25),
    ]);
    expect(highlights.last.artist, 'Kino');
  });

  test('a new artist is a discovery only after two weeks of stats', () {
    List<Highlight> withHistory(int days) => ListeningHighlights.of([
      _play('Old', _daysAgo(days)),
      for (var i = 0; i < 3; i++)
        _play(
          'New $i',
          _daysAgo(1 + i / 10),
          artist: 'Mata feat. Young Leosia',
        ),
    ], now: _now);
    expect(
      [
        for (final h in withHistory(30))
          if (h.kind == HighlightKind.discovery) (h.artist, h.count),
      ],
      [('Mata', 3), ('Young Leosia', 3)],
    );
    expect(
      withHistory(10).where((h) => h.kind == HighlightKind.discovery),
      isEmpty,
    );
  });

  test('a comeback after three months; song of the week; on repeat', () {
    final highlights = ListeningHighlights.of([
      _play('Kukushka', _daysAgo(200)),
      _play('Kukushka', _daysAgo(3)),
      for (var i = 0; i < 6; i++) _play('Big Talk', _daysAgo(2 + i / 100)),
      for (var i = 0; i < 5; i++) _play('Loop', _daysAgo(1 + i / 100)),
    ], now: _now);
    final comeback = highlights.firstWhere(
      (h) => h.kind == HighlightKind.comeback,
    );
    expect(comeback.song!.title, 'Kukushka');
    expect(comeback.gap!.inDays, 197);
    final week = highlights.firstWhere(
      (h) => h.kind == HighlightKind.songOfWeek,
    );
    expect((week.song!.title, week.count), ('Big Talk', 6));
    // Big Talk is the song of the week, so only Loop is "on repeat".
    expect(
      [
        for (final h in highlights)
          if (h.kind == HighlightKind.onRepeat) (h.song!.title, h.count),
      ],
      [('Loop', 5)],
    );
  });
}
