import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/recordings.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/playback/loudness_measurer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';

/// An ID3v2.3 tag with TXXX frames, then a silent MPEG frame.
Uint8List mp3WithTxxx(Map<String, String> fields) {
  final frames = BytesBuilder();
  for (final MapEntry(:key, :value) in fields.entries) {
    final body = [0, ...latin1.encode(key), 0, ...latin1.encode(value)];
    frames
      ..add(latin1.encode('TXXX'))
      ..add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List())
      ..add([0, 0])
      ..add(body);
  }
  final tag = frames.toBytes();
  final size = tag.length;
  return (BytesBuilder()
        ..add(latin1.encode('ID3'))
        ..add([3, 0, 0])
        ..add([
          (size >> 21) & 0x7f,
          (size >> 14) & 0x7f,
          (size >> 7) & 0x7f,
          size & 0x7f,
        ])
        ..add(tag)
        // MPEG-1 Layer III, 128 kbit/s, 44.1 kHz.
        ..add([0xff, 0xfb, 0x90, 0x00, ...List.filled(413, 0)]))
      .toBytes();
}

void main() {
  sqfliteFfiInit();

  group('replayGainLoudness', () {
    test('ID3 TXXX, any case', () {
      final tags = Mp3Metadata()
        ..customMetadata = {
          'replaygain_track_gain': '-6.50 dB',
          'REPLAYGAIN_TRACK_PEAK': '0.5',
        };
      final loudness = replayGainLoudness(tags)!;
      expect(loudness.lufs, closeTo(-11.5, 1e-9));
      expect(loudness.peakDb, closeTo(-6.02, 0.01));
    });

    test('Vorbis comments, and Opus R128 relative to -23 LUFS', () {
      final flac = VorbisMetadata()..replayGainTrackGain = ['+2.00 dB'];
      expect(replayGainLoudness(flac)!.lufs, -20);
      final opus = VorbisMetadata()..unknowns['R128_TRACK_GAIN'] = '-1280';
      expect(replayGainLoudness(opus)!.lufs, -18);
    });

    test('no tags, no loudness', () {
      expect(replayGainLoudness(Mp3Metadata()), isNull);
      expect(replayGainLoudness(Mp4Metadata()), isNull);
    });
  });

  test('the gain goes the strength\'s part of the way to -14 LUFS', () {
    const quiet = Loudness(lufs: -20, peakDb: -12);
    expect(quiet.gainDb(1), 6);
    expect(quiet.gainDb(0.5), 3);
    expect(const Loudness(lufs: -8, peakDb: 0).gainDb(1), -6);
    expect(const Loudness(lufs: -40, peakDb: 0).gainDb(1), 0);
  });

  test('a boost stops where the peak would pass -1 dBFS; a cut never does', () {
    expect(const Loudness(lufs: -24, peakDb: -4).gainDb(1), 3);
    expect(const Loudness(lufs: -20, peakDb: 0.5).gainDb(1), 0);
    expect(const Loudness(lufs: -20).gainDb(1), 0, reason: 'peak unknown');
    expect(const Loudness(lufs: -6).gainDb(1), -8);
    expect(const Loudness(lufs: 5, peakDb: 3).gainDb(1), -15);
  });

  group('the scan', () {
    late Directory root;
    late Directory music;
    late DatabaseSync sync;
    late SongCatalog catalog;
    late LocalLibrary library;
    late Recordings store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('loudness_test');
      music = await Directory('${root.path}/Music').create();
      sync = DatabaseSync(storageRoot: () async => root);
      await writeMusicDb((await sync.localFile('music.db')).path);
      catalog = SongCatalog(sync);
      library = LocalLibrary(
        catalog,
        storageRoot: () async => root,
        factoryOverride: databaseFactoryFfi,
      );
      await library.load();
      await library.addFolder(music.path);
      store = Recordings(library.database);
    });

    tearDown(() async {
      library.dispose();
      catalog.dispose();
      sync.dispose();
      await root.delete(recursive: true);
    });

    test('keeps each file\'s ReplayGain, and forgets a deleted file', () async {
      final tagged = File('${music.path}/Afina - Pay Your Respect.mp3');
      await tagged.writeAsBytes(
        mp3WithTxxx({'REPLAYGAIN_TRACK_GAIN': '-4.00 dB'}),
      );
      final plain = await File('${music.path}/Kino - Kukushka.mp3').create();
      await library.scan();

      RecordingKey file(File f) => (RecordingSource.file, f.path);
      expect((await store.loudness(file(tagged)))!.lufs, -14);
      expect(await store.loudness(file(plain)), isNull);
      // Read once: the plain file waits for the phone's own measurement.
      expect(await store.settled(), {file(tagged)});
      expect(await store.tagsRead(), {tagged.path, plain.path});

      final db = await library.database();
      Future<int> rows() async => (await db.query('recordings')).length;
      expect(await rows(), 2);
      await tagged.delete();
      await library.scan();
      expect(await rows(), 1);
    });

    test('a length and a measurement fill the same row', () async {
      const video = (RecordingSource.youtube, 'abc');
      await store.saveDuration(video, const Duration(seconds: 200));
      expect(await store.loudness(video), isNull);
      expect(await store.settled(), isEmpty);

      await store.saveLoudness(
        video,
        const Loudness(lufs: -9, peakDb: 0.5),
        LoudnessMethod.analysis,
      );
      expect((await store.loudness(video))!.peakDb, 0.5);
      expect(await store.duration(video), const Duration(seconds: 200));
      expect(await store.settled(), {video});
    });

    test('keyOf: a server file, else a video, else the phone file', () {
      expect(
        Recordings.keyOf(serverFileId: 7, youtubeVideoId: 'v', path: '/a'),
        (RecordingSource.server, '7'),
      );
      expect(Recordings.keyOf(youtubeVideoId: 'v', path: '/a'), (
        RecordingSource.youtube,
        'v',
      ));
      expect(Recordings.keyOf(path: '/a'), (RecordingSource.file, '/a'));
      expect(Recordings.keyOf(), isNull);
    });

    test('the measurer measures what isn\'t settled, newest first', () async {
      final tagged = File('${music.path}/Afina - Pay Your Respect.mp3');
      await tagged.writeAsBytes(
        mp3WithTxxx({'REPLAYGAIN_TRACK_GAIN': '-4.00 dB'}),
      );
      final plain = await File('${music.path}/Kino - Kukushka.mp3').create();
      final broken = await File('${music.path}/Kino - Gruppa krovi.mp3')
          .create();
      await library.scan();

      final measured = <String>[];
      final measurer = LoudnessMeasurer(
        store,
        () async => [
          (key: (RecordingSource.youtube, 'v1'), path: '/cache/v1.webm'),
          for (final f in [tagged, plain, broken])
            (key: (RecordingSource.file, f.path), path: f.path),
        ],
        measure: (path) async {
          measured.add(path);
          if (path == broken.path) throw Exception('unreadable');
          return (
            loudness: const Loudness(lufs: -20),
            duration: const Duration(seconds: 3),
          );
        },
        delay: Duration.zero,
      );
      measurer.schedule();
      await measurer.idle;
      expect(measured, isEmpty, reason: 'off until leveling is on');

      measurer.enabled = true;
      await measurer.idle;
      expect(measured, ['/cache/v1.webm', plain.path, broken.path]);
      expect(
        await store.duration((RecordingSource.youtube, 'v1')),
        const Duration(seconds: 3),
      );
      expect(await store.loudness((RecordingSource.file, broken.path)), isNull);

      measured.clear();
      measurer.schedule();
      await measurer.idle;
      expect(measured, isEmpty, reason: 'each file once, a failed one too');
      measurer.dispose();
    });
  });
}
