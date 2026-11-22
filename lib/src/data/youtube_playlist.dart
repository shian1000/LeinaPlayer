import 'feat_credit.dart';
import 'latin_names.dart';
import 'text_normalizer.dart';
import 'youtube_video.dart';

/// A YouTube playlist as fetched for import.
class YouTubePlaylistData {
  const YouTubePlaylistData({
    required this.id,
    required this.name,
    required this.owner,
    required this.videos,
  });

  final String id;
  final String name;

  /// The channel that made the playlist, when known.
  final String? owner;
  final List<YouTubeVideo> videos;
}

/// The playlist id from a pasted link (`.../playlist?list=PL…`, or a watch link that carries
/// `&list=`), or a bare id; `null` when there's none. Same rules as MusicDatabase's
/// `extract_playlist_id()`.
String? extractPlaylistId(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final fromLink = RegExp(r'[?&]list=([\w-]+)').firstMatch(text);
  if (fromLink != null) return fromLink.group(1);
  return RegExp(r'^[\w-]+$').hasMatch(text) && !text.contains('/')
      ? text
      : null;
}

/// Artist and song title of a playlist video — a lite version of MusicDatabase's
/// `build_metadata_from_item()` (`src/utils/youtube/import_from_playlist.py`; ADR 0003): drops
/// "| channel" suffixes, hashtags and junk brackets ("(Official Video)", "[HD]", "(2019)"), takes
/// the artist from a "`<Artist> - Topic`" channel, else splits "Artist - Title" (a dash inside a
/// bracket doesn't split: "Summer Paradise (Future Funk - Vaporwave - Electronic Mix)"; a
/// " -- " goes first: "18.White House Records & Fisz -- Na sznurowadle - KODEX" is Fisz's
/// "Na sznurowadle", the label's compilation's track number and name dropped), else
/// "Artist: Title" when the part before the colon is the channel or an artist music.db knows,
/// else uses the channel name. "Title - Lyric Video (English / French)" — junk only after the
/// separator — is the left part by the channel. Real version markers (Remix, Live, feat., …) are
/// kept, with the rest of their bracket: "(Live @ Odra, Wrocław / ZORZA 2025)" isn't junk for its
/// year. An event's "`<event 2018> | <artist> | <song> | <channel>`" reads as that artist and
/// song. "Artist- Title", the dash glued to the artist, splits too, and a title in quotes
/// (`''Aniolek''`, „…”) loses them. Credits after the title go: a producer's ("prod. Sergiusz",
/// [withoutProducerCredits]) and players' (", gitara …"); a guest ("gość Sarsa", " - feat. X -")
/// joins the artist as "feat.". "┃Cover by Raon Lee" names the performer (the channel when it is
/// that name's start). A bracket right after the artist's name at the start is its logo ("alt-J
/// (∆) Breezeblocks"), one in another alphabet after a Latin title its original ("SILHOUETTE
/// (シルエット)"), and "(Bob Dylan's 'Man Gave Names…')" names the song it's a version of.
///
/// With [artistNamed] (`SongCatalog.artistNamed`) — for names that are stored or asked for — a
/// video whose artist could only come from a channel music.db doesn't know as an artist is
/// read by [channelVideoReadings] ("General Woo U mom zivotu" by a fan's channel), a title that
/// is only a known artist takes its first hashtag as the song ("Łona #hot16challenge"), and
/// "The Cure | Talk Talk | Foghorn - muzyka na jesień" names those artists.
({String artist, String title}) parseYouTubeTrack(
  String videoTitle,
  String channel, {
  String? Function(String name)? artistNamed,
}) {
  final read = _readYouTubeTrack(videoTitle, channel, artistNamed);
  if (artistNamed != null &&
      read.fromChannel &&
      artistNamed(read.artist) == null) {
    if (read.hashtags.isNotEmpty) {
      if (artistNamed(read.title) case final artist?) {
        return (artist: artist, title: read.hashtags.first);
      }
    }
    final readings = channelVideoReadings(videoTitle, channel, artistNamed);
    if (readings.isNotEmpty) return readings.first;
  }
  return (artist: read.artist, title: read.title);
}

/// Other readings of a video whose artist [parseYouTubeTrack] could only take from the channel,
/// for when its reading names no song — a lite part of MusicDatabase's title parsing (ADR 0003):
/// the title starting with a whole artist name ("renata przemyk bo jesli tak ma byc" by
/// "thericeburner" is "bo jesli tak ma byc" by Renata Przemyk), longest name first, also past a
/// second artist joined to it ("Łona i Webber Wyślij sobie pocztówkę" by a label), and an
/// artist in the trailing bracket ("Wonderful Life (Smith & Burrows)" by "Peaky Blinders").
/// [artistNamed] says which artist goes by a name (`SongCatalog.artistNamed`): only a name
/// music.db knows counts, so a title's first words aren't taken for an artist otherwise.
List<({String artist, String title})> channelVideoReadings(
  String videoTitle,
  String channel,
  String? Function(String name) artistNamed,
) {
  final read = _readYouTubeTrack(videoTitle, channel, null);
  if (!read.fromChannel) return const [];
  final readings = <({String artist, String title})>[];
  final words = read.title.split(' ');
  for (var i = words.length - 1; i > 0; i--) {
    if (artistNamed(words.take(i).join(' ')) case final artist?) {
      final rest = words.skip(i).toList();
      // "Łona i Webber Wyślij sobie pocztówkę": a second artist joined to the first one.
      if (rest.length > 2 && _artistJoiner.hasMatch(rest.first)) {
        for (var j = rest.length - 1; j > 1; j--) {
          if (artistNamed(rest.sublist(1, j).join(' ')) != null) {
            readings.add((artist: artist, title: rest.skip(j).join(' ')));
            break;
          }
        }
      }
      readings.add((artist: artist, title: rest.join(' ')));
    }
  }
  final bracket = _trailingBracket.firstMatch(read.title);
  if (bracket != null && bracket.start > 0) {
    if (artistNamed(bracket.group(1)!) case final artist?) {
      readings.add((
        artist: artist,
        title: read.title.substring(0, bracket.start).trim(),
      ));
    }
  }
  return readings;
}

({String artist, String title, bool fromChannel, List<String> hashtags})
_readYouTubeTrack(
  String videoTitle,
  String channel,
  String? Function(String name)? artistNamed,
) {
  var title = videoTitle
      .replaceAllMapped(_doubledBracket, (m) => '(${m.group(1)!})')
      .replaceFirst(_trackNumber, '');
  String? coverBy;
  title = title.replaceFirstMapped(_coverBy, (m) {
    coverBy = m.group(1)!.trim();
    return '';
  }).trim();
  if (_splitEventPipes(title, channel) case (final artist, final song)) {
    title = '$artist - $song';
  } else if (artistNamed != null) {
    title = _pipedArtists(title, artistNamed) ?? title;
  }
  title = title.replaceAll(_pipeSuffix, '');
  title = title.replaceAllMapped(
    _anyBracket,
    (m) =>
        _junkAnywhere.hasMatch(m.group(1)!) &&
            !_versionMarker.hasMatch(m.group(1)!)
        ? ' '
        : m.group(0)!,
  );
  final withHashtags = title;
  final hashtags = [
    for (final tag in _hashtag.allMatches(withHashtags))
      if (tag.group(0)!.substring(1) case final word when word.isNotEmpty) word,
  ];
  title = title.replaceAll(_hashtag, ' ').replaceAll(_spaces, ' ').trim();
  // A title that is nothing but hashtags ("#Życzliwość") is their words.
  if (title.isEmpty) {
    title = withHashtags.replaceAll('#', ' ').replaceAll(_spaces, ' ').trim();
  }

  final topic = RegExp(r'\s*-\s*topic$', caseSensitive: false);
  String artist;
  String song;
  var fromChannel = false;
  if (topic.hasMatch(channel)) {
    artist = channel.replaceAll(topic, '').trim();
    song = title;
  } else if (_splitDoubleDash(title) case (final left, final right)) {
    artist = _withoutLabel(left, channel);
    song = right;
  } else {
    final split =
        _splitSpaced(title) ??
        _splitGlued(title) ??
        _splitColon(title, channel, artistNamed);
    if (coverBy case final performer?) {
      final name = _cleanChannel(channel);
      final normalizedName = normalizeForSearch(name);
      final normalizedPerformer = normalizeForSearch(performer);
      artist =
          normalizedName.isNotEmpty &&
              (normalizedPerformer == normalizedName ||
                  normalizedPerformer.startsWith('$normalizedName '))
          ? name
          : performer;
      song = split?.$2 ?? title;
      // "Radiohead - Creep | Cover by X": the original's artist, when music.db knows it.
      final original = split == null ? null : artistNamed?.call(split.$1);
      if (original != null) {
        song = '$song ($original cover)';
      }
    } else {
      fromChannel = split == null || _isJunkOnly(split.$2, split.$1, channel);
      if (split != null && fromChannel) {
        artist = _cleanChannel(channel);
        song = split.$1;
      } else {
        artist = split?.$1 ?? _cleanChannel(channel);
        song = split?.$2 ?? title;
      }
    }
  }
  song = _stripArtist(song, artist);
  song = withoutProducerCredits(song).replaceFirst(_playerCredit, '').trim();
  if (_guestCredit.firstMatch(song) case final guest? when guest.start > 0) {
    artist = '$artist feat. ${guest.group(1)!.trim()}';
    song = song.substring(0, guest.start).trim();
  }
  song = stripTrailingJunkSuffix(
    _stripJunkSuffix(song).replaceFirst(_trailingOfficial, ''),
  ).replaceAll(_doubleQuotes, '').trim();
  song = song.replaceFirstMapped(_quoted, (m) => m.group(1)!).trim();
  song = _withoutOriginalName(song);
  return (
    artist: artist,
    title: song.isEmpty ? title : song,
    fromChannel: fromChannel,
    hashtags: hashtags,
  );
}

// "┃" / "｜" glued to the text are pipes too ("SILHOUETTE (シルエット)┃Cover by Raon Lee").
final _pipeSuffix = RegExp(r'(?:\s+\||\s*[┃｜]).*$');
final _pipe = RegExp(r'\s+\|\s+|\s*[┃｜]\s*');
final _year = RegExp(r'\b(?:19|20)\d{2}\b');

/// A word joining two artists' names at a title's start ([channelVideoReadings]).
final _artistJoiner = RegExp(
  r'^(?:i|x|&|\+|and|oraz|feat\.?|ft\.?)$',
  caseSensitive: false,
);

// "((Videoclip))": a bracket doubled — the brackets' rules see one.
final _doubledBracket = RegExp(r'\(\(([^()]*)\)\)');
// "18.White House Records & Fisz -- …": a compilation's track number.
final _trackNumber = RegExp(r'^\s*\d{1,3}\.\s*(?=\p{L})', unicode: true);
// "┃Cover by Raon Lee", "(Cover by X)", "- cover by X" at the end: who performs it.
final _coverBy = RegExp(
  r'\s*(?:[|┃｜]|\s[-–—]\s)?\s*[(\[]?\s*cover(?:ed)?\s+by\s+([^|┃｜()\[\]]+?)\s*[)\]]?\s*$',
  caseSensitive: false,
);
// A channel that is a label's: "White House Records".
final _labelChannel = RegExp(
  r'\b(?:records|recordings|label|nagrania|music|productions?|entertainment)$',
  caseSensitive: false,
);
// Players credited after the title: ", gitara Paweł Smakulski".
final _playerCredit = RegExp(
  r'\s*,\s*(?:gitar[ay]|bas|perkusja|klawisze|skrzypce|saksofon|trąbka|cuty|scratche?|'
  r'wokal|chórki|realizacja|mix|mastering)\b.*$',
  caseSensitive: false,
);
// A guest at the end: "Brzmienie gość Sarsa", "Przerywamy program - feat. O.S.T.R. & Hades".
final _guestCredit = RegExp(
  r'(?:\s+gość\s+|\s+[-–—]\s+(?:feat\.?|ft\.?|featuring)\s+)(.+)$',
  caseSensitive: false,
);
// "General Woo U mom zivotu Official": the word alone at the end.
final _trailingOfficial = RegExp(r'(?<=\S)\s+official$', caseSensitive: false);
// "(Bob Dylan's 'Man Gave Names to All the Animals')": the song this one is a version of.
final _originalName = RegExp(
  '\\s*[(\\[][^()\\[\\]]+?[\'’]s\\s+[\'‘’"“”«][^()\\[\\]]+[\'‘’"“”»]\\s*[)\\]]\\s*\$',
);
final _latinLetter = RegExp(r'[A-Za-z]');

/// [song] without a trailing bracket that names it otherwise: the song it's a version of, or
/// the title in another alphabet after a Latin one ("SILHOUETTE (シルエット)").
String _withoutOriginalName(String song) {
  final named = _originalName.firstMatch(song);
  if (named != null && named.start > 0) {
    return song.substring(0, named.start).trim();
  }
  final bracket = _trailingBracket.firstMatch(song);
  if (bracket == null || bracket.start == 0) return song;
  final inside = bracket.group(1)!;
  final before = song.substring(0, bracket.start);
  if (hasNonLatinLetters(inside) &&
      !_latinLetter.hasMatch(inside) &&
      _latinLetter.hasMatch(before) &&
      !hasNonLatinLetters(before)) {
    return before.trim();
  }
  return song;
}

/// "The Cure | Talk Talk | Foghorn - muzyka na jesień": artists between pipes, the first one an
/// artist music.db knows and the last one followed by the title — as "A, B, C - title";
/// `null` for any other title.
String? _pipedArtists(String title, String? Function(String name) artistNamed) {
  final parts = title.split(_pipe).map((p) => p.trim()).toList();
  if (parts.length < 2 || parts.any((p) => p.isEmpty)) return null;
  final last = _splitSpaced(parts.last);
  if (last == null || artistNamed(parts.first) == null) return null;
  return '${[...parts.take(parts.length - 1), last.$1].join(', ')} - ${last.$2}';
}

/// "White House Records & Fisz -- Na sznurowadle - KODEX": artist and title around " -- ",
/// the title up to its next " - " (a compilation's name after it); `null` without " -- ".
(String, String)? _splitDoubleDash(String title) {
  final at = _outsideBrackets(title, ' -- ');
  if (at <= 0) return null;
  final artist = title.substring(0, at).trim();
  var song = title.substring(at + 4).trim();
  final rest = _splitSpaced(song);
  if (rest != null) song = rest.$1;
  return artist.isEmpty || song.isEmpty ? null : (artist, song);
}

/// [artist] without a label's channel joined to it ("White House Records & Fisz" by White House
/// Records is Fisz): the label put its own name in front of the artist's.
String _withoutLabel(String artist, String channel) {
  final name = _cleanChannel(channel);
  if (!_labelChannel.hasMatch(name)) return artist;
  final key = normalizeForSearch(name);
  final parts = artistCreditParts(artist);
  if (parts == null) return artist;
  final rest = [
    for (final part in parts)
      if (normalizeForSearch(part) != key) part,
  ];
  return rest.isEmpty || rest.length == parts.length ? artist : rest.join(', ');
}

/// "Paramore: crushcrushcrush" by Paramore, "dylan.pl: Adam dał imiona zwierzętom" by
/// dylan.pl: "Artist: Title" when the part before the colon is the channel's name or an artist
/// music.db knows; `null` otherwise.
(String, String)? _splitColon(
  String title,
  String channel,
  String? Function(String name)? artistNamed,
) {
  final at = _outsideBrackets(title, ': ');
  if (at <= 0) return null;
  final artist = title.substring(0, at).trim();
  final song = title.substring(at + 2).trim();
  if (artist.isEmpty || song.isEmpty) return null;
  final name = normalizeForSearch(_cleanChannel(channel)).replaceAll(' ', '');
  if (name.isNotEmpty &&
      normalizeForSearch(artist).replaceAll(' ', '') == name) {
    return (artist, song);
  }
  return artistNamed?.call(artist) == null ? null : (artist, song);
}

const _openingBrackets = '([【（［';
const _closingBrackets = ')]】）］';

/// Where [separator] first stands outside any bracket in [text], -1 when it doesn't.
int _outsideBrackets(String text, String separator) {
  var depth = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (_openingBrackets.contains(c)) {
      depth++;
    } else if (_closingBrackets.contains(c)) {
      if (depth > 0) depth--;
    } else if (depth == 0 && text.startsWith(separator, i)) {
      return i;
    }
  }
  return -1;
}

/// How many brackets are open at [index] of [text].
int _depthAt(String text, int index) {
  var depth = 0;
  for (var i = 0; i < index; i++) {
    if (_openingBrackets.contains(text[i])) depth++;
    if (_closingBrackets.contains(text[i]) && depth > 0) depth--;
  }
  return depth;
}

// A producer's credit: "prod. Sergiusz", "(prod. by X)", "- prod. DJ Eprom", "produced by X";
// "prod" a whole word, so "Prodigy" stays.
final _bracketedProducer = RegExp(
  r'\s*[(\[]\s*(?:prod\b\.?|produced\s+by\b)[^()\[\]]*[)\]]',
  caseSensitive: false,
);
final _trailingProducer = RegExp(
  r'(?:\s+[-–—]\s+|\s*,\s*|\s+)(?:prod\b\.?|produced\s+by\b)\s*\S.*$',
  caseSensitive: false,
);

/// [title] without its producer's credits, bracketed anywhere (MusicDatabase's
/// `strip_producer_credit()`) or unbracketed at its end, with whatever follows ("Brzmienie,
/// prod. Sondr duet, gitara …" — unbracketed is the phone's own); a title that is nothing but
/// one stays.
String withoutProducerCredits(String title) {
  final cut = title
      .replaceAll(_bracketedProducer, ' ')
      .replaceFirst(_trailingProducer, '')
      .replaceAll(_spaces, ' ')
      .trim();
  return cut.isEmpty ? title : cut;
}

/// Phrases of [_junkPhrases] that only say which upload it is, not which edit: matching cuts
/// these, while "(Radio Edit)" or "(Original Mix)" still keep a title apart.
final _matchingJunkPhrases = {
  for (final phrase in _junkPhrases)
    if (!RegExp(r'\b(?:edit|mix|version|explicit)\b').hasMatch(phrase)) phrase,
  'original',
};
// "(Version II)", "(Video Version 2)": which music video, the same recording.
final _videoVersion = RegExp(
  r'^(?:video\s+|music\s+video\s+)?version\s+(?:[ivx]+|\d+)$',
  caseSensitive: false,
);
// Junk words a stored title may still end with, only cut for matching ("Bloom lyrics"):
// MusicDatabase never cuts a bare "lyrics" from a title, which a real one may end with.
final _matchingJunkSuffix = RegExp(
  r'\s*\b(?:lyrics|lyric|official|original)$',
  caseSensitive: false,
);
final _guestWord = RegExp(r'\s+gość\s+', caseSensitive: false);

/// The titles [title] (a playlist track's, as it was stored) may name a song by, in the order
/// to try them: itself, without [stripTrailingJunkSuffix]'s junk, and without whatever else
/// only describes the upload — junk brackets ([_junkAnywhere], [_junkPhrases] but the edits,
/// a year, "(Original)", "(Version II)"; a doubled "((Videoclip))" too), a producer's credit
/// ([withoutProducerCredits]) and a trailing "lyrics" / "official". Version markers stay:
/// "(Live)" still names only a live version. A guest's "gość X" reads as "feat. X". For
/// matching only (`SongCatalog.findByName`): the stored title isn't changed.
List<String> titlesToMatch(String title) {
  var clean = title
      .replaceAllMapped(_doubledBracket, (m) => '(${m.group(1)!})')
      .replaceAll(_guestWord, ' feat. ');
  clean = withoutProducerCredits(clean)
      .replaceAllMapped(
        _anyBracket,
        (m) => m.start > 0 && _isMatchingJunk(m.group(1)!) ? ' ' : m.group(0)!,
      )
      .replaceAll(_spaces, ' ')
      .trim();
  while (true) {
    var next = stripTrailingJunkSuffix(clean);
    final cut = next
        .replaceFirst(_matchingJunkSuffix, '')
        .trim()
        .replaceFirst(_leftoverSeparator, '')
        .trim();
    if (cut.isNotEmpty) next = cut;
    if (next == clean) break;
    clean = next;
  }
  return {
    title,
    stripTrailingJunkSuffix(title),
    if (clean.isNotEmpty) clean,
  }.toList();
}

bool _isMatchingJunk(String content) {
  final inside = content.trim();
  if (_versionMarker.hasMatch(inside)) return false;
  return _junkAnywhere.hasMatch(inside) ||
      _junkSuffixWords.hasMatch(inside) ||
      _matchingJunkPhrases.contains(inside.toLowerCase()) ||
      _videoVersion.hasMatch(inside);
}

final _leadingBracket = RegExp(r'^[(\[【（［][^()\[\]【】（）［］]*[)\]】）］]\s*');

/// Artist and song of an event's video, "`<event with its year> | <artist> | <song>`", the last
/// part the channel's own name ("FRYDERYKI 2018 | Daria Zawiałow & Krzysztof Zalewski |
/// Malinowy chruśniak + Polsko | Gala Fryderyk"), where [_pipeSuffix] alone would leave only the
/// event. `null` for any other title: with a " - ", or not exactly those three parts. MusicDatabase's
/// `split_event_pipes()` (`src/utils/common/sanitize/text.py`) reads it the same way, but with no
/// channel to compare it drops any fourth part.
(String, String)? _splitEventPipes(String title, String channel) {
  if (_splitSpaced(title) != null) return null;
  final parts = title.split(_pipe).map((p) => p.trim()).toList();
  final name = normalizeForSearch(_cleanChannel(channel)).replaceAll(' ', '');
  if (parts.length == 4 &&
      name.isNotEmpty &&
      normalizeForSearch(parts.last).replaceAll(' ', '') == name) {
    parts.removeLast();
  }
  if (parts.length != 3 ||
      parts.any((p) => p.isEmpty) ||
      !_year.hasMatch(parts.first)) {
    return null;
  }
  return (parts[1], parts[2]);
}

final _hashtag = RegExp(r'#\S+');
final _spaces = RegExp(r'\s+');
final _anyBracket = RegExp(r'[\(\[【]([^()\[\]【】]*)[\)\]】]');
final _trailingBracket = RegExp(r'\s*[\(\[【]([^()\[\]【】]*)[\)\]】]\s*$');
final _doubleQuotes = RegExp(r'["“”„‟『』]');
final _quoted = RegExp(r"^(?:''|[‘’'«»])(.+?)(?:''|[‘’'«»])$");
final _gluedDash = RegExp(r'(?<=\S)[-–—]\s+');

/// A bracket with one of these words anywhere in the title is junk (MusicDatabase's
/// YOUTUBE_TITLE_JUNK_MARKER_WORDS_ANYWHERE).
final _junkAnywhere = RegExp(
  r'\b(animation|official|lyrics|lyric|visualiser|visualizer|video|clip|officiel|'
  r'oryginał|subtitles|4k|remaster|remastered|oficial|teledysk|tekst)\b',
  caseSensitive: false,
);

/// The trailing bracket is junk when its whole content is one of these
/// (YOUTUBE_TITLE_JUNK_PHRASES) …
const _junkPhrases = {
  'official video',
  'official audio',
  'official music video',
  'official lyric video',
  'lyric video',
  'lyrics',
  'hd',
  'hq',
  'videoclip',
  'musicvideo',
  'video clip',
  'original radio edit',
  'radio edit',
  'radio version',
  'album version',
  'original mix',
  'explicit',
  'clean version',
  'edit',
  'full song',
  'opening theme',
  'ending theme',
  'opening song',
  'ending song',
};

/// … or it contains one of these words, or a year (YOUTUBE_TITLE_JUNK_MARKER_WORDS).
final _junkSuffixWords = RegExp(
  r'\b(soundtrack|audio|from|video|\d{4})\b',
  caseSensitive: false,
);

/// A bracket naming a version of the song is never junk, whatever else it says: "(Live @ Odra,
/// Wrocław / ZORZA 2025)", "(Official Acoustic Live Video)" (VERSION_MARKER_RE).
final _versionMarker = RegExp(
  r'\b(live|cover|remix|acoustic|extended|club edit|unplugged|demo|instrumental)\b',
  caseSensitive: false,
);

/// Phrases cut from the very end of a title, unbracketed: MusicDatabase's
/// `TITLE_JUNK_SUFFIXES` (`src/config/constants.py`).
const _titleJunkSuffixes = [
  'official music video',
  'official lyric video',
  'official video',
  'official audio',
  'music video',
  'lyric video',
  'video clip',
  'videoclip',
  'musicvideo',
  'dance performance video',
  'performance video',
  'm/v',
  'full song',
  // An anime's or a game's theme named by its place in the show: "Cowboy Bebop - The Real
  // Folk Blues ending theme".
  'opening theme',
  'ending theme',
  'opening song',
  'ending song',
  'oficjalny odsłuch',
  'hd',
  'hq',
  '4k',
];

final _titleJunkSuffix = RegExp(
  '\\s*\\b(?:${_titleJunkSuffixes.map(RegExp.escape).join('|')})\\s*\$',
  caseSensitive: false,
);
final _leftoverSeparator = RegExp(r'\s*[-–—:|]+$');

/// [title] without the junk phrases stacked at its end ("Song Music Video Official Audio") and
/// the separator one leaves dangling ("Secret Youth - Music Video"); a title that is nothing but
/// such a phrase ("Ending Theme") stays — a port of MusicDatabase's
/// `strip_trailing_junk_suffix()` (`src/utils/common/sanitize/text.py`).
String stripTrailingJunkSuffix(String title) {
  var result = title.trim();
  while (true) {
    final cut = result.replaceFirst(_titleJunkSuffix, '').trim();
    final left = cut.replaceFirst(_leftoverSeparator, '');
    if (cut == result || left.isEmpty) return result;
    result = left;
  }
}

String _stripJunkSuffix(String title) {
  var result = title.trim();
  while (true) {
    final match = _trailingBracket.firstMatch(result);
    if (match == null) return result;
    final content = match.group(1)!.trim();
    if (_versionMarker.hasMatch(content) ||
        (!_junkPhrases.contains(content.toLowerCase()) &&
            !_junkSuffixWords.hasMatch(content))) {
      return result;
    }
    result = result.substring(0, match.start).trim();
  }
}

(String, String)? _splitSpaced(String title) {
  for (final separator in [' - ', ' – ', ' — ']) {
    final at = _outsideBrackets(title, separator);
    if (at > 0) {
      final artist = title.substring(0, at).trim();
      final song = title.substring(at + separator.length).trim();
      if (artist.isNotEmpty && song.isNotEmpty) return (artist, song);
    }
  }
  return null;
}

/// "Renata Przemyk- Aniolek": a dash right after the artist, a space after it.
(String, String)? _splitGlued(String title) {
  final at = _gluedDash
      .allMatches(title)
      .where((m) => _depthAt(title, m.start) == 0)
      .firstOrNull;
  if (at == null) return null;
  final artist = title.substring(0, at.start).trim();
  final song = title.substring(at.end).trim();
  return artist.isEmpty || song.isEmpty ? null : (artist, song);
}

/// Words a "`<song> - <junk>`" title's right part is made of (lite counterpart of the
/// junk-only-title check of MusicDatabase's song request recovery).
final _junkOnlyWords = RegExp(
  r'\b(official|music|lyric|lyrics|video|videoclip|clip|audio|visualiser|visualizer|'
  r'animation|animated|hd|hq|4k|teledysk|tekst|oficial|officiel)\b',
  caseSensitive: false,
);

/// [right] holds nothing but junk words once brackets are dropped ("Lyric Video (English /
/// French)"). Not when [left] is the channel's own name: then it is the artist ("India.Arie -
/// Video" by India.Arie), nor without a channel to take the artist from.
bool _isJunkOnly(String right, String left, String channel) {
  final words = right.replaceAll(_anyBracket, ' ');
  if (normalizeForSearch(words).isEmpty ||
      normalizeForSearch(words.replaceAll(_junkOnlyWords, ' ')).isNotEmpty) {
    return false;
  }
  final name = normalizeForSearch(_cleanChannel(channel)).replaceAll(' ', '');
  return name.isNotEmpty &&
      normalizeForSearch(left).replaceAll(' ', '') != name;
}

/// "DawidPodsiadloVEVO" → "DawidPodsiadlo", "Kamp! Official" → "Kamp!".
String _cleanChannel(String channel) => channel
    .replaceAll(RegExp(r'\s*(VEVO|Official)$', caseSensitive: false), '')
    .trim();

/// `SIAMÉS "Summer Nights"` from channel "SIAMES": the artist repeated at the start of the
/// title, with a bracket right after it — the artist's logo ("alt-J (∆) Breezeblocks").
String _stripArtist(String song, String artist) {
  if (artist.isEmpty) return song;
  final lowerSong = song.toLowerCase();
  final lowerArtist = artist.toLowerCase();
  if (lowerSong.startsWith('$lowerArtist ') && song.length > artist.length) {
    final rest = song.substring(artist.length).trim();
    final bare = rest.replaceFirst(_leadingBracket, '').trim();
    return bare.isEmpty ? rest : bare;
  }
  return song;
}
