import 'package:flutter_test/flutter_test.dart';
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

    test('no separator: the channel (without VEVO) is the artist', () {
      expect(p('Mr. Vain (Original Radio Edit)', 'CultureBeatVEVO'), (
        artist: 'CultureBeat',
        title: 'Mr. Vain',
      ));
    });

    test('real versions are kept', () {
      expect(
        p('Björk - Army of Me (Sucker Punch Remix) [From Sucker Punch]', 'x'),
        (artist: 'Björk', title: 'Army of Me (Sucker Punch Remix)'),
      );
      expect(p('Merk & Kremont - Sad Story (Out of Luck) (Lyric Video)', 'x'), (
        artist: 'Merk & Kremont',
        title: 'Sad Story (Out of Luck)',
      ));
    });
  });
}
