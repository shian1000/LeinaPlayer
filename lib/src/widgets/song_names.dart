import 'package:flutter/widgets.dart';

import '../data/combined_search.dart';
import '../data/cover_credit.dart';
import '../data/latin_names.dart';
import '../data/song_requests.dart';
import '../data/version_names.dart';
import '../playback/player_controller.dart';
import '../l10n.dart';
import '../theme_controller.dart';

/// How names in another alphabet are shown (Ustawienia › Wygląd › "Nazwy w alfabecie
/// łacińskim"); rebuilds [context] when it's changed.
LatinNames latinNamesOf(BuildContext context) =>
    ThemeScope.maybeOf(context)?.latinNames ?? LatinNames.original;

/// The title a video gets when nothing better is known (`video_link.dart`,
/// `combined_search.dart`): kept Polish there, as it also goes into match keys and requests.
const _youTubeVideoTitle = 'Film z YouTube';

/// Polish placeholders kept as values (see [_youTubeVideoTitle], [SongRequest.unknownArtist]),
/// shown in the app's language.
String _placeholderShown(String value) => switch (value) {
  _youTubeVideoTitle => l10n.songNamesYouTubeVideo,
  SongRequest.unknownArtist => l10n.songNamesUnknownArtist,
  _ => value,
};

String _titleShown(
  BuildContext context,
  String title,
  String? titleLatin,
  CoverOf? covered,
  SongVersion? version,
) {
  final latin = latinNamesOf(context);
  title = _placeholderShown(title);
  return titleWithCover(
    titleWithVersion(latin.show(title, titleLatin), version),
    covered,
    latin: latin.shown,
  );
}

/// A song's names as screens show them: "Кино (Kino)" as [latinNamesOf] says, then a version's
/// marker and a cover's credit after the title: "Creep (Live) (Radiohead cover)".
extension SongNames on SearchHit {
  String shownTitle(BuildContext context) =>
      _titleShown(context, title, titleLatin, coverOf, version);

  String shownArtist(BuildContext context) =>
      latinNamesOf(context).show(_placeholderShown(artistLabel), artistLatin);

  String? shownAlbum(BuildContext context) =>
      album == null ? null : latinNamesOf(context).show(album!, albumLatin);
}

extension NowPlayingNames on NowPlaying {
  String shownTitle(BuildContext context) =>
      _titleShown(context, title, titleLatin, coverOf, version);

  String shownArtist(BuildContext context) =>
      latinNamesOf(context).show(_placeholderShown(artist), artistLatin);
}
