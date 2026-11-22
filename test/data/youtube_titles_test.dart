import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_playlist.dart';
import 'package:music_database_app/src/data/youtube_search.dart';
import 'package:music_database_app/src/data/youtube_titles.dart';

// What YouTube's InnerTube gave for the playlist "Preuzeti (2018.05)" on 2026-11-22, asked in
// English ("hl": "en") and in Polish: L.U.C.'s video came translated in English only.
const _english =
    'L.U.C. feat. K.Prońko, K2, Mesajah  - In relation to (Official video)';
const _original =
    'L.U.C. ft. K. Prońko, K2, Mesajah - W związku z tym (official video)';

// Its oEmbed answer, shortened (the same whatever language is asked).
const _oEmbed =
    '{"title":"L.U.C. ft. K. Pro\\u0144ko, K2, Mesajah - W zwi\\u0105zku z tym '
    '(official video)","author_name":"MaxFloRec TV","type":"video",'
    '"provider_name":"YouTube"}';

YouTubePlaylistData _playlist(String lucTitle) => YouTubePlaylistData(
  id: 'PLtr9YjCLuScTUYmIOZ_9s_nqvLlTww_HM',
  name: 'Preuzeti (2018.05)',
  owner: null,
  videos: [
    const YouTubeVideo(
      id: 'HEkerSi5Fig',
      title: 'SCANDAL - Shunkan Sentimental',
      channel: 'SCANDAL',
    ),
    YouTubeVideo(id: 'KiTVO7GPsqQ', title: lucTitle, channel: 'MaxFloRec TV'),
  ],
);

void main() {
  test('oEmbed gives the original title', () {
    expect(titleFromOEmbed(_oEmbed), _original);
    expect(titleFromOEmbed('{"author_name":"x"}'), isNull);
  });

  test('titles that differ between two languages are the translated ones', () {
    expect(translatedTitleIds(_playlist(_english), _playlist(_original)), {
      'KiTVO7GPsqQ',
    });
    expect(
      translatedTitleIds(_playlist(_original), _playlist(_original)),
      isEmpty,
    );
  });

  group('YouTubePlaylists', () {
    final settings = SourceSettings();
    final asked = <String>[];

    setUp(asked.clear);

    YouTubePlaylists playlists({
      Future<String?> Function(String id)? originalTitle,
      bool secondFails = false,
    }) => YouTubePlaylists(
      newPipeAvailable: true,
      newPipe: (id) async => _playlist(_english),
      newPipeIn: (id, language) async {
        if (secondFails) throw Exception('offline');
        return _playlist(language == 'en' ? _english : _original);
      },
      originalTitle:
          originalTitle ??
          (id) async {
            asked.add(id);
            return titleFromOEmbed(_oEmbed);
          },
    );

    test('a translated title is put back as the uploader wrote it', () async {
      final data = await playlists().fetch('PL', settings);
      expect(data.videos.map((v) => v.title), [
        'SCANDAL - Shunkan Sentimental',
        _original,
      ]);
      // Only the translated video is asked for.
      expect(asked, ['KiTVO7GPsqQ']);
      expect(parseYouTubeTrack(data.videos.last.title, 'MaxFloRec TV'), (
        artist: 'L.U.C. ft. K. Prońko, K2, Mesajah',
        title: 'W związku z tym',
      ));
    });

    test(
      'without the second reading or oEmbed the first reading stays',
      () async {
        expect(
          (await playlists(
            secondFails: true,
          ).fetch('PL', settings)).videos.last.title,
          _english,
        );
        expect(
          (await playlists(
            originalTitle: (id) async => throw Exception('offline'),
          ).fetch('PL', settings)).videos.last.title,
          _english,
        );
      },
    );
  });
}
