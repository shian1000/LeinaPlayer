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
/// the artist from a "`<Artist> - Topic`" channel, else splits "Artist - Title", else uses the
/// channel name. "Title - Lyric Video (English / French)" — junk only after the separator — is
/// the left part by the channel. Real version markers (Remix, Live, feat., …) are kept, with the
/// rest of their bracket: "(Live @ Odra, Wrocław / ZORZA 2025)" isn't junk for its year.
/// An event's "`<event 2018> | <artist> | <song> | <channel>`" reads as that artist and song.
/// "Artist- Title", the dash glued to the artist, splits too, and a title in quotes
/// (`''Aniolek''`, „…”) loses them.
({String artist, String title}) parseYouTubeTrack(
  String videoTitle,
  String channel,
) {
  final read = _readYouTubeTrack(videoTitle, channel);
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
  final read = _readYouTubeTrack(videoTitle, channel);
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

({String artist, String title, bool fromChannel}) _readYouTubeTrack(
  String videoTitle,
  String channel,
) {
  var title = videoTitle;
  if (_splitEventPipes(title, channel) case (final artist, final song)) {
    title = '$artist - $song';
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
  } else {
    final split = _splitSpaced(title) ?? _splitGlued(title);
    fromChannel = split == null || _isJunkOnly(split.$2, split.$1, channel);
    if (split != null && fromChannel) {
      artist = _cleanChannel(channel);
      song = split.$1;
    } else {
      artist = split?.$1 ?? _cleanChannel(channel);
      song = split?.$2 ?? title;
    }
  }
  song = _stripArtist(song, artist);
  song = stripTrailingJunkSuffix(_stripJunkSuffix(song))
      .replaceAll(_doubleQuotes, '')
      .trim();
  song = song.replaceFirstMapped(_quoted, (m) => m.group(1)!).trim();
  return (
    artist: artist,
    title: song.isEmpty ? title : song,
    fromChannel: fromChannel,
  );
}

final _pipeSuffix = RegExp(r'\s+\|.*$');
final _pipe = RegExp(r'\s+\|\s+');
final _year = RegExp(r'\b(?:19|20)\d{2}\b');

/// A word joining two artists' names at a title's start ([channelVideoReadings]).
final _artistJoiner = RegExp(r'^(?:i|x|&|\+|and|oraz|feat\.?|ft\.?)$', caseSensitive: false);

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
    final at = title.indexOf(separator);
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
  final at = _gluedDash.firstMatch(title);
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

/// `SIAMÉS "Summer Nights"` from channel "SIAMES": the artist repeated at the start of the title.
String _stripArtist(String song, String artist) {
  if (artist.isEmpty) return song;
  final lowerSong = song.toLowerCase();
  final lowerArtist = artist.toLowerCase();
  if (lowerSong.startsWith('$lowerArtist ') && song.length > artist.length) {
    return song.substring(artist.length).trim();
  }
  return song;
}
