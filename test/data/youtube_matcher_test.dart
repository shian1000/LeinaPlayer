import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/youtube_matcher.dart';
import 'package:music_database_app/src/data/youtube_video.dart';

YouTubeVideo _v(
  String id,
  String title,
  String channel, {
  int seconds = 200,
  int views = 1000,
}) => YouTubeVideo(
  id: id,
  title: title,
  channel: channel,
  duration: Duration(seconds: seconds),
  viewCount: views,
);

MatchTarget _song(String artist, String title, {String? synonyms}) =>
    MatchTarget(title: title, mainArtists: [MatchArtist(artist, synonyms)]);

void main() {
  test('query is the main artists and the title', () {
    expect(
      MatchTarget(
        title: 'Nadprzestrzenie',
        mainArtists: [MatchArtist('Dawid Podsiadło'), MatchArtist('Kaśka')],
        featArtists: [MatchArtist('Gość')],
      ).query,
      'Dawid Podsiadło Kaśka Nadprzestrzenie',
    );
  });

  test('prefers the Topic upload over a more popular live recording', () {
    final pick = pickYouTubeVideo(
      _song('Dawid Podsiadło', 'Małomiasteczkowy'),
      [
        _v(
          'live',
          'Dawid Podsiadło - Małomiasteczkowy (na żywo)',
          'Dawid Podsiadło',
          views: 9000000,
        ),
        _v(
          'topic',
          'Małomiasteczkowy',
          'Dawid Podsiadło - Topic',
          views: 50000,
        ),
      ],
    );
    expect(pick?.id, 'topic');
  });

  test('rejects karaoke, reactions, wrong songs and wrong artists', () {
    final scored = scoreYouTubeVideos(_song('Afina', 'Pay Your Respect'), [
      _v('k', 'Afina - Pay Your Respect (Karaoke)', 'Karaoke Po Polsku'),
      _v('r', 'REAKCJA na Afina - Pay Your Respect', 'Ktoś'),
      _v('o', 'Afina - Inny utwór', 'Afina'),
      _v('a', 'Pay Your Respect', 'Zupełnie ktoś inny'),
      _v('short', 'Afina - Pay Your Respect', 'Afina', seconds: 30),
    ]);
    expect(scored.where((s) => s.accepted), isEmpty);
    expect(
      pickYouTubeVideo(_song('Afina', 'Pay Your Respect'), [
        for (final s in scored) s.video,
      ]),
      isNull,
    );
  });

  test('a version named in the song title wins instead of losing', () {
    final target = _song('Daft Punk', 'One More Time (Remix)');
    expect(
      pickYouTubeVideo(target, [
        _v('orig', 'Daft Punk - One More Time (Official Audio)', 'Daft Punk'),
        _v('remix', 'Daft Punk - One More Time (Remix)', 'Daft Punk'),
      ])?.id,
      'remix',
    );
    expect(
      pickYouTubeVideo(_song('Daft Punk', 'One More Time'), [
        _v('orig', 'Daft Punk - One More Time (Official Audio)', 'Daft Punk'),
        _v('remix', 'Daft Punk - One More Time (Remix)', 'Daft Punk'),
      ])?.id,
      'orig',
    );
  });

  test('finds the artist through a synonym (channel name)', () {
    final pick = pickYouTubeVideo(
      _song('Бумбокс', 'Вахтерам', synonyms: 'familyboombox, Boombox'),
      [_v('ok', 'Вахтерам', 'familyboombox')],
    );
    expect(pick?.id, 'ok');
  });

  test('a keyword that is part of the song title is not held against it', () {
    final pick = pickYouTubeVideo(_song('Oasis', 'Live Forever'), [
      _v('ok', 'Oasis - Live Forever (Official HD Remastered Video)', 'Oasis'),
    ]);
    expect(pick?.id, 'ok');
  });

  test('behind-the-scenes and club recordings are not the song', () {
    final target = MatchTarget(
      title: "Baby Don't Hurt Me",
      mainArtists: [MatchArtist('David Guetta')],
    );
    expect(
      pickYouTubeVideo(target, [
        _v(
          'bts',
          "David Guetta - Baby Don't Hurt Me [Behind The Scenes]",
          'David Guetta',
          views: 900000,
        ),
        _v(
          'ok',
          "David Guetta - Baby Don't Hurt Me (Official Video)",
          'David Guetta',
          views: 100000,
        ),
      ])?.id,
      'ok',
    );
  });

  test('the bracketed part of the song title picks the version', () {
    expect(
      pickYouTubeVideo(_song('seven oops', 'Lovers (Instrumental)'), [
        _v('vocal', 'seven oops - Lovers', 'SevenOopsVEVO', views: 900000),
        _v(
          'inst',
          'Lovers (Instrumental)',
          'seven oops Official YouTube Channel',
        ),
      ])?.id,
      'inst',
    );
  });

  test('"&" and "and" are the same', () {
    expect(
      pickYouTubeVideo(_song('Fandango', 'Autos, Moda Y Rock & Roll'), [
        _v('ok', 'Fandango - Autos, Moda Y Rock and Roll', 'Fandango'),
      ])?.id,
      'ok',
    );
  });
}
