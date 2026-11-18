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

  group('parseYouTubeTrack', () {
    ({String artist, String title}) p(String title, String channel) =>
        parseYouTubeTrack(title, channel);

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
