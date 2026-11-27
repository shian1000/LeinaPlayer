import 'package:flutter/widgets.dart';

import '../data/combined_search.dart';
import '../data/cover_credit.dart';
import '../data/latin_names.dart';
import '../data/lyrics_transliteration.dart';
import '../data/song_catalog.dart';
import '../data/song_requests.dart';
import '../data/version_names.dart';
import '../playback/player_controller.dart';
import '../l10n.dart';
import '../theme_controller.dart';

/// How names in another alphabet are shown (Ustawienia › Wygląd › Transliteracja) for a song
/// in [language] (music.db's `songs.language`; one of "Języki wyłączone z transliteracji"
/// shows none), with Ukrainian names in the Slavic alphabet when it's picked; rebuilds
/// [context] when it's changed.
LatinNamesShown latinNamesOf(BuildContext context, {String? language}) {
  final themes = ThemeScope.maybeOf(context);
  if (themes == null) return const LatinNamesShown(LatinNames.original);
  return LatinNamesShown(
    themes.latinNamesFor(language),
    themes.ukrainianTransliteration == UkrainianTransliteration.slavic
        ? latinAlternativesOf(context, ukrainianSlavicMethod)
        : const {},
  );
}

/// [SongCatalog.latinAlternatives] of [method]. Without depending on the catalog: every name
/// on screen would rebuild with each of its changes, and a new music.db rebuilds the lists.
Map<String, String> latinAlternativesOf(BuildContext context, String method) =>
    context
        .getInheritedWidgetOfExactType<SongCatalogScope>()
        ?.notifier
        ?.latinAlternatives[method] ??
    const {};

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
  String? language,
) {
  final latin = latinNamesOf(context, language: language);
  title = _placeholderShown(title);
  final coveredName = covered?.name;
  return titleWithCover(
    // Titles have no forms of other methods yet: [LatinNamesShown.forms] are artists' names.
    titleWithVersion(latin.names.show(title, titleLatin), version),
    coveredName != null && latin.forms[coveredName] != null
        ? CoverOf(coveredName, latin.forms[coveredName])
        : covered,
    latin: latin.shown,
  );
}

/// A song's names as screens show them: "Кино (Kino)" as [latinNamesOf] says, then a version's
/// marker and a cover's credit after the title: "Creep (Live) (Radiohead cover)".
extension SongNames on SearchHit {
  String shownTitle(BuildContext context) => _titleShown(
    context,
    title,
    titleLatin,
    coverOf,
    version,
    mainSong?.language,
  );

  String shownArtist(BuildContext context) => latinNamesOf(
    context,
    language: mainSong?.language,
  ).show(_placeholderShown(artistLabel), artistLatin);

  String? shownAlbum(BuildContext context) => album == null
      ? null
      : latinNamesOf(
          context,
          language: mainSong?.language,
        ).names.show(album!, albumLatin);
}

extension NowPlayingNames on NowPlaying {
  String shownTitle(BuildContext context) =>
      _titleShown(context, title, titleLatin, coverOf, version, language);

  String shownArtist(BuildContext context) => latinNamesOf(
    context,
    language: language,
  ).show(_placeholderShown(artist), artistLatin);
}
