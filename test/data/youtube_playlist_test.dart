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
      expect(
        channelVideoReadings('Łona i ja na rowerze', 'x', artistNamed),
        [(artist: 'Łona', title: 'i ja na rowerze')],
      );
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
}
