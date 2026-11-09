import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/cover_credit.dart';
import 'package:music_database_app/src/data/youtube_matcher.dart';
import 'package:music_database_app/src/data/youtube_video.dart';

void main() {
  test('a cover is shown with its credit, Latin form instead of the name', () {
    const beyonce = CoverOf('Beyoncé');
    const kino = CoverOf('Кино', 'Kino');
    expect(titleWithCover('Creep', null), 'Creep');
    expect(
      titleWithCover('Crazy in Love', beyonce, latin: true),
      'Crazy in Love (Beyoncé cover)',
    );
    expect(titleWithCover('Song', kino), 'Song (Кино cover)');
    expect(titleWithCover('Song', kino, latin: true), 'Song (Kino cover)');
  });

  test('the credit is read from brackets only, not from a song\'s name', () {
    expect(readCoverCredit('Creep (Radiohead cover)')?.title, 'Creep');
    expect(readCoverCredit('Creep [Acoustic Cover]')?.title, 'Creep');
    expect(readCoverCredit('Песня (кавер)')?.title, 'Песня');
    final by = readCoverCredit('Look At Me Now (Cover by Karmin)')!;
    expect(by.title, 'Look At Me Now');
    expect(by.performer, 'Karmin');

    expect(readCoverCredit('Creep'), isNull);
    expect(readCoverCredit('Creep (Live)'), isNull);
    expect(readCoverCredit("Twinz (Deep Cover '98)"), isNull);
    expect(readCoverCredit('Cover Me (Remix)'), isNull);
    expect(readCoverCredit('(Cover)'), isNull);
  });

  group('looking for a cover on YouTube', () {
    YouTubeVideo video(String id, String title, String channel) => YouTubeVideo(
      id: id,
      title: title,
      channel: channel,
      duration: const Duration(seconds: 200),
      viewCount: 1000,
    );
    final cover = MatchTarget(
      title: 'Creep',
      mainArtists: [MatchArtist('Hannah Rue')],
      coverOf: 'Radiohead',
    );

    test('the query names the covered artist', () {
      expect(cover.query, 'Hannah Rue Creep Radiohead cover');
    });

    test('a video saying "cover" is preferred, and the original refused', () {
      expect(
        pickYouTubeVideo(cover, [
          video('plain', 'Hannah Rue - Creep', 'Fan uploads'),
          video('credited', 'Hannah Rue - Creep (Radiohead cover)', 'Other'),
          video('original', 'Radiohead - Creep', 'Radiohead'),
        ])?.id,
        'credited',
      );
      expect(
        pickYouTubeVideo(cover, [
          video('original', 'Radiohead - Creep', 'Radiohead'),
        ]),
        isNull,
      );
    });
  });
}
