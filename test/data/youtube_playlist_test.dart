import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/text_normalizer.dart';
import 'package:music_database_app/src/data/youtube_playlist.dart';

void main() {
  test('playlist id from links and bare ids', () {
    expect(
      extractPlaylistId('https://www.youtube.com/playlist?list=PLabc_123-x'),
      'PLabc_123-x',
    );
    expect(
      extractPlaylistId(
        'https://youtube.com/watch?v=dQw4w9WgXcQ&list=PLq&index=2',
      ),
      'PLq',
    );
    expect(extractPlaylistId('  PLbare  '), 'PLbare');
    expect(extractPlaylistId('https://example.com/nothing'), isNull);
    expect(extractPlaylistId(''), isNull);
  });

  test('trailing junk phrases are cut, a title of nothing else stays', () {
    // MusicDatabase's test_an_anime_theme_named_by_its_place_in_the_show_is_junk.
    expect(
      stripTrailingJunkSuffix('The Real Folk Blues ending theme'),
      'The Real Folk Blues',
    );
    expect(stripTrailingJunkSuffix('Tank! - Opening Theme'), 'Tank!');
    expect(stripTrailingJunkSuffix('Song Music Video Official Audio'), 'Song');
    expect(stripTrailingJunkSuffix('Lonely full song'), 'Lonely');
    expect(stripTrailingJunkSuffix('Ending Theme'), 'Ending Theme');
    expect(stripTrailingJunkSuffix('HD'), 'HD');
    expect(stripTrailingJunkSuffix('Opening Night'), 'Opening Night');
  });

  group('parseYouTubeTrack', () {
    test('an anime theme named by its place in the show loses it', () {
      expect(
        parseYouTubeTrack(
          'Cowboy Bebop - The Real Folk Blues ending theme',
          'anime fan',
        ),
        (artist: 'Cowboy Bebop', title: 'The Real Folk Blues'),
      );
      expect(parseYouTubeTrack('SEATBELTS - Tank! (Opening Theme)', 'x'), (
        artist: 'SEATBELTS',
        title: 'Tank!',
      ));
    });

    ({String artist, String title}) p(String title, String channel) =>
        parseYouTubeTrack(title, channel);

    test('an event\'s "<event year> | <artist> | <song> | <channel>"', () {
      expect(
        p(
          'FRYDERYKI 2018 | Daria Zawiałow & Krzysztof Zalewski | '
              'Malinowy chruśniak + Polsko | Gala Fryderyk',
          'Gala Fryderyk',
        ),
        (
          artist: 'Daria Zawiałow & Krzysztof Zalewski',
          title: 'Malinowy chruśniak + Polsko',
        ),
      );
      expect(p('Opole 2017 | Kayah | Testosteron', 'TVP'), (
        artist: 'Kayah',
        title: 'Testosteron',
      ));
      // No year in the first part, or not three parts: still a "| suffix".
      expect(p('Testosteron | Kayah | TVP Rozrywka', 'x'), (
        artist: 'x',
        title: 'Testosteron',
      ));
      expect(p('Live 2018 | Kayah | Testosteron | Opole', 'TVP'), (
        artist: 'TVP',
        title: 'Live 2018',
      ));
    });

    test('"Artist - Title" with junk brackets, hashtags and a pipe suffix', () {
      expect(
        p(
          'Dawid Podsiadło - Małomiasteczkowy (Official Video)',
          'Dawid Podsiadło',
        ),
        (artist: 'Dawid Podsiadło', title: 'Małomiasteczkowy'),
      );
      expect(
        p('OMNIMAR - The Matrix (Official Video) | darkTunes Music Group', 'x'),
        (artist: 'OMNIMAR', title: 'The Matrix'),
      );
      expect(p('Voo Voo - Nocą (Official Audio) #Zostańwdomu', 'Voo Voo'), (
        artist: 'Voo Voo',
        title: 'Nocą',
      ));
      expect(p('Kult - Arahja (2019) [HD]', 'Kult'), (
        artist: 'Kult',
        title: 'Arahja',
      ));
    });

    test('Topic channels: the channel is the artist', () {
      expect(p('Małomiasteczkowy', 'Dawid Podsiadło - Topic'), (
        artist: 'Dawid Podsiadło',
        title: 'Małomiasteczkowy',
      ));
    });

    test('a title that is only a hashtag keeps its word', () {
      expect(p('#Życzliwość', 'Karaś/Rogucki - Topic'), (
        artist: 'Karaś/Rogucki',
        title: 'Życzliwość',
      ));
    });

    test('no separator: the channel (without VEVO) is the artist', () {
      expect(p('Mr. Vain (Original Radio Edit)', 'CultureBeatVEVO'), (
        artist: 'CultureBeat',
        title: 'Mr. Vain',
      ));
    });

    test('junk only after the separator: the left part by the channel', () {
      expect(p('Glow - Lyric Video (English / French)', 'Attic Ocean'), (
        artist: 'Attic Ocean',
        title: 'Glow',
      ));
      expect(p('Pidvalia - Official Music Video', 'DakhaBrakhaVEVO'), (
        artist: 'DakhaBrakha',
        title: 'Pidvalia',
      ));
      expect(p('Attic Ocean - Glow', 'Attic Ocean'), (
        artist: 'Attic Ocean',
        title: 'Glow',
      ));
      // The channel's own name on the left is the artist, even before a junk-looking title.
      expect(p('India.Arie - Video', 'India.Arie'), (
        artist: 'India.Arie',
        title: 'Video',
      ));
    });

    test(
      '"Artist- Title" with the dash glued to the artist; quotes dropped',
      () {
        expect(p("Renata Przemyk- ''Aniolek''", 'ilona117'), (
          artist: 'Renata Przemyk',
          title: 'Aniolek',
        ));
        expect(p('Kult - „Arahja”', 'Kult'), (artist: 'Kult', title: 'Arahja'));
        // Not a dash inside a word.
        expect(p('Jean-Michel Jarre', 'x'), (
          artist: 'x',
          title: 'Jean-Michel Jarre',
        ));
      },
    );

    test('real versions are kept', () {
      expect(
        p('Björk - Army of Me (Sucker Punch Remix) [From Sucker Punch]', 'x'),
        (artist: 'Björk', title: 'Army of Me (Sucker Punch Remix)'),
      );
      expect(p('Merk & Kremont - Sad Story (Out of Luck) (Lyric Video)', 'x'), (
        artist: 'Merk & Kremont',
        title: 'Sad Story (Out of Luck)',
      ));
      // A version's bracket stays whole, its year and "Video" too.
      expect(
        p(
          'Dawid Podsiadło i Kaśka Sochacka - samoloty (Live @ Odra, Wrocław / ZORZA 2025)',
          'Dawid Podsiadło',
        ),
        (
          artist: 'Dawid Podsiadło i Kaśka Sochacka',
          title: 'samoloty (Live @ Odra, Wrocław / ZORZA 2025)',
        ),
      );
      expect(
        p(
          'Kwiat Jabłoni - Dziś późno pójdę spać (Official Acoustic Live Video)',
          'x',
        ),
        (
          artist: 'Kwiat Jabłoni',
          title: 'Dziś późno pójdę spać (Official Acoustic Live Video)',
        ),
      );
      expect(p('Kwiat Jabłoni - Dziś późno pójdę spać (2019)', 'x'), (
        artist: 'Kwiat Jabłoni',
        title: 'Dziś późno pójdę spać',
      ));
    });
  });

  group('the playlist "Preuzeti (2018.05)"', () {
    String? artistNamed(String name) => const {
      'general woo': 'General Woo',
      'lona': 'Łona',
      'the cure': 'The Cure',
      'paramore': 'Paramore',
      'fisz': 'Fisz',
      'soulsearchanddestroy': 'SoulSearchAndDestroy',
    }[normalizeForSearch(name)];
    ({String artist, String title}) p(String title, String channel) =>
        parseYouTubeTrack(title, channel, artistNamed: artistNamed);

    test('a dash inside a bracket does not split', () {
      expect(
        p(
          'Summer Paradise (Future Funk - Vaporwave - Electronic Mix)',
          'SoulSearchAndDestroy',
        ),
        (
          artist: 'SoulSearchAndDestroy',
          title: 'Summer Paradise (Future Funk - Vaporwave - Electronic Mix)',
        ),
      );
    });

    test('" -- " splits first; a track number and the label go', () {
      expect(
        p(
          '18.White House Records & Fisz -- Na sznurowadle - KODEX',
          'White House Records',
        ),
        (artist: 'Fisz', title: 'Na sznurowadle'),
      );
      // Without the catalog too.
      expect(
        parseYouTubeTrack(
          '18.White House Records & Fisz -- Na sznurowadle - KODEX',
          'White House Records',
        ),
        (artist: 'Fisz', title: 'Na sznurowadle'),
      );
    });

    test('"Artist: Title" by the channel or a known artist', () {
      expect(p('Paramore: crushcrushcrush [OFFICIAL VIDEO]', 'Paramore'), (
        artist: 'Paramore',
        title: 'crushcrushcrush',
      ));
      expect(
        parseYouTubeTrack(
          "dylan.pl: Adam dał imiona zwierzętom (Bob Dylan's 'Man Gave Names "
              "to All the Animals')",
          'dylan.pl',
        ),
        (artist: 'dylan.pl', title: 'Adam dał imiona zwierzętom'),
      );
      // Any other colon stays in the title.
      expect(parseYouTubeTrack('Intro: The Beginning', 'Somebody'), (
        artist: 'Somebody',
        title: 'Intro: The Beginning',
      ));
    });

    test('producer and player credits go, a guest joins the artist', () {
      expect(
        p('KęKę - Nigdy ponad stan prod. Sergiusz', 'Takie Rzeczy Label'),
        (artist: 'KęKę', title: 'Nigdy ponad stan'),
      );
      expect(p('KęKę - Cesarz prod. Boryrobibity', 'Takie Rzeczy Label'), (
        artist: 'KęKę',
        title: 'Cesarz',
      ));
      expect(
        p(
          'KęKę - Brzmienie  gość Sarsa, prod. Sondr duet, gitara Paweł '
              'Smakulski',
          'Takie Rzeczy Label',
        ),
        (artist: 'KęKę feat. Sarsa', title: 'Brzmienie'),
      );
      expect(
        p(
          'Sarius - Przerywamy program - feat. O.S.T.R. & Hades - prod. DJ Eprom',
          'x',
        ),
        (artist: 'Sarius feat. O.S.T.R. & Hades', title: 'Przerywamy program'),
      );
      // "Prod" only as a whole word, and a feat. credit not set off by a dash stays.
      expect(p('The Prodigy - Firestarter', 'x'), (
        artist: 'The Prodigy',
        title: 'Firestarter',
      ));
      expect(p('Afina - Pay Your Respect ft. CJ Pitts', 'x'), (
        artist: 'Afina',
        title: 'Pay Your Respect ft. CJ Pitts',
      ));
    });

    test('a fan channel: the known artist the title starts with', () {
      expect(p('General Woo   U mom zivotu Official', 'Black Shadow'), (
        artist: 'General Woo',
        title: 'U mom zivotu',
      ));
      // Without the catalog the channel stays the artist, "Official" still goes.
      expect(
        parseYouTubeTrack(
          'General Woo   U mom zivotu Official',
          'Black Shadow',
        ),
        (artist: 'Black Shadow', title: 'General Woo U mom zivotu'),
      );
    });

    test('a title of only a known artist takes its hashtag', () {
      expect(p('Łona #hot16challenge #hot16', 'Dobrzewiesz Nagrania'), (
        artist: 'Łona',
        title: 'hot16challenge',
      ));
    });

    test(
      '"Cover by" names the performer; the original title in its alphabet goes',
      () {
        expect(
          p(
            'NARUTO SHIPPUDEN OP.16 - SILHOUETTE (シルエット)┃Cover by Raon Lee',
            'Raon',
          ),
          (artist: 'Raon', title: 'SILHOUETTE'),
        );
        expect(p('Creep | Cover by Somebody Else', 'covers channel'), (
          artist: 'Somebody Else',
          title: 'Creep',
        ));
        expect(p('The Cure - Lovesong (cover by Adele)', 'x'), (
          artist: 'Adele',
          title: 'Lovesong (The Cure cover)',
        ));
      },
    );

    test('a bracket right after the artist at the start is its logo', () {
      expect(p('alt-J (∆) Breezeblocks', 'alt-J'), (
        artist: 'alt-J',
        title: 'Breezeblocks',
      ));
    });

    test('several artists between pipes, and a cover medley as it reads', () {
      expect(
        p(
          'The Cure | Talk Talk | Foghorn - muzyka na jesień',
          'Kawa i Awangarda',
        ),
        (artist: 'The Cure, Talk Talk, Foghorn', title: 'muzyka na jesień'),
      );
      expect(
        p('a-ha - Take On Me in 20 Styles ft. Seth Everman', 'Anthony Vincent'),
        (artist: 'a-ha', title: 'Take On Me in 20 Styles ft. Seth Everman'),
      );
    });
  });

  group('the playlist "Скачать (2018.06)"', () {
    String? artistNamed(String name) => const {
      'nipplepeople': 'Nipplepeople',
      'yeye': 'YeYe',
    }[normalizeForSearch(name)];
    ({String artist, String title}) p(String title, String channel) =>
        parseYouTubeTrack(title, channel, artistNamed: artistNamed);

    test('the channel\'s name in front, credits after the junk bracket', () {
      expect(
        p(
          'nipplepeople FRKA (Official video), Kire Mitrev, Slavica Maras',
          'nipplepeople',
        ),
        (artist: 'nipplepeople', title: 'FRKA'),
      );
      expect(
        parseYouTubeTrack(
          'Nipplepeople - FRKA (Official video), Kire Mitrev, Slavica Maras',
          'x',
        ),
        (artist: 'Nipplepeople', title: 'FRKA'),
      );
      // Not after a bracket that is part of the title, nor a version's.
      expect(p('Grad (Zagreb), Split, Rijeka', 'nipplepeople'), (
        artist: 'nipplepeople',
        title: 'Grad (Zagreb), Split, Rijeka',
      ));
      expect(p('Nipplepeople - FRKA (Live), Tvornica', 'x'), (
        artist: 'Nipplepeople',
        title: 'FRKA (Live), Tvornica',
      ));
    });

    test('full-width junk brackets go, as ASCII ones do', () {
      expect(p('ゆらゆら（Official Music Video）', 'YeYe'), (
        artist: 'YeYe',
        title: 'ゆらゆら',
      ));
      expect(p('YeYe - ゆらゆら［MV］（Official Video）', 'x'), (
        artist: 'YeYe',
        title: 'ゆらゆら［MV］',
      ));
      expect(p('YeYe - ゆらゆら（Live）', 'x'), (
        artist: 'YeYe',
        title: 'ゆらゆら（Live）',
      ));
      expect(titlesToMatch('ゆらゆら（Official Music Video）').last, 'ゆらゆら');
    });
  });

  test('titlesToMatch: junk a stored title still has, cut for matching', () {
    List<String> t(String title) => titlesToMatch(title);
    expect(t('I Follow Rivers (Original)').last, 'I Follow Rivers');
    expect(t('Pokito a Poko ((Videoclip))').last, 'Pokito a Poko');
    expect(t('Bloom lyrics').last, 'Bloom');
    expect(t('Czarne lustra prod. White House').last, 'Czarne lustra');
    expect(
      t('Got My Mind Set On You (Version II)').last,
      'Got My Mind Set On You',
    );
    expect(t('Brzmienie gość Sarsa').last, 'Brzmienie feat. Sarsa');
    // The title as it is first; versions and edits stay.
    expect(t('Bloom lyrics').first, 'Bloom lyrics');
    expect(t('Boję się (Live)'), ['Boję się (Live)']);
    expect(t('Boję się (Radio Edit)'), ['Boję się (Radio Edit)']);
    expect(t('Lyrics'), ['Lyrics']);
  });

  group('emoji', () {
    // Found reviewing the phone's requests on 2026-11-25: the emoji went into the title.
    test('are dropped from the title, with their variation selectors', () {
      expect(
        parseYouTubeTrack(
          'ADHD – Dzieci Burzy z Salki ⚡🌩️ | LIVE',
          'Zespół ADHD',
        ),
        (artist: 'ADHD', title: 'Dzieci Burzy z Salki'),
      );
      expect(parseYouTubeTrack('ADHD - Apokalipsa 🔥', 'Zespół ADHD'), (
        artist: 'ADHD',
        title: 'Apokalipsa',
      ));
    });

    test('are dropped from the artist and from inside a bracket', () {
      expect(parseYouTubeTrack('🔥 Kult 🔥 - Arahja (Remix 👨‍👩‍👧)', 'Fan'), (
        artist: 'Kult',
        title: 'Arahja (Remix)',
      ));
      expect(parseYouTubeTrack('Arahja 🇵🇱 1️⃣', 'Kult - Topic'), (
        artist: 'Kult',
        title: 'Arahja',
      ));
    });

    test('letters of other scripts and ordinary punctuation stay', () {
      for (final title in [
        'Кино - Группа крови',
        '米津玄師 - ピースサイン',
        '아이유 - 밤편지',
        'Café Tacvba - Eres!',
        'Artist - Rock & Roll™ ↔ Ünïcödé, (Live)',
      ]) {
        expect(withoutEmoji(title), title);
      }
      expect(parseYouTubeTrack('Кино - Группа крови ⭐', 'Fan'), (
        artist: 'Кино',
        title: 'Группа крови',
      ));
      expect(parseYouTubeTrack('米津玄師 - ピースサイン 🎵', 'Fan'), (
        artist: '米津玄師',
        title: 'ピースサイン',
      ));
      // A joiner between letters is a script's, not an emoji's (Malayalam).
      expect(withoutEmoji('ന്\u200Dറെ 😀'), 'ന്\u200Dറെ');
    });

    test('a title of nothing but emoji stays as it was', () {
      expect(withoutEmoji('🔥🔥'), '');
      expect(parseYouTubeTrack('🔥🔥', 'Kult - Topic').title, '🔥🔥');
    });

    test('a stored track title loses them in its request', () {
      expect(
        requestTitleOfVideo('Dzieci Burzy z Salki ⚡🌩️'),
        'Dzieci Burzy z Salki',
      );
      expect(requestTitleOfVideo('Группа крови'), 'Группа крови');
    });
  });

  group('channelVideoReadings', () {
    String? artistNamed(String name) => const {
      'renata przemyk': 'Renata Przemyk',
      'smith burrows': 'Smith & Burrows',
      'renata': 'Renata',
      'lona': 'Łona',
      'webber': 'Webber',
    }[normalizeForSearch(name)];

    test('the title starting with an artist music.db knows, longest first', () {
      expect(
        channelVideoReadings(
          'renata przemyk bo jesli tak ma byc',
          'thericeburner',
          artistNamed,
        ),
        [
          (artist: 'Renata Przemyk', title: 'bo jesli tak ma byc'),
          (artist: 'Renata', title: 'przemyk bo jesli tak ma byc'),
        ],
      );
      // A whole name only, and a title left after it.
      expect(channelVideoReadings('renata przemykowa', 'x', artistNamed), [
        (artist: 'Renata', title: 'przemykowa'),
      ]);
      expect(channelVideoReadings('Renata Przemyk', 'x', artistNamed), [
        (artist: 'Renata', title: 'Przemyk'),
      ]);
    });

    test('past a second artist joined to the first', () {
      expect(
        channelVideoReadings(
          'Łona i Webber Wyślij sobie pocztówkę',
          'Dobrzewiesz Nagrania',
          artistNamed,
        ),
        [
          (artist: 'Łona', title: 'Wyślij sobie pocztówkę'),
          (artist: 'Łona', title: 'i Webber Wyślij sobie pocztówkę'),
        ],
      );
      // A joining word only between two names music.db knows.
      expect(channelVideoReadings('Łona i ja na rowerze', 'x', artistNamed), [
        (artist: 'Łona', title: 'i ja na rowerze'),
      ]);
    });

    test('the artist in a trailing bracket', () {
      expect(
        channelVideoReadings(
          'Wonderful Life (Smith & Burrows)',
          'Peaky Blinders',
          artistNamed,
        ),
        [(artist: 'Smith & Burrows', title: 'Wonderful Life')],
      );
      expect(
        channelVideoReadings('Wonderful Life (Acoustic)', 'x', artistNamed),
        isEmpty,
      );
    });

    test('nothing when the title names its artist itself', () {
      expect(
        channelVideoReadings(
          'Renata Przemyk - Bo jeśli tak ma być',
          'thericeburner',
          artistNamed,
        ),
        isEmpty,
      );
      expect(
        channelVideoReadings(
          'Renata Przemyk bo',
          'Renata - Topic',
          artistNamed,
        ),
        isEmpty,
      );
    });
  });
  group('a channel name with an affix (bug L3)', () {
    String? artistNamed(String name) => const {
      'clutch': 'Clutch',
      'pomplamoose': 'Pomplamoose',
      'music for pleasure': 'Music For Pleasure',
      'bigmusic': 'BigMusic',
    }[normalizeForSearch(name)];
    ({String artist, String title}) p(String title, String channel) =>
        parseYouTubeTrack(title, channel, artistNamed: artistNamed);

    test(
      '"Music" goes when the title names the artist, with its ft. guest',
      () {
        const title =
            'Les Yeux Noirs (Dark Eyes) | Django Reinhardt | '
            'Pomplamoose ft. The Vignes Rooftop Revival';
        const read = (
          artist: 'Pomplamoose feat. The Vignes Rooftop Revival',
          title: 'Les Yeux Noirs (Dark Eyes)',
        );
        expect(p(title, 'PomplamooseMusic'), read);
        // Without music.db too: the title names Pomplamoose.
        expect(parseYouTubeTrack(title, 'PomplamooseMusic'), read);
        expect(parseYouTubeTrack(title, 'Pomplamoose Music'), read);
      },
    );

    test('"Official" goes in any case, "VEVO" as before', () {
      const read = (artist: 'Clutch', title: 'Profits of Doom');
      expect(p('Profits of Doom', 'OfficialClutch'), read);
      expect(parseYouTubeTrack('Profits of Doom', 'OfficialClutch'), read);
      expect(parseYouTubeTrack('Profits of Doom', 'Official Clutch'), read);
      expect(parseYouTubeTrack('Profits of Doom', 'ClutchOfficial'), read);
      expect(p('Profits of Doom', 'ClutchVEVO'), read);
      expect(p('Profits of Doom', 'ClutchMusic'), read);
    });

    test(
      'a name music.db knows, or one nothing confirms, keeps its "Music"',
      () {
        // A real artist's own name.
        expect(p('Some Song', 'BigMusic').artist, 'BigMusic');
        expect(
          p('Some Song', 'Music For Pleasure').artist,
          'Music For Pleasure',
        );
        // Neither music.db nor the title names "Pomplamoose".
        expect(
          parseYouTubeTrack('Les Yeux Noirs', 'PomplamooseMusic').artist,
          'PomplamooseMusic',
        );
        // Not glued after a small letter: no CamelCase suffix.
        expect(parseYouTubeTrack('Song', 'BIGMUSIC').artist, 'BIGMUSIC');
        // "Officially…" isn't the "Official" prefix.
        expect(
          parseYouTubeTrack('Song', 'Officially Yours').artist,
          'Officially Yours',
        );
        // A three-letter name in the title doesn't count.
        expect(parseYouTubeTrack('The Song', 'TheMusic').artist, 'TheMusic');
      },
    );

    test('"- Topic" channels are unaffected', () {
      expect(
        p('Profits of Doom', 'Clutch Music - Topic').artist,
        'Clutch Music',
      );
      expect(p('Profits of Doom', 'Official - Topic').artist, 'Official');
    });

    test('a title naming its artist keeps it', () {
      expect(p('Clutch - Profits of Doom', 'OfficialClutch'), (
        artist: 'Clutch',
        title: 'Profits of Doom',
      ));
    });
  });
}
