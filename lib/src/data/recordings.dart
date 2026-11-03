import 'dart:io';
import 'dart:math';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:sqflite/sqflite.dart';

/// A recording's loudness for "Wyrównywanie głośności": integrated loudness in LUFS and the
/// peak in dBFS. Kept per recording — a phone file, a server file (`files.id`), a YouTube
/// video — never per song: each recording of a song is mastered differently.
class Loudness {
  const Loudness({required this.lufs, this.peakDb});

  final double lufs;
  final double? peakDb;

  /// What the songs are brought to, as Spotify and YouTube do.
  static const targetLufs = -14.0;

  /// A boost never lifts the song's peak above this, so the limiter (`VolumeLeveling.kt`)
  /// never has to squash it (user's choice: one steady gain for the whole song, its dynamics
  /// untouched, as Spotify's "Normal" does).
  static const peakCeilingDb = -1.0;

  /// The gain bringing this recording [strength] (0–1) of the way to [targetLufs]: a cut in
  /// full, a boost only as far as its peak allows — none when the peak isn't known.
  double gainDb(double strength) {
    final gain = strength * (targetLufs - lufs);
    if (gain <= 0) return max(gain, -15.0);
    final peak = peakDb;
    return peak == null ? 0 : min(gain, max(0.0, peakCeilingDb - peak));
  }
}

/// Where a recording's loudness came from.
enum LoudnessMethod {
  /// The file's ReplayGain (or Opus R128) tags.
  replayGain,

  /// The file's tags were read and had none; the phone may still measure it.
  none,

  /// The phone measured the file (EBU R128, `VolumeLeveling.kt`); a silent file has no `lufs`.
  analysis,

  /// Measuring failed (an unreadable file); not tried again.
  failed;

  /// Nothing more to find out about the recording's loudness.
  bool get settled => this != none;
}

/// The kinds of recordings the `recordings` table keys.
enum RecordingSource { file, server, youtube }

/// A recording in the `recordings` table.
typedef RecordingKey = (RecordingSource, String);

/// ReplayGain 2.0's reference: a track gain of G dB means −18 − G LUFS.
const _replayGainReference = -18.0;

/// Opus' R128 gains are relative to EBU R128's −23 LUFS, in 1/256 dB.
const _r128Reference = -23.0;

/// The track's loudness from its tags: ReplayGain in ID3 (TXXX), Vorbis comments (FLAC, Ogg,
/// Opus) and APE; Opus' R128_TRACK_GAIN. Not MP4's freeform atoms — the tag reader skips them.
Loudness? replayGainLoudness(Object tags) {
  final Map<String, String> fields = switch (tags) {
    Mp3Metadata() => {
      for (final e in tags.customMetadata.entries) e.key.toUpperCase(): e.value,
    },
    VorbisMetadata() => {
      ...tags.unknowns,
      if (tags.replayGainTrackGain.isNotEmpty)
        'REPLAYGAIN_TRACK_GAIN': tags.replayGainTrackGain.first,
      if (tags.replayGainTrackPeak.isNotEmpty)
        'REPLAYGAIN_TRACK_PEAK': tags.replayGainTrackPeak.first,
    },
    ApeMetadata() => {
      for (final e in tags.unknowns.entries) e.key.toUpperCase(): e.value,
    },
    _ => const {},
  };
  final peak = _number(fields['REPLAYGAIN_TRACK_PEAK']);
  final peakDb = peak == null || peak <= 0 ? null : 20 * log(peak) / ln10;
  final gain = _number(fields['REPLAYGAIN_TRACK_GAIN']);
  if (gain != null) {
    return Loudness(lufs: _replayGainReference - gain, peakDb: peakDb);
  }
  final r128 = _number(fields['R128_TRACK_GAIN']);
  if (r128 != null) {
    return Loudness(lufs: _r128Reference - r128 / 256, peakDb: peakDb);
  }
  return null;
}

/// [replayGainLoudness] of the file at [path]; `null` also when it can't be read.
Loudness? readFileLoudness(String path) {
  try {
    return replayGainLoudness(readAllMetadata(File(path), getImage: false));
  } catch (_) {
    return null;
  }
}

/// "-6.20 dB", "+1.5 dB", "0.988" → the number.
double? _number(String? text) {
  if (text == null) return null;
  final match = RegExp(r'[-+]?\d+(?:[.,]\d+)?').firstMatch(text);
  return match == null ? null : double.tryParse(match[0]!.replaceAll(',', '.'));
}

/// The `recordings` table of `local.db`: what the phone found out about each recording — its
/// loudness ("Wyrównywanie głośności") and length. Rows are made by whichever comes first (the
/// scan, a measurement, a play) and filled in column by column.
class Recordings {
  Recordings(this._database, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Future<Database> Function() _database;
  final DateTime Function() _now;

  /// A recording: a server file, else a YouTube video (also when it plays from the cache or a
  /// download), else the phone file at [path].
  static RecordingKey? keyOf({
    int? serverFileId,
    String? youtubeVideoId,
    String? path,
  }) => switch ((serverFileId, youtubeVideoId, path)) {
    (final id?, _, _) => (RecordingSource.server, '$id'),
    (_, final id?, _) => (RecordingSource.youtube, id),
    (_, _, final path?) => (RecordingSource.file, path),
    _ => null,
  };

  /// [key]'s loudness, `null` when it isn't known.
  Future<Loudness?> loudness(RecordingKey key) async {
    final rows = await (await _database()).query(
      'recordings',
      columns: ['lufs', 'peak_db'],
      where: 'source = ? AND key = ? AND lufs IS NOT NULL',
      whereArgs: [key.$1.name, key.$2],
    );
    if (rows.isEmpty) return null;
    return Loudness(
      lufs: rows.first['lufs']! as double,
      peakDb: rows.first['peak_db'] as double?,
    );
  }

  /// [key]'s length, `null` when it isn't known.
  Future<Duration?> duration(RecordingKey key) async {
    final rows = await (await _database()).query(
      'recordings',
      columns: ['duration_ms'],
      where: 'source = ? AND key = ? AND duration_ms IS NOT NULL',
      whereArgs: [key.$1.name, key.$2],
    );
    return rows.isEmpty
        ? null
        : Duration(milliseconds: rows.first['duration_ms']! as int);
  }

  /// Recordings whose loudness was settled ([LoudnessMethod.settled]) — not to be measured.
  Future<Set<RecordingKey>> settled() async => {
    for (final row in await (await _database()).query(
      'recordings',
      columns: ['source', 'key'],
      where: 'loudness_method IS NOT NULL AND loudness_method != ?',
      whereArgs: [LoudnessMethod.none.name],
    ))
      (
        RecordingSource.values.byName(row['source']! as String),
        row['key']! as String,
      ),
  };

  /// Phone files whose tags were read already, keyed by path.
  Future<Set<String>> tagsRead() async => {
    for (final row in await (await _database()).query(
      'recordings',
      columns: ['key'],
      where: 'source = ? AND loudness_method IS NOT NULL',
      whereArgs: [RecordingSource.file.name],
    ))
      row['key']! as String,
  };

  /// [key]'s loudness, found by [method].
  Future<void> saveLoudness(
    RecordingKey key,
    Loudness? loudness,
    LoudnessMethod method, {
    Duration? duration,
  }) => _put(key, {
    'lufs': loudness?.lufs,
    'peak_db': loudness?.peakDb,
    'loudness_method': method.name,
    'measured_at': _now().millisecondsSinceEpoch,
    if (duration != null) 'duration_ms': duration.inMilliseconds,
  });

  Future<void> saveDuration(RecordingKey key, Duration duration) =>
      _put(key, {'duration_ms': duration.inMilliseconds});

  /// Several phone files' tags at once (the scan).
  Future<void> saveTags(Map<String, Loudness?> byPath) async {
    final batch = (await _database()).batch();
    final now = _now().millisecondsSinceEpoch;
    for (final MapEntry(key: path, value: loudness) in byPath.entries) {
      _putIn(
        batch,
        (RecordingSource.file, path),
        {
          'lufs': loudness?.lufs,
          'peak_db': loudness?.peakDb,
          'loudness_method':
              (loudness == null
                      ? LoudnessMethod.none
                      : LoudnessMethod.replayGain)
                  .name,
          'measured_at': now,
        },
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> forget(RecordingKey key) async => (await _database()).delete(
    'recordings',
    where: 'source = ? AND key = ?',
    whereArgs: [key.$1.name, key.$2],
  );

  Future<void> _put(RecordingKey key, Map<String, Object?> values) async {
    final batch = (await _database()).batch();
    _putIn(batch, key, values);
    await batch.commit(noResult: true);
  }

  /// Sets [values] on [key]'s row, keeping its other columns. Not an UPSERT: Android 10's
  /// SQLite (3.22) doesn't have it.
  static void _putIn(
    Batch batch,
    RecordingKey key,
    Map<String, Object?> values,
  ) {
    batch
      ..update(
        'recordings',
        values,
        where: 'source = ? AND key = ?',
        whereArgs: [key.$1.name, key.$2],
      )
      ..insert('recordings', {
        'source': key.$1.name,
        'key': key.$2,
        ...values,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
