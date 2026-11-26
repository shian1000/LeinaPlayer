import 'dart:math';

import 'text_normalizer.dart';
import 'version_names.dart';
import 'youtube_video.dart';

/// One of a song's artists: the name and its other names (MusicDatabase's comma-separated
/// `artists.synonyms`, e.g. a channel name).
class MatchArtist {
  MatchArtist(this.name, [String? synonyms])
    : names = [
        name,
        for (final s in (synonyms ?? '').split(','))
          if (s.trim().isNotEmpty) s.trim(),
      ];

  final String name;

  /// [name] first, then the synonyms.
  final List<String> names;
}

/// The song a YouTube video is looked for.
class MatchTarget {
  MatchTarget({
    required this.title,
    required this.mainArtists,
    this.featArtists = const [],
    this.fullAlbum = false,
    this.coverOf,
    this.version,
  });

  final String title;
  final List<MatchArtist> mainArtists;
  final List<MatchArtist> featArtists;

  /// A whole album in one recording (`SongKind.fullAlbum`): only a long "full album" video will
  /// do, never one of its songs.
  final bool fullAlbum;

  /// The name a cover's credit gives (the covered artist, else the covered song).
  final String? coverOf;

  /// A version's marker ("Live", "Cid Rim Remix"; `songs.version_kind`), never part of [title].
  final String? version;

  /// What to type into YouTube's search: main artists and the title, no guests (extra words make
  /// YouTube's results worse, not better) — "full album" added for a [fullAlbum], a version's
  /// marker, the covered artist and "cover" for a cover: either would otherwise find the original.
  String get query => [
    ...mainArtists.map((a) => a.name),
    title,
    ?version,
    if (fullAlbum) 'full album',
    ?coverOf,
    if (coverOf != null) 'cover',
  ].join(' ').trim();
}

/// A candidate with its score; [rejected] says why it can't be the song at all.
class ScoredVideo {
  const ScoredVideo(this.video, this.score, {this.rejected});

  final YouTubeVideo video;
  final double score;
  final String? rejected;

  bool get accepted => rejected == null;
}

/// Picks the YouTube video that is most likely the plain studio recording of [target], or `null`
/// when no candidate is convincing — better nothing than a cover or a live recording.
///
/// A deliberately simplified ("lite") version of MusicDatabase's `score_result()`
/// (`src/utils/youtube/manage_youtube_playlists.py`, notes in its
/// `docs/agent-notes/youtube-search-matching.md`); see ADR 0003. The phone has less to go on
/// (no yt-dlp tags or `track` metadata), so this is not a port and is not kept in sync.
/// Measured against MusicDatabase's own picks with `tool/youtube_match_benchmark.dart`.
YouTubeVideo? pickYouTubeVideo(
  MatchTarget target,
  List<YouTubeVideo> candidates,
) {
  final scored = [
    for (final s in scoreYouTubeVideos(target, candidates))
      if (s.accepted) s,
  ];
  if (scored.isEmpty) return null;
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0
        ? byScore
        : (b.video.viewCount ?? 0).compareTo(a.video.viewCount ?? 0);
  });
  return scored.first.video;
}

/// Every candidate scored, in the input order (for [pickYouTubeVideo] and the benchmark).
List<ScoredVideo> scoreYouTubeVideos(
  MatchTarget target,
  List<YouTubeVideo> candidates,
) {
  final song = _Song(target);
  return [for (final video in candidates) _score(song, video)];
}

/// The target, normalized once.
class _Song {
  _Song(MatchTarget target)
    // A version's marker counts as the bracketed part of its title.
    : title = _padded(
        target.version == null
            ? target.title
            : '${target.title} (${target.version})',
      ),
      core = _padded(target.title.replaceAll(_brackets, ' ')),
      marked =
          target.version != null ||
          _brackets.hasMatch(target.title.replaceAll(_sourceCredit, ' ')),
      mainArtists = [
        for (final a in target.mainArtists) [for (final n in a.names) _norm(n)],
      ],
      featArtists = [
        for (final a in target.featArtists) [for (final n in a.names) _norm(n)],
      ],
      fullAlbum = target.fullAlbum,
      isCover = target.coverOf != null;

  /// Whole title, " padded " for whole-word `contains`.
  final String title;

  /// Title without bracketed parts ("(Remix)", "[Live]"), which candidates often drop.
  final String core;

  /// Whether the title has a bracketed part that tells a version apart — not just where the song
  /// comes from.
  final bool marked;

  final List<List<String>> mainArtists;
  final List<List<String>> featArtists;
  final bool fullAlbum;
  final bool isCover;
}

/// What MusicDatabase's hand-off asks of a full album's video: around 20 minutes or more.
const _fullAlbumMinutes = 20;

/// Words of a full album's video, not a sign of a wrong one.
const _fullAlbumWords = {'full album', 'caly album'};

final _brackets = RegExp(r'[\(\[][^\)\]]*[\)\]]');

/// Spotify's soundtrack credit, "(from Cyberpunk: Edgerunners Season 2)": every upload of the
/// song copies it, a game's or fan's video too, so matching it says nothing of the version.
final _sourceCredit = RegExp(
  r'[\(\[]\s*from\s[^\)\]]*[\)\]]',
  caseSensitive: false,
);

// "&" is dropped by normalization, so "Rock & Roll" and "Rock and Roll" only meet without "and".
String _norm(String text) =>
    normalizeForSearch(text).replaceAll(_and, '').trim();
final _and = RegExp(r'(^| )and(?= |$)');
String _padded(String text) => ' ${_norm(text)} ';
String _collapsed(String normalized) => normalized.replaceAll(' ', '');

bool _hasWord(String padded, String phrase) => padded.contains(' $phrase ');

// Keyword lists (already normalized: no diacritics, lowercase), inspired by MusicDatabase's
// NOT_THE_SONG / LQ / STRONG_LQ / VIDEO / HQ keyword lists. A keyword that is part of the
// song's own title never counts against a candidate.

/// Not a recording of the song at all.
const _notTheSong = [
  'tlumaczenie',
  'translation',
  'lyrics translation',
  'reaction',
  'react',
  'reakcja',
  'reaguje',
  'review',
  'recenzja',
  'tutorial',
  'lekcja',
  'how to play',
  'jak zagrac',
  'karaoke',
  'instrumental',
  'nightcore',
  'sped up',
  'slowed',
  '8d',
  'bass boosted',
  'teaser',
  'trailer',
  'track by track',
  'parodia',
  'parody',
  'full album',
  'caly album',
  'shorts',
  'behind the scenes',
  'making of',
  'interview',
  'wywiad',
];

/// Live recordings: essentially never the studio version.
const _live = [
  'live',
  'na zywo',
  'en vivo',
  'ao vivo',
  'en directo',
  'koncert',
  'concert',
  'woodstock',
  'pol and rock',
  'polandrock',
  'opener',
  'meskie granie',
  'jools holland',
  'unplugged',
  'session',
  'sesja',
  'tour',
  'performance',
  'festival',
  'klub',
];

/// Another arrangement of the song; a bonus instead when the song's title names it.
const _otherVersion = [
  'remix',
  'rmx',
  'edit',
  'club mix',
  'extended',
  'cover',
  'acoustic',
  'akustycznie',
  'akustyczna',
  'demo',
  'version',
  'wersja',
  'orchestra',
  'orchestral',
  'orkiestra',
  'dub',
  'mashup',
  'bootleg',
];

/// A video rather than an audio upload — a format preference, not a wrong song.
const _video = [
  'official video',
  'official music video',
  'music video',
  'video clip',
  'teledysk',
  'official mv',
  'mv',
  'lyric video',
  'lyrics video',
  'lyrics',
  'lyric',
  'tekst',
  'napisy',
  'visualizer',
  'visualiser',
];

const _official = [
  'original soundtrack',
  'original series soundtrack',
  'original motion picture soundtrack',
  'original game soundtrack',
  'official audio',
  'audio',
  'official',
  'oficjalny',
  'oficjalne',
  'remaster',
  'remastered',
  'hq',
  'hd',
];

// " - Acoustic Version" at the end, after a spaced dash.
final _dashSuffix = RegExp(r'\s[-–—]\s+([^-–—\(\)\[\]]+?)\s*$');

/// The parts of [videoTitle] that may name a version: its brackets and what follows its last
/// spaced dash.
List<String> _versionMarkers(String videoTitle) => [
  for (final m in _brackets.allMatches(videoTitle))
    m[0]!.substring(1, m[0]!.length - 1),
  if (_dashSuffix.firstMatch(videoTitle.replaceAll(_brackets, ' '))
      case final dash?)
    dash[1]!,
];

/// [padded] without the artists' names.
String _withoutArtists(String padded, List<List<String>> artists) {
  for (final names in artists) {
    for (final n in names) {
      if (n.isNotEmpty) padded = padded.replaceAll(' $n ', ' ');
    }
  }
  return padded;
}

ScoredVideo _score(_Song song, YouTubeVideo video) {
  ScoredVideo reject(String why) => ScoredVideo(video, 0, rejected: why);

  final duration = video.duration;
  if (song.fullAlbum) {
    // Without a duration a single song can't be told apart.
    if (duration == null || duration.inMinutes < _fullAlbumMinutes) {
      return reject('czas trwania');
    }
  } else if (duration != null &&
      (duration.inSeconds < 45 || duration.inMinutes >= 20)) {
    return reject('czas trwania');
  }

  final title = _padded(video.title);
  final channelNorm = _norm(video.channel);
  final isTopic = channelNorm.endsWith(' topic');
  final channel = _collapsed(
    channelNorm
        .replaceAll(RegExp(r' topic$'), '')
        .replaceAll(RegExp(r'vevo$'), ''),
  );

  for (final word in _notTheSong) {
    if (song.fullAlbum && _fullAlbumWords.contains(word)) continue;
    if (_hasWord(title, word) && !_hasWord(song.title, word)) {
      return reject('„$word”');
    }
  }

  // Title: the song's title (or its unbracketed core) as whole words of the video title.
  var score = 0.0;
  if (_hasWord(title, song.title.trim())) {
    // Matching the bracketed part too ("(Instrumental)", "(Remix X)") is the strongest sign
    // of the right version.
    score += song.marked ? 3 : 1;
  } else if (!_hasWord(title, song.core.trim())) {
    return reject('tytuł');
  }

  // Artist: some main artist (or other name) in the video title or the channel name. Topic
  // channels and many official uploads name the artist only in the channel.
  bool present(List<String> names) => names.any(
    (n) =>
        n.isNotEmpty && (_hasWord(title, n) || channel.contains(_collapsed(n))),
  );
  final mainFound = song.mainArtists.where(present).length;
  if (mainFound == 0) return reject('wykonawca');
  score += mainFound - 1;
  score += 0.5 * song.featArtists.where(present).length;
  // The artist's own channel, or a label's VEVO one (soundtracks are often uploaded there).
  if (channelNorm.endsWith('vevo') ||
      song.mainArtists.any(
        (names) => names.any((n) => n.isNotEmpty && channel == _collapsed(n)),
      )) {
    score += 1;
  }

  // Another version the song's title doesn't name: rejected when a bracket or the part after a
  // dash says so ("Nemreš Bolivit (Space Cat Remix)" by "Renman - Topic" for the plain song —
  // with the Topic bonus it tied with the original upload, and views picked the remix), else
  // it outweighs the Topic bonus. A release's marker ("Radio Edit", "Album Version") is the
  // same recording, a cover's own credit ("Acoustic Cover" for a cover) its version, and an
  // artist's name ("Dub FX") says nothing of it: a word only there costs what it used to.
  final artists = [...song.mainArtists, ...song.featArtists];
  final markers = _versionMarkers(video.title);
  bool neutral(String marker) =>
      namesRelease(marker) ||
      (song.isCover && _hasWord(_padded(marker), 'cover'));
  final named = _padded(markers.where((m) => !neutral(m)).join(' '));
  var rest = _withoutArtists(title, artists);
  for (final m in markers.where(neutral)) {
    rest = rest.replaceAll(' ${_norm(m)} ', ' ');
  }
  var otherVersion = false;
  for (final word in _otherVersion) {
    if (!_hasWord(title, word)) continue;
    if (_hasWord(song.title, word) || (song.isCover && word == 'cover')) {
      score += 2;
    } else if (_hasWord(named, word)) {
      return reject('wersja „$word”');
    } else if (_hasWord(rest, word)) {
      otherVersion = true;
      score -= 6;
    } else if (_hasWord(_withoutArtists(title, artists), word)) {
      score -= 3;
    } else {
      continue;
    }
    break;
  }
  if (isTopic && !otherVersion) score += 3;
  for (final word in _live) {
    if (_hasWord(title, word) && !_hasWord(song.title, word)) {
      score -= 3;
      break;
    }
  }
  for (final word in _video) {
    if (_hasWord(title, word) && !_hasWord(song.title, word)) {
      score -= 1;
      break;
    }
  }
  for (final word in _official) {
    if (_hasWord(title, word)) {
      score += word == 'official audio' || word == 'audio' ? 2 : 1;
      break;
    }
  }
  if (song.fullAlbum && _fullAlbumWords.any((w) => _hasWord(title, w))) {
    score += 2;
  }
  final views = video.viewCount;
  if (views != null && views > 0) score += 0.3 * log(views) / ln10;
  return ScoredVideo(video, score);
}
