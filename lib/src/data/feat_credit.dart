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
