import 'package:sqlite3/sqlite3.dart';

import 'text_normalizer.dart';

// Only at the end of a name: in "Noir OST I" what follows tells apart several albums of one work.
final _ending = RegExp(
  r'[\s\-–—:,]*[(\[]?\s*(?<![\p{L}\p{N}_])(?:(?:the|official|original)\s+)*'
  r'(?:(?:motion\s+picture|video\s+game|game|anime|film|movie|tv|series)\s+)?'
  r'(?:soundtracks?|o\.s\.t\.?|ost)\s*[)\]]?\s*$',
  caseSensitive: false,
  unicode: true,
);
final _alphanumeric = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// The film, game or anime a name ending in a soundtrack word is about ("Tekken 5 Soundtrack" →
/// "Tekken 5", "Fallout 4 (Original Game Soundtrack)" → "Fallout 4"), `null` for any other
/// name — a port of MusicDatabase's `soundtrack_work()` (`src/utils/common/soundtrack_names.py`).
String? soundtrackWork(String? name) {
  if (name == null) return null;
  final found = _ending.firstMatch(name);
  if (found == null) return null;
  final work = name.substring(0, found.start).trim();
  return _alphanumeric.hasMatch(work) ? work : null;
}

/// The films, games and anime a song may be credited to instead of who sings it ("Nana -
/// Kuroi Namida" is Anna Tsuchiya's song): music.db's `soundtrack_works` list (MusicDatabase's
/// migration 0025, hand-off `soundtrack-works-for-musicdatabaseapp.md`) with its other
/// spellings, and the works of `"<work> OST"` albums named in two words or more — "Rio OST"
/// would make "Rio Reiser" a film. A lite `matching_works()` / `credited_work()` of
/// MusicDatabase's `src/utils/database/soundtrack_albums.py`.
class SoundtrackWorks {
  const SoundtrackWorks([this._works = const {}]);

  static const none = SoundtrackWorks();

  static const _minWordsOfKnownWork = 2;

  /// normalizeForSearch(spelling) → the work's name.
  final Map<String, String> _works;

  /// The work [artist] is — one of the works, or a name ending in a soundtrack word — or
  /// `null`. Only a whole name: "Nana Mouskouri" isn't the anime.
  String? creditedWork(String? artist) =>
      _works[normalizeForSearch(artist)] ?? soundtrackWork(artist);

  /// [work]'s spellings, normalized: its name and its other names on the list.
  Set<String> spellingsOf(String work) => {
    normalizeForSearch(work),
    for (final MapEntry(:key, :value) in _works.entries)
      if (value == work) key,
  }..remove('');

  /// The works of [albumTitles] (`albums` that aren't singles; songs' albums before that
  /// table) and the listed ones; the list's spelling wins. Without `soundtrack_works` (a
  /// music.db from before migration 0025) only the albums'.
  static SoundtrackWorks read(Database db, Set<String> tables) {
    final works = <String, String>{};
    for (final title in _albumTitles(db, tables)) {
      final work = soundtrackWork(title);
      if (work == null) continue;
      final key = normalizeForSearch(work);
      if (key.split(' ').length >= _minWordsOfKnownWork) works[key] = work;
    }
    if (tables.contains('soundtrack_works')) {
      for (final row in db.select(
        'SELECT name, aliases FROM soundtrack_works',
      )) {
        final name = row['name']! as String;
        for (final spelling in [
          name,
          ...((row['aliases'] as String?) ?? '').split(','),
        ]) {
          final key = normalizeForSearch(spelling);
          if (key.isNotEmpty) works[key] = name;
        }
      }
    }
    return works.isEmpty ? none : SoundtrackWorks(works);
  }

  static Iterable<String> _albumTitles(Database db, Set<String> tables) {
    final Iterable<Row> rows;
    if (tables.contains('albums')) {
      final hasType = db
          .select('PRAGMA table_info(albums)')
          .any((c) => c['name'] == 'type');
      rows = db.select(
        hasType
            ? "SELECT title FROM albums WHERE type IS NULL OR type != 'single'"
            : 'SELECT title FROM albums',
      );
    } else {
      rows = db.select(
        'SELECT DISTINCT album AS title FROM songs WHERE album IS NOT NULL',
      );
    }
    return rows.map((row) => row['title']).whereType<String>();
  }
}

/// Does the normalized [text] hold one of [spellings] (normalized) as whole words — "Nana" in
/// "Anna Tsuchiya Inspi' Nana (Black Stones)", not in "Nanami"?
bool namesWork(String? text, Set<String> spellings) {
  final padded = ' ${normalizeForSearch(text)} ';
  return spellings.any((spelling) => padded.contains(' $spelling '));
}
