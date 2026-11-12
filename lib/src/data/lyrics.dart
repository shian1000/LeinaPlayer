import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'combined_search.dart';
import 'server_trust.dart';
import 'track_ref.dart';

/// One line of time-synced lyrics.
typedef LyricLine = ({Duration at, String text});

/// A song's lyrics: [synced] lines when known, else [plain] text.
class Lyrics {
  const Lyrics({
    this.plain,
    this.synced = const [],
    this.instrumental = false,
    this.source = 'LRCLIB',
  });

  final String? plain;
  final List<LyricLine> synced;
  final bool instrumental;

  /// Where the text came from, as the card credits it ("MusicDatabase (Genius)").
  final String source;

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

/// Lyrics from MusicDatabase's server (`GET /lyrics/<songs.id>`, its hand-off
/// `lyrics-for-musicdatabaseapp.md`) for a music.db song, else from LRCLIB (lrclib.net — free,
/// no key), which the phone looks up itself where MusicDatabase has none (a gap filled on the
/// phone, ADR 0003; MusicDatabase's counterpart is its "Lyrics" enrichment). Kept only in
/// memory for this run, so nothing new is stored on the phone.
class LyricsFinder {
  LyricsFinder({
    Future<Object?> Function(Uri uri)? getJson,
    Future<Object?> Function(Uri uri)? getServerJson,
  }) : _getJson = getJson ?? _httpGetJson,
       _getServerJson = getServerJson ?? _serverGetJson;

  static final instance = LyricsFinder();

  final Future<Object?> Function(Uri uri) _getJson;
  final Future<Object?> Function(Uri uri) _getServerJson;
  final _found = <String, Future<Lyrics?>>{};

  /// MusicDatabase's server first, on the addresses [servers] gives (none: LRCLIB only).
  /// `null`: neither knows the song. Throws when LRCLIB can't be reached.
  Future<Lyrics?> find(SearchHit hit, {Future<List<Uri>> Function()? servers}) {
    final key = TrackRef.of(hit).key;
    final pending = _found[key] ??= _look(hit, servers);
    // A failure (no connection) is tried again next time.
    pending.catchError((Object _) {
      _found.remove(key);
      return null;
    });
    return pending;
  }

  Future<Lyrics?> _look(
    SearchHit hit,
    Future<List<Uri>> Function()? servers,
  ) async {
    final song = hit.mainSong;
    // MusicDatabase never looks these up: there are no words to find.
    if (song?.language == 'Instrumental') {
      return const Lyrics(instrumental: true, source: 'MusicDatabase');
    }
    if (song != null && servers != null) {
      if (await _fromServer(song.id, servers) case final lyrics?) {
        return lyrics;
      }
    }
    return _fromLrclib(hit);
  }

  /// `null` sends the song to LRCLIB: the server has no lyrics for it (404) or can't answer.
  Future<Lyrics?> _fromServer(
    int songId,
    Future<List<Uri>> Function() servers,
  ) async {
    final List<Uri> addresses;
    try {
      addresses = await servers();
    } catch (e) {
      debugPrint('Server addresses for lyrics failed: $e');
      return null;
    }
    for (final base in addresses) {
      final Object? json;
      try {
        json = await _getServerJson(base.resolve('lyrics/$songId'));
      } catch (e) {
        debugPrint('Lyrics from the server failed: $e');
        continue;
      }
      if (json is! Map) return null;
      final lyrics = Lyrics(
        plain: json['plain'] as String?,
        synced: parseLrc(json['synced'] as String? ?? ''),
        instrumental: json['instrumental'] == true,
        source: _serverCredit(json['source']),
      );
      // Plain text alone is often on purpose (the synced lines didn't fit the song's
      // video): LRCLIB's synced lines aren't asked for instead.
      return lyrics.isEmpty ? null : lyrics;
    }
    return null;
  }

  static String _serverCredit(Object? source) => switch (source) {
    'lrclib_fetcher' => 'MusicDatabase (LRCLIB)',
    'library_tags_fetcher' => 'MusicDatabase (tagi pliku)',
    'genius_lyrics_fetcher' => 'MusicDatabase (Genius)',
    'musixmatch_fetcher' => 'MusicDatabase (Musixmatch)',
    'lyricstranslate_fetcher' => 'MusicDatabase (LyricsTranslate)',
    'tekstowo_fetcher' => 'MusicDatabase (Tekstowo)',
    'fajnanuta_fetcher' => 'MusicDatabase (FajnaNuta)',
    _ => 'MusicDatabase',
  };

  Future<Lyrics?> _fromLrclib(SearchHit hit) async {
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
Future<Object?> _httpGetJson(Uri uri) => _getJsonWith(
  HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..userAgent = 'LeinaPlayer (private music app)',
  uri,
  const Duration(seconds: 15),
);

/// `null` for 404 (no lyrics in MusicDatabase); short timeouts, as LRCLIB is still to be asked.
Future<Object?> _serverGetJson(Uri uri) => _getJsonWith(
  ServerTrust.instance.client()..connectionTimeout = const Duration(seconds: 3),
  uri,
  const Duration(seconds: 8),
);

Future<Object?> _getJsonWith(
  HttpClient client,
  Uri uri,
  Duration timeout,
) async {
  try {
    final response = await (await client.getUrl(uri)).close().timeout(timeout);
    if (response.statusCode == HttpStatus.notFound) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return jsonDecode(await response.transform(utf8.decoder).join());
  } finally {
    client.close(force: true);
  }
}
