// Measures the phone's "lite" YouTube matcher (lib/src/data/youtube_matcher.dart) against the
// videos MusicDatabase picked itself (songs.youtube_video_id).
//
//   dart run tool/youtube_match_benchmark.dart <music.db> [sample size] [--offline]
//
// The first run searches YouTube (youtube_explode) for a sample of songs that have a stored
// video and caches the results in build/youtube_match_benchmark/candidates.json, a few seconds
// apart so YouTube doesn't start asking whether we're a bot. Later runs reuse the cache, so the
// matcher can be tuned offline; --offline never touches the network. Plain Dart: no Flutter.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:music_database_app/src/data/youtube_matcher.dart';
import 'package:music_database_app/src/data/youtube_video.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const _delay = Duration(seconds: 4);
final _cacheFile = File('build/youtube_match_benchmark/candidates.json');

Future<void> main(List<String> args) async {
  final positional = [
    for (final a in args)
      if (!a.startsWith('--')) a,
  ];
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/youtube_match_benchmark.dart <music.db> [sample] [--offline]',
    );
    exit(64);
  }
  final sampleSize = positional.length > 1 ? int.parse(positional[1]) : 100;
  final offline = args.contains('--offline');

  sqfliteFfiInit();
  final songs = await _readLinkedSongs(positional[0]);
  // Every k-th song: spread over the whole library, same sample every run.
  final step = max(1, songs.length ~/ sampleSize);
  final sample = [
    for (var i = 0; i < songs.length && i ~/ step < sampleSize; i += step)
      songs[i],
  ];

  final cache = await _loadCache();
  final yt = YoutubeExplode();
  try {
    var fetched = 0;
    for (final song in sample) {
      if (cache.containsKey('${song.id}') || offline) continue;
      if (fetched > 0) await Future<void>.delayed(_delay);
      fetched++;
      stdout.write(
        '\rSearching ${fetched.toString().padLeft(3)}: ${song.target.query}'
        '                    ',
      );
      try {
        final results = await yt.search
            .search(song.target.query)
            .timeout(const Duration(seconds: 20));
        cache['${song.id}'] = [
          for (final v in results.take(15))
            YouTubeVideo(
              id: v.id.value,
              title: v.title,
              channel: v.author,
              duration: v.duration,
              viewCount: v.engagement.viewCount,
            ).toJson(),
        ];
        await _saveCache(cache);
      } catch (e) {
        stdout.writeln('\n  search failed: $e');
      }
    }
    if (fetched > 0) stdout.writeln();
  } finally {
    yt.close();
  }

  var same = 0, different = 0, none = 0, unreachable = 0, total = 0;
  final report = StringBuffer();
  for (final song in sample) {
    final raw = cache['${song.id}'];
    if (raw == null) continue;
    total++;
    final candidates = [
      for (final c in raw as List)
        YouTubeVideo.fromJson(c as Map<String, Object?>),
    ];
    final reachable = candidates.any((c) => c.id == song.videoId);
    if (!reachable) unreachable++;
    final pick = pickYouTubeVideo(song.target, candidates);
    if (pick?.id == song.videoId) {
      same++;
      continue;
    }
    pick == null ? none++ : different++;
    report.writeln(
      '\n${pick == null ? 'NONE' : 'DIFF'} ${song.target.query}'
      '${reachable ? '' : '  (MusicDatabase\'s video not in results)'}',
    );
    for (final s in scoreYouTubeVideos(song.target, candidates)) {
      final mark = s.video.id == song.videoId
          ? 'DB '
          : s.video.id == pick?.id
          ? 'APP'
          : '   ';
      report.writeln(
        '  $mark ${s.accepted ? s.score.toStringAsFixed(1).padLeft(5) : 'x'.padLeft(5)} '
        '${s.video.title} | ${s.video.channel}'
        '${s.accepted ? '' : '  [${s.rejected}]'}',
      );
    }
  }
  stdout.write(report);
  String pct(int n) => total == 0 ? '-' : '${(100 * n / total).round()}%';
  stdout.writeln(
    '\nSongs: $total. Same video as MusicDatabase: $same (${pct(same)}), '
    'different: $different (${pct(different)}), no match: $none (${pct(none)}). '
    'MusicDatabase\'s video not among the search results at all: $unreachable '
    '(${pct(unreachable)}).',
  );
}

typedef _LinkedSong = ({int id, String videoId, MatchTarget target});

Future<List<_LinkedSong>> _readLinkedSongs(String path) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    final rows = await db.rawQuery('''
      SELECT s.id, s.title, s.youtube_video_id, a.name, a.synonyms
      FROM songs s JOIN artists a ON a.id = s.artist_id
      WHERE s.youtube_video_id IS NOT NULL AND s.youtube_video_id NOT IN ('', 'N/A')
      ORDER BY s.id''');
    final extra = <int, List<Map<String, Object?>>>{};
    for (final row in await db.rawQuery(
      '''
        SELECT x.song_id, x.role, a.name, a.synonyms
        FROM additional_song_artists x JOIN artists a ON a.id = x.artist_id''',
    )) {
      (extra[row['song_id']! as int] ??= []).add(row);
    }
    return [
      for (final row in rows)
        (
          id: row['id']! as int,
          videoId: row['youtube_video_id']! as String,
          target: MatchTarget(
            title: row['title']! as String,
            mainArtists: [
              MatchArtist(row['name']! as String, row['synonyms'] as String?),
              for (final x in extra[row['id']] ?? const [])
                if (x['role'] == 'main')
                  MatchArtist(x['name']! as String, x['synonyms'] as String?),
            ],
            featArtists: [
              for (final x in extra[row['id']] ?? const [])
                if (x['role'] == 'feat')
                  MatchArtist(x['name']! as String, x['synonyms'] as String?),
            ],
          ),
        ),
    ];
  } finally {
    await db.close();
  }
}

Future<Map<String, Object?>> _loadCache() async => await _cacheFile.exists()
    ? (jsonDecode(await _cacheFile.readAsString()) as Map<String, Object?>)
    : <String, Object?>{};

Future<void> _saveCache(Map<String, Object?> cache) async {
  await _cacheFile.parent.create(recursive: true);
  await _cacheFile.writeAsString(jsonEncode(cache));
}
