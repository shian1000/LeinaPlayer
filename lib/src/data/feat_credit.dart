final _bracket = RegExp(r'\s*[\(\[【]([^()\[\]【】]*)[\)\]】]');
// A bracket's content that is a credit: "(feat. X)", "(with X)".
final _creditInBracket = RegExp(
  r'^\s*(?:feat\.?|ft\.?|featuring|with)\s',
  caseSensitive: false,
);
// An unbracketed credit, up to " - " or the next bracket: "(Remix)" after it stays.
final _bareCredit = RegExp(
  r'(?:^|\s)(?:feat\.?|ft\.?|featuring)\s+[^()\[\]【】]+?(?=\s+[-–—]\s|\s*[()\[\]【】]|$)',
  caseSensitive: false,
);
final _spaces = RegExp(r'\s+');

/// A title with its featured-artist credits dropped, bracketed or not ("Tamagotchi feat. Dawid
/// Podsiadło", "Выше головы (feat. Тося)", "Song (feat. X) (Remix)" is "Song (Remix)"), or `null`
/// when it has none or is nothing but one. music.db keeps such credits out of `songs.title`
/// (they are `additional_song_artists`). A lite version of MusicDatabase's
/// `strip_feat_credits()` (`src/utils/common/artist_credits.py`; ADR 0003).
String? withoutFeatCredits(String title) {
  final bare = title
      .replaceAllMapped(
        _bracket,
        (m) => _creditInBracket.hasMatch('${m.group(1)!} ') ? ' ' : m.group(0)!,
      )
      .replaceAll(_bareCredit, ' ')
      .replaceAll(_spaces, ' ')
      .trim();
  return bare.isEmpty || bare == title.trim() ? null : bare;
}

// Between equal artists, as MusicDatabase's `_MAIN_SEPARATOR`: " x " lowercase only ("Malcolm X").
final _mainJoin = RegExp(r',\s+|\s+(?:&|x|/|\+|vs\.?)\s+');
// … and its ARTIST_JOINING_WORDS ("Dawid Podsiadło i Kaśka Sochacka"), any case.
final _joiningWord = RegExp(
  r'\s+(?:and|und|et|i|y|і|и|та)\s+',
  caseSensitive: false,
);

/// The artists a joined credit names ("Dawid Podsiadło i Kaśka Sochacka", "A & B", "A x B"),
/// or `null` when it names one. Purely textual — "Simon & Garfunkel" splits too — so a caller
/// takes the parts only when each is an artist it already knows. The separators of
/// MusicDatabase's `propose_artist_split()` (`src/utils/common/artist_credits.py`; ADR 0003).
List<String>? artistCreditParts(String artist) {
  final parts = [
    for (final piece in artist.split(_mainJoin))
      for (final part in piece.split(_joiningWord))
        if (part.trim().isNotEmpty) part.trim(),
  ];
  return parts.length < 2 ? null : parts;
}
