import 'dart:convert';
import 'dart:io';

import 'combined_search.dart';
import 'track_ref.dart';

/// One line of time-synced lyrics.
typedef LyricLine = ({Duration at, String text});

/// A song's lyrics: [synced] lines when known, else [plain] text.
class Lyrics {
  const Lyrics({this.plain, this.synced = const [], this.instrumental = false});

  final String? plain;
  final List<LyricLine> synced;
  final bool instrumental;

  bool get isEmpty => !instrumental && synced.isEmpty && (plain ?? '').isEmpty;
}

/// Parses LRC ("[01:23.45] text") into lines in time order; lines without a time are left out.
List<LyricLine> parseLrc(String lrc) {
  final stamp = RegExp(r'\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  final lines = <LyricLine>[];
  for (final raw in const LineSplitter().convert(lrc)) {
    final stamps = stamp.allMatches(raw).toList();
    if (stamps.isEmpty) continue;
    final text = raw.substring(stamps.last.end).trim();
    for (final m in stamps) {
      final fraction = m.group(3) ?? '0';
      lines.add((
        at: Duration(
          minutes: int.parse(m.group(1)!),
          seconds: int.parse(m.group(2)!),
          milliseconds: int.parse(fraction.padRight(3, '0').substring(0, 3)),
        ),
        text: text,
      ));
    }
  }
  return lines..sort((a, b) => a.at.compareTo(b.at));
}

/// Lyrics from LRCLIB (lrclib.net — free, no key), which the phone looks up itself while
/// MusicDatabase has none (a gap filled on the phone, ADR 0003; MusicDatabase's counterpart
/// would be an enrichment like its Genius one). Kept only in memory for this run, so nothing
/// new is stored on the phone.
class LyricsFinder {
  LyricsFinder({Future<Object?> Function(Uri uri)? getJson})
    : _getJson = getJson ?? _httpGetJson;

  static final instance = LyricsFinder();

  final Future<Object?> Function(Uri uri) _getJson;
  final _found = <String, Future<Lyrics?>>{};

  /// `null`: LRCLIB doesn't know the song. Throws when it can't be reached.
  Future<Lyrics?> find(SearchHit hit) {
    final key = TrackRef.of(hit).key;
    final pending = _found[key] ??= _look(hit);
    // A failure (no connection) is tried again next time.
    pending.catchError((Object _) {
      _found.remove(key);
      return null;
    });
    return pending;
  }

  Future<Lyrics?> _look(SearchHit hit) async {
    final query = {
      'track_name': hit.title,
      'artist_name': hit.artistLabel,
      if (hit.album case final album? when album.isNotEmpty)
        'album_name': album,
    };
    final exact = await _getJson(Uri.https('lrclib.net', '/api/get', query));
    if (exact is Map) return _lyricsOf(exact);
    final found = await _getJson(
      Uri.https('lrclib.net', '/api/search', {
        'track_name': hit.title,
        'artist_name': hit.artistLabel,
      }),
    );
    if (found is List && found.isNotEmpty && found.first is Map) {
      return _lyricsOf(found.first as Map);
    }
    return null;
  }

  static Lyrics? _lyricsOf(Map<Object?, Object?> json) {
    final lyrics = Lyrics(
      plain: json['plainLyrics'] as String?,
      synced: parseLrc(json['syncedLyrics'] as String? ?? ''),
      instrumental: json['instrumental'] == true,
    );
    return lyrics.isEmpty ? null : lyrics;
  }
}

/// `null` for 404 (LRCLIB's "not found").
Future<Object?> _httpGetJson(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..userAgent = 'LeinaRadio (private music app)';
  try {
    final response = await (await client.getUrl(uri))
        .close()
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return jsonDecode(await response.transform(utf8.decoder).join());
  } finally {
    client.close(force: true);
  }
}
