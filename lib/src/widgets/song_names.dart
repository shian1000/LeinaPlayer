import 'package:flutter/widgets.dart';

import '../data/combined_search.dart';
import '../data/latin_names.dart';
import '../playback/player_controller.dart';
import '../theme_controller.dart';

/// Whether names in another alphabet get their Latin form after them (Ustawienia › Wygląd ›
/// "Nazwy w alfabecie łacińskim"); rebuilds [context] when it's switched.
bool showsLatinNames(BuildContext context) =>
    ThemeScope.maybeOf(context)?.latinNames ?? false;

/// A song's names as screens show them: "Кино (Kino)" with [showsLatinNames].
extension SongNames on SearchHit {
  String shownTitle(BuildContext context) =>
      showsLatinNames(context) ? withLatin(title, titleLatin) : title;

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
      showsLatinNames(context) ? withLatin(title, titleLatin) : title;

  String shownArtist(BuildContext context) =>
      showsLatinNames(context) ? withLatin(artist, artistLatin) : artist;
}
