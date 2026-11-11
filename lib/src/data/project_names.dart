import 'text_normalizer.dart';

/// A row of music.db's `projects` dictionary (MusicDatabase's migration 0019, hand-off
/// `projects-for-musicdatabaseapp.md`): the series or compilation a recording was made for
/// (Tiny Desk, Like a Version). [aliases] are its other spellings, [channels] the channels
/// publishing it ("NPR Music"), both comma-separated in music.db.
class Project {
  Project(this.name, {String? aliases, String? channels})
    : aliases = _splitNames(aliases),
      channels = _splitNames(channels);

  final String name;
  final List<String> aliases;
  final List<String> channels;

  List<String> get spellings => [name, ...aliases];

  static List<String> _splitNames(String? text) => [
    for (final part in (text ?? '').split(','))
      if (part.trim() case final name when name.isNotEmpty) name,
  ];
}

/// What a song's artist and title say once [project] is out of them: "Boys (Like a Version)"
/// is "Boys" of Like a Version.
typedef ProjectReading = ({Project project, String artist, String title});

const _word = r'[\p{L}\p{N}_]';
const _notWord = r'[^\p{L}\p{N}_]';
final _words = RegExp('$_word+', unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);
// What may be said around a spelling and goes with it: "Live at Męskie Granie", "Kaunas
// Acoustics Session".
const _leadIn = r'(?:(?:live\s+)?(?:at|on|from|for)\s+|@\s*)?';
const _trailingWord = r'(?:\s+(?:sessions?|concert|performance))?';
const _edgeSeparators = ' -–—|:;,./~•·';
const _separatorsAroundAName = ':|-–—/';
const _brackets = {
  '(': ')',
  '[': ']',
  '{': '}',
  '【': '】',
  '（': '）',
  '「': '」',
  '［': '］',
};
final _repeatedSeparator = RegExp(r'(\s[-–—|:]\s+)(?:[-–—|:]\s+)+');
final _emptyListItem = RegExp(r'\s*,\s*(?=[)\]}】）」］])|(?<=[(\[{【（「［])\s*,\s*');
final _artistTitle = RegExp(r'\s+[-–—]\s+|\s+:\s+');
// A spelling naming a performance itself: only then can a title be the whole set of whoever it
// names. "Męskie Granie" - "Rilke" is just a song.
final _wholeSetWord = RegExp(
  '(?<!$_word)(?:concerts?|koncert|sessions?|sesja)(?!$_word)',
  unicode: true,
  caseSensitive: false,
);
final _spaces = RegExp(r'\s+');
final _spellingPatterns = <String, RegExp?>{};

RegExp? _spellingPattern(String spelling) =>
    _spellingPatterns.putIfAbsent(spelling, () {
      final words = [
        for (final word in _words.allMatches(spelling)) RegExp.escape(word[0]!),
      ];
      if (words.isEmpty) return null;
      return RegExp(
        '(?<!$_word)$_leadIn(?<core>${words.join('$_notWord*')})'
        '$_trailingWord(?!$_word)',
        unicode: true,
        caseSensitive: false,
      );
    });

/// The project of the longest spelling in [text] and where it is, or `null`.
(Project, RegExpMatch)? _find(String? text, List<Project> projects) {
  if (text == null || text.isEmpty) return null;
  (Project, RegExpMatch)? best;
  for (final project in projects) {
    for (final spelling in project.spellings) {
      final found = _spellingPattern(spelling)?.firstMatch(text);
      if (found != null &&
          (best == null ||
              found.namedGroup('core')!.length >
                  best.$2.namedGroup('core')!.length)) {
        best = (project, found);
      }
    }
  }
  return best;
}

/// Is [name] one of [project]'s spellings (or, with [channels], one of its channels)?
bool _namedBy(String name, Project project, {bool channels = true}) {
  final key = normalizeForSearch(name);
  return key.isNotEmpty &&
      [
        ...project.spellings,
        if (channels) ...project.channels,
      ].any((other) => normalizeForSearch(other) == key);
}

String _strip(String text, String characters) {
  var start = 0, end = text.length;
  while (start < end && characters.contains(text[start])) {
    start++;
  }
  while (end > start && characters.contains(text[end - 1])) {
    end--;
  }
  return text.substring(start, end);
}

/// Where the bracket around `text[start, end)` opens and closes, or `null`.
(int, int)? _enclosingBracket(String text, int start, int end) {
  for (var position = start - 1; position >= 0; position--) {
    final closing = _brackets[text[position]];
    if (closing != null) {
      final close = text.indexOf(closing, end);
      return close >= 0 ? (position, close) : null;
    }
    if (_brackets.containsValue(text[position])) return null;
  }
  return null;
}

/// The project [text] names, [text] without it and the spelling as written, or `null`:
/// "Boys (Like a Version)" is "Boys", "Daughter | Tiny Desk Concert" is "Daughter". A bracket
/// left with nothing but numbers in it goes too: "(Męskie Granie 2018)" is that edition.
(Project, String, String)? _cut(String? text, List<Project> projects) {
  final found = _find(text, projects);
  if (found == null) return null;
  final (project, match) = found;
  var (start, end) = (match.start, match.end);
  if (_enclosingBracket(text!, start, end) case (final open, final close)
      when !_letter.hasMatch(
        text.substring(open + 1, start) + text.substring(end, close),
      )) {
    (start, end) = (open, close + 1);
  }
  final rest = (text.substring(0, start) + text.substring(end))
      .replaceAll(_spaces, ' ')
      .trim()
      .replaceAll(_emptyListItem, '')
      .replaceAllMapped(_repeatedSeparator, (m) => m[1]!);
  return (project, _strip(rest, _edgeSeparators), match.namedGroup('core')!);
}

/// A whole set's title: the spelling found without the channel publishing it — "NPR Music Tiny
/// Desk Concert" is "Tiny Desk Concert".
String _wholeSetTitle(Project project, String spelling) {
  for (final channel in project.channels) {
    final found = _spellingPattern(channel)?.matchAsPrefix(spelling);
    if (found == null) continue;
    final rest = _strip(spelling.substring(found.end), _edgeSeparators);
    if (rest.isNotEmpty) return rest;
  }
  return spelling;
}

/// Does a separator or a bracket divide the project from the rest of [text]? "Kaunas Acoustics
/// : Liūdni slibinai" — but "Męskie Granie Orkiestra 2022" is one name, the project only part
/// of it.
bool _setApart(String text, RegExpMatch match) {
  final before = text.substring(0, match.start).trimRight();
  final after = text.substring(match.end).trimLeft();
  return before.isNotEmpty &&
          '$_separatorsAroundAName([{【（「［'.contains(
            before[before.length - 1],
          ) ||
      after.isNotEmpty && '$_separatorsAroundAName)]}】）」］'.contains(after[0]);
}

/// The project a song's [artist] or [title] names, with the artist and title it leaves, or
/// `null` — a lite version of MusicDatabase's `read_project()`
/// (`src/utils/common/project_names.py`; ADR 0003). Only whole spellings from [projects] count
/// ("Session" alone says nothing), case ignored. A channel of the project as the artist ("NPR
/// Music") leaves who plays in the title: "Daughter: Tiny Desk Concert" is Daughter's whole set.
/// An artist whose name only contains the project keeps it ("Męskie Granie Orkiestra 2016"); one
/// that is only the project ("Męskie Granie") stays, though it says nothing of who plays.
ProjectReading? readProject(
  String artist,
  String title,
  List<Project> projects,
) {
  if (projects.isEmpty) return null;
  final inArtist = _find(artist, projects);
  if (inArtist case (final project, final match)
      when _setApart(artist, match)) {
    final (_, rest, _) = _cut(artist, projects)!;
    if (rest.isNotEmpty) {
      final inTitle = _cut(title, projects);
      return (
        project: project,
        artist: rest,
        title: inTitle == null || inTitle.$2.isEmpty ? title : inTitle.$2,
      );
    }
  }
  if (_cut(title, projects) case (final project, final rest, final spelling)) {
    final wholeSet = _wholeSetWord.hasMatch(spelling);
    if (_namedBy(artist, project, channels: false) && !wholeSet) {
      return (
        project: project,
        artist: artist,
        title: rest.isEmpty ? spelling : rest,
      );
    }
    if (_namedBy(artist, project)) {
      // A channel as the artist: who plays is in the title.
      if (rest.isEmpty) {
        return (
          project: project,
          artist: artist,
          title: _wholeSetTitle(project, spelling),
        );
      }
      if (_artistTitle.firstMatch(rest) case final separator?
          when separator.start > 0 && separator.end < rest.length) {
        return (
          project: project,
          artist: rest.substring(0, separator.start),
          title: rest.substring(separator.end),
        );
      }
      return (
        project: project,
        artist: rest,
        title: _wholeSetTitle(project, spelling),
      );
    }
    return (
      project: project,
      artist: artist,
      title: rest.isEmpty ? _wholeSetTitle(project, spelling) : rest,
    );
  }
  if (inArtist case (final project, _)) {
    return (project: project, artist: artist, title: title);
  }
  return null;
}
