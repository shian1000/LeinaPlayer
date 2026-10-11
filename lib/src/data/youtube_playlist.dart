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
/// channel name. Real version markers (Remix, Live, feat., …) are kept.
({String artist, String title}) parseYouTubeTrack(
  String videoTitle,
  String channel,
) {
  var title = videoTitle.replaceAll(_pipeSuffix, '');
  title = title.replaceAllMapped(
    _anyBracket,
    (m) => _junkAnywhere.hasMatch(m.group(1)!) ? ' ' : m.group(0)!,
  );
  title = title.replaceAll(_hashtag, ' ').replaceAll(_spaces, ' ').trim();

  final topic = RegExp(r'\s*-\s*topic$', caseSensitive: false);
  String artist;
  String song;
  if (topic.hasMatch(channel)) {
    artist = channel.replaceAll(topic, '').trim();
    song = title;
  } else {
    final split = _splitSpaced(title);
    artist = split?.$1 ?? _cleanChannel(channel);
    song = split?.$2 ?? title;
  }
  song = _stripArtist(song, artist);
  song = _stripJunkSuffix(song).replaceAll(_doubleQuotes, '').trim();
  return (artist: artist, title: song.isEmpty ? title : song);
}

final _pipeSuffix = RegExp(r'\s+\|.*$');
final _hashtag = RegExp(r'#\S+');
final _spaces = RegExp(r'\s+');
final _anyBracket = RegExp(r'[\(\[【]([^()\[\]【】]*)[\)\]】]');
final _trailingBracket = RegExp(r'\s*[\(\[【]([^()\[\]【】]*)[\)\]】]\s*$');
final _doubleQuotes = RegExp(r'["“”„‟『』]');

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

String _stripJunkSuffix(String title) {
  var result = title.trim();
  while (true) {
    final match = _trailingBracket.firstMatch(result);
    if (match == null) return result;
    final content = match.group(1)!.trim();
    if (!_junkPhrases.contains(content.toLowerCase()) &&
        !_junkSuffixWords.hasMatch(content)) {
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
