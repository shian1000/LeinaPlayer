import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
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

  test('a version: its marker searched, its recording preferred', () {
    final target = MatchTarget(
      title: 'Boję się',
      mainArtists: [MatchArtist('Artur Rojek')],
      version: 'Live',
    );
    expect(target.query, 'Artur Rojek Boję się Live');
    expect(
      pickYouTubeVideo(target, [
        _v('studio', 'Artur Rojek - Boję się', 'Artur Rojek', views: 9000),
        _v('live', 'Artur Rojek - Boję się (Live)', 'Artur Rojek'),
      ])?.id,
      'live',
    );
  });

  test('a full album: "full album" searched, only a long video accepted', () {
    final target = MatchTarget(
      title: 'Grochów',
      mainArtists: [MatchArtist('Kult')],
      fullAlbum: true,
    );
    expect(target.query, 'Kult Grochów full album');
    expect(
      pickYouTubeVideo(target, [
        _v('song', 'Kult - Grochów', 'Kult', views: 900000),
        _v('noduratio', 'Kult - Grochów (full album)', 'Kult'),
        _v('album', 'Kult - Grochów [FULL ALBUM]', 'Kult', seconds: 2700),
      ])?.id,
      'album',
    );
    expect(
      pickYouTubeVideo(_song('Kult', 'Grochów'), [
        _v('album', 'Kult - Grochów [FULL ALBUM]', 'Kult', seconds: 2700),
      ]),
      isNull,
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

  group('another version the song title does not name', () {
    // MusicDatabase song #5965, reviewed on 2026-11-25: the phone reported the Topic remix.
    final remix = _v(
      'szXthhpfkzw',
      'Nemreš Bolivit (Space Cat Remix)',
      'Renman - Topic',
      seconds: 289,
      views: 40000,
    );
    final original = _v(
      '-XS-1zFEytA',
      'Renman - Nemreš Bolivit',
      'BalkanHop',
      seconds: 302,
      views: 30000,
    );

    test('a remix in a bracket is rejected, even from a Topic channel', () {
      final target = _song('Renman', 'Nemreš Bolivit');
      expect(pickYouTubeVideo(target, [remix, original])?.id, '-XS-1zFEytA');
      expect(scoreYouTubeVideos(target, [remix]).single.accepted, isFalse);
      expect(pickYouTubeVideo(target, [remix]), isNull);
    });

    test('the album "Space Cat, The Remixes" does not make it the song', () {
      final song = CatalogSong(
        id: 5965,
        title: 'Nemreš Bolivit',
        artistLabel: 'Renman',
        album: 'Space Cat, The Remixes',
      );
      expect(
        pickYouTubeVideo(song.youTubeTarget, [remix, original])?.id,
        '-XS-1zFEytA',
      );
    });

    test('the remix itself is still found for its version row', () {
      final target = MatchTarget(
        title: 'Nemreš Bolivit',
        mainArtists: [MatchArtist('Renman')],
        version: 'Space Cat Remix',
      );
      expect(pickYouTubeVideo(target, [remix, original])?.id, 'szXthhpfkzw');
    });

    test('a run-on marker outweighs the Topic bonus', () {
      expect(
        pickYouTubeVideo(_song('Renman', 'Nemreš Bolivit'), [
          _v('topic', 'Nemreš Bolivit Space Cat Remix', 'Renman - Topic'),
          _v('plain', 'Renman - Nemreš Bolivit', 'Fan uploads', views: 100),
        ])?.id,
        'plain',
      );
    });

    test('a release marker and an artist name are not another version', () {
      expect(
        scoreYouTubeVideos(_song('Kult', 'Arahja'), [
          _v('radio', 'Arahja (Radio Edit)', 'Kult - Topic'),
          _v('album', 'Kult - Arahja - Album Version', 'Kult'),
        ]).map((s) => s.accepted),
        [true, true],
      );
      expect(
        pickYouTubeVideo(_song('Dub FX', 'Love Someone'), [
          _v('topic', 'Love Someone', 'Dub FX - Topic'),
          _v('fan', 'Dub FX - Love Someone', 'Fan uploads', views: 100000),
        ])?.id,
        'topic',
      );
    });

    test("a cover's own credit is its version", () {
      final target = MatchTarget(
        title: 'Creep',
        mainArtists: [MatchArtist('Postmodern Jukebox')],
        coverOf: 'Radiohead',
      );
      expect(
        pickYouTubeVideo(target, [
          _v('c', 'Creep (Acoustic Radiohead Cover)', 'Postmodern Jukebox'),
        ])?.id,
        'c',
      );
      expect(
        pickYouTubeVideo(_song('Radiohead', 'Creep'), [
          _v('c', 'Radiohead - Creep (Acoustic Cover)', 'Fan'),
        ]),
        isNull,
      );
    });
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

  test('a soundtrack credit in brackets is not a version', () {
    expect(
      pickYouTubeVideo(
        _song(
          'Rico Nasty',
          "You Can't Run From Me (from Cyberpunk: Edgerunners Season 2)",
        ),
        [
          _v(
            'game',
            "DEAD AS DISCO Rico Nasty - You Can't Run From Me "
                '(from Cyberpunk: Edgerunners Season 2)',
            'Cross-Ribbons',
            views: 500000,
          ),
          _v(
            'ost',
            "Rico Nasty - You Can't Run From Me | Cyberpunk: Edgerunners 2 "
                '(Original Series Soundtrack)',
            'SonySoundtracksVEVO',
            views: 200000,
          ),
        ],
      )?.id,
      'ost',
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
