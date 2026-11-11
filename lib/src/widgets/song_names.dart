import 'package:flutter/widgets.dart';

import '../data/combined_search.dart';
import '../data/cover_credit.dart';
import '../data/latin_names.dart';
import '../data/version_names.dart';
import '../playback/player_controller.dart';
import '../theme_controller.dart';

/// Whether names in another alphabet get their Latin form after them (Ustawienia › Wygląd ›
/// "Nazwy w alfabecie łacińskim"); rebuilds [context] when it's switched.
bool showsLatinNames(BuildContext context) =>
    ThemeScope.maybeOf(context)?.latinNames ?? false;

String _titleShown(
  BuildContext context,
  String title,
  String? titleLatin,
  CoverOf? covered,
  SongVersion? version,
) {
  final latin = showsLatinNames(context);
  return titleWithCover(
    titleWithVersion(latin ? withLatin(title, titleLatin) : title, version),
    covered,
    latin: latin,
  );
}

/// A song's names as screens show them: "Кино (Kino)" with [showsLatinNames], then a version's
/// marker and a cover's credit after the title: "Creep (Live) (Radiohead cover)".
extension SongNames on SearchHit {
  String shownTitle(BuildContext context) =>
      _titleShown(context, title, titleLatin, coverOf, version);

  String shownArtist(BuildContext context) => showsLatinNames(context)
      ? withLatin(artistLabel, artistLatin)
      : artistLabel;

  String? shownAlbum(BuildContext context) =>
      album == null || !showsLatinNames(context)
      ? album
      : withLatin(album!, albumLatin);
}

extension NowPlayingNames on NowPlaying {
  String shownTitle(BuildContext context) =>
      _titleShown(context, title, titleLatin, coverOf, version);

  String shownArtist(BuildContext context) =>
      showsLatinNames(context) ? withLatin(artist, artistLatin) : artist;
}
