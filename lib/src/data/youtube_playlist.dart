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
/// "thericeburner" is "bo jesli tak ma byc" by Renata Przemyk), longest name first, and an
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
      readings.add((artist: artist, title: words.skip(i).join(' ')));
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
  var title = videoTitle.replaceAll(_pipeSuffix, '');
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
  song = _stripJunkSuffix(song).replaceAll(_doubleQuotes, '').trim();
  song = song.replaceFirstMapped(_quoted, (m) => m.group(1)!).trim();
  return (
    artist: artist,
    title: song.isEmpty ? title : song,
    fromChannel: fromChannel,
  );
}

final _pipeSuffix = RegExp(r'\s+\|.*$');
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
