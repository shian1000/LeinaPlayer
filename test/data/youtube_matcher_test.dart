import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/combined_search.dart';
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

  test('"đ" written "dj" or "d" is the same', () {
    for (final title in ['Djurdjevdan', 'Durdevdan', 'Đurđevdan']) {
      expect(
        pickYouTubeVideo(_song('Goran Bregović', 'Đurđevdan'), [
          _v('ok', 'Goran Bregovic - $title', 'Bijelo Dugme'),
        ])?.id,
        'ok',
        reason: title,
      );
    }
  });

  test('a duet with someone the song does not name is another performance', () {
    // Reviewed on 2026-11-27: a TV duet was picked over the song's own upload.
    expect(
      pickYouTubeVideo(_song('Goran Bregović', 'Đurđevdan'), [
        _v(
          'duet',
          'Ceca & Goran Bregović - Đurđevdan / Novogodišnji program RTS 2022',
          'RTS Najlepše narodne pesme',
          views: 3741756,
        ),
        _v('own', 'Goran Bregović - Đurđevdan', 'Some Channel', views: 20000),
      ])?.id,
      'own',
    );
    // "feat." of the song's own guest, or title first: no other performer.
    final withGuest = MatchTarget(
      title: 'Nadprzestrzenie',
      mainArtists: [MatchArtist('Dawid Podsiadło')],
      featArtists: [MatchArtist('Kaśka')],
    );
    final scores = [
      for (final s in scoreYouTubeVideos(withGuest, [
        _v('a', 'Dawid Podsiadło feat. Kaśka - Nadprzestrzenie', 'X'),
        _v('b', 'Dawid Podsiadło - Nadprzestrzenie', 'X'),
        _v('c', 'Nadprzestrzenie - Dawid Podsiadło', 'X'),
      ]))
        s.score,
    ];
    expect(scores[0], greaterThanOrEqualTo(scores[1]));
    expect(scores[2], scores[1]);
  });

  test('an alias of the artist: the channel of the video music.db links', () {
    final target = _song(
      'Goran Bregović',
      'Đurđevdan',
    ).withArtistAlias('Bijelo Dugme');
    expect(target.query, 'Goran Bregović Đurđevdan');
    expect(
      pickYouTubeVideo(target, [
        _v(
          'audio',
          'Bijelo Dugme - Đurđevdan - (Audio 1994) HD',
          'PGP RTS',
          views: 5428300,
        ),
        _v(
          'tv',
          'Ceca & Goran Bregović - Đurđevdan / Novogodišnji program RTS 2022',
          'RTS Najlepše narodne pesme',
          views: 3741756,
        ),
      ])?.id,
      'audio',
    );
  });

  test('a Latin name finds its Cyrillic upload, and the other way round', () {
    // Spotify's names for the GTA: Criminal Russia playlist (2026-11-28).
    expect(
      pickYouTubeVideo(_song('Garyk Krichevsky', 'Мой номер 245'), [
        _v('v', 'Гарик Кричевский - Мой номер 245', 'Studio Bob'),
      ])?.id,
      'v',
    );
    expect(
      pickYouTubeVideo(_song('Mikhail Boyarskiy', 'Зеленоглазое такси'), [
        _v('v', 'Зеленоглазое такси', 'Михаил Боярский - Topic'),
      ])?.id,
      'v',
    );
    expect(
      pickYouTubeVideo(_song('Sergey Nagovitsyn', 'Разбитая судьба'), [
        _v('v', 'Сергей Наговицын - Разбитая судьба', 'Шансон'),
      ])?.id,
      'v',
    );
    // A Latin title with the original in brackets.
    expect(
      pickYouTubeVideo(_song('Mikhail Shufutinsky', 'Obozhayu (Обожаю)'), [
        _v('v', 'Обожаю', 'Михаил Шуфутинский'),
      ])?.id,
      'v',
    );
    expect(
      pickYouTubeVideo(_song('Кино', 'Gruppa krovi'), [
        _v('v', 'Kino - Gruppa Krovi', 'Omnistar East'),
      ])?.id,
      'v',
    );
  });

  test('live and other versions named in Russian count like English ones', () {
    // What the phone picked for the GTA: Criminal Russia playlist before (2026-11-28).
    expect(
      pickYouTubeVideo(_song('Mikhail Krug', 'Водочку пьём'), [
        _v('version', 'Водочку пьем (Версия)', 'Михаил Круг', views: 90000),
        _v('song', 'Михаил Круг - Водочку пьём', 'Золото Шансона'),
      ])?.id,
      'song',
    );
    expect(
      pickYouTubeVideo(_song('Vyacheslav Dobrynin', 'Синий туман'), [
        _v(
          'concert',
          'Вячеслав Добрынин - Синий туман (Юбилейный концерт)',
          'Vyacheslav Dobrynin',
          views: 900000,
        ),
        _v('song', 'Синий туман', 'Вячеслав Добрынин - Topic', views: 50000),
      ])?.id,
      'song',
    );
    expect(
      pickYouTubeVideo(_song('Комбинация', 'American Boy'), [
        _v('karaoke', 'Комбинация - American Boy (караоке)', 'Karaoke'),
      ]),
      isNull,
    );
  });

  test('loose Latin letters still need the right song and artist', () {
    expect(
      pickYouTubeVideo(_song('Mikhail Krug', 'Кольщик'), [
        _v('other', 'Михаил Круг - Владимирский централ', 'Золото Шансона'),
        _v('someone', 'Сергей Трофимов - Кольщик', 'Сергей Трофимов'),
      ]),
      isNull,
    );
    // Latin against Latin is compared as it was: "y" and "i" stay apart.
    expect(
      pickYouTubeVideo(_song('Sergey Trofimov', 'Aleshka'), [
        _v('v', 'Sergei Trofimov - Aleshka', 'Channel'),
      ]),
      isNull,
    );
  });

  test('any one of a Spotify track\'s joined artists will do', () {
    final target = SearchHit.youTubeOnly(
      title: 'Surrender - Eelke Kleijn Remix',
      artistLabel: 'Way Out West, Eelke Kleijn',
      videoId: null,
    ).youTubeTarget;
    expect(
      target.query,
      'Way Out West, Eelke Kleijn Surrender - Eelke Kleijn Remix',
    );
    expect(
      pickYouTubeVideo(target, [
        _v(
          'v',
          'Way Out West - Surrender (Eelke Kleijn Remix)',
          'Hope Recordings',
        ),
      ])?.id,
      'v',
    );
  });
}
