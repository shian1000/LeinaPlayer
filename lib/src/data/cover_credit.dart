/// What a cover is a cover of, as its credit names it: the artist (`songs.covered_artist_id`),
/// or for a traditional song with no artist to name `songs.covered_title`. The credit is never
/// part of `songs.title`: MusicDatabase keeps the title without it (hand-off
/// `cover-songs-for-musicdatabaseapp.md`).
class CoverOf {
  const CoverOf(this.name, [this.latin]);

  final String name;

  /// Its Latin form, when [name] is in another alphabet (`latin_names.dart`).
  final String? latin;

  /// What song search finds a cover by, as the credit is shown with its title.
  String get searchText => [name, ?latin, 'cover'].join(' ');
}

/// "Crazy in Love (Beyoncé cover)", or just [title] when it isn't a cover. With [latin] the
/// credit has the Latin form instead of the name beside it, to spare "(Кино (Kino) cover)".
String titleWithCover(String title, CoverOf? covered, {bool latin = false}) =>
    covered == null
    ? title
    : '$title (${(latin ? covered.latin : null) ?? covered.name} cover)';

const _notAWordPart = r'[\p{L}\p{N}_]';
final _bracket = RegExp(r'[\(\[【]([^()\[\]【】]*)[\)\]】]');
final _coverWord = RegExp(
  '(?<!$_notAWordPart)(?:cover|кавер)(?!$_notAWordPart)',
  unicode: true,
  caseSensitive: false,
);
// "Twinz (Deep Cover '98)" is that song's name.
final _notACover = RegExp(
  '(?<!$_notAWordPart)(?:deep|under|take)\\s+cover(?!$_notAWordPart)'
  '|(?<!$_notAWordPart)cover\\s+(?:me|up)(?!$_notAWordPart)',
  unicode: true,
  caseSensitive: false,
);
final _coveredBy = RegExp(
  r'^\s*cover(?:ed)?\s+by\s+(.+?)\s*$',
  caseSensitive: false,
);
final _spaces = RegExp(r'\s+');

/// A title with its bracketed cover credit dropped, or `null` when it has none: "Creep (Radiohead
/// cover)" is "Creep". [performer] is the name of a "(Cover by X)", where X plays it and the
/// artist before it is the one covered. A lite version of MusicDatabase's `read_cover()`
/// (`src/utils/common/cover_names.py`; ADR 0003).
({String title, String? performer})? readCoverCredit(String title) {
  if (_notACover.hasMatch(title)) return null;
  for (final bracket in _bracket.allMatches(title)) {
    final inside = bracket.group(1)!;
    final by = _coveredBy.firstMatch(inside);
    if (by == null && !_coverWord.hasMatch(inside)) continue;
    final rest = title
        .replaceRange(bracket.start, bracket.end, ' ')
        .replaceAll(_spaces, ' ')
        .trim();
    return rest.isEmpty ? null : (title: rest, performer: by?.group(1));
  }
  return null;
}
