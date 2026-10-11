import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/data/database_sync.dart';
import 'package:music_database_app/src/data/local_library.dart';
import 'package:music_database_app/src/data/song_catalog.dart';
import 'package:music_database_app/src/data/source_settings.dart';
import 'package:music_database_app/src/data/youtube_audio.dart';
import 'package:music_database_app/src/data/youtube_library.dart';
import 'package:music_database_app/src/playback/player_controller.dart';
import 'package:music_database_app/src/playback/youtube_playback.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Backend implements AudioBackend {
  final opened = <String>[];
  final _state = StreamController<({bool playing, bool completed})>.broadcast();

  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration?> get duration => const Stream.empty();
  @override
  Stream<({bool playing, bool completed})> get state => _state.stream;
  @override
  Future<void> open(NowPlaying track) async => opened.add(track.source);
  @override
  Future<void> play() async => _state.add((playing: true, completed: false));
  @override
  Future<void> pause() async => _state.add((playing: false, completed: false));
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  sqfliteFfiInit();

  late Directory root;
  late DatabaseSync sync;
  late SongCatalog catalog;
  late LocalLibrary local;
  late YouTubeLibrary library;
  late SourceSettings settings;
  late _Backend backend;
  late PlayerController player;
  late List<String> calls;
  late List<Uri> opened;
  var newPipeFails = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('youtube_playback_test');
    sync = DatabaseSync(storageRoot: () async => root);
    catalog = SongCatalog(sync, factoryOverride: databaseFactoryFfi);
    local = LocalLibrary(
      catalog,
      storageRoot: () async => root,
      factoryOverride: databaseFactoryFfi,
    );
    library = YouTubeLibrary(local.database, storageRoot: () async => root);
    await library.load();
    settings = SourceSettings();
    await settings.load();
    backend = _Backend();
    player = PlayerController(backend: () => backend);
    calls = [];
    opened = [];
    newPipeFails = false;
  });

  tearDown(() async {
    player.dispose();
    library.dispose();
    local.dispose();
    catalog.dispose();
    sync.dispose();
    await root.delete(recursive: true);
  });

  YouTubePlayback playback() => YouTubePlayback(
    audio: YouTubeAudio(
      newPipeAvailable: true,
      newPipe: (id) async {
        calls.add('newPipe');
        if (newPipeFails) throw Exception('403');
        return [YouTubeAudioStream(url: 'https://s/$id', itag: 251)];
      },
    ),
    library: library,
    settings: settings,
    player: player,
    openExternal: (uri) async {
      opened.add(uri);
      return true;
    },
  );

  NowPlaying track(String source) =>
      NowPlaying(title: 'T', artist: 'A', source: source, coverSeed: 's');

  Future<File> cache(String id) async {
    final file = await library.newCacheFile(id, 'webm');
    await file.writeAsBytes([1]);
    await library.cacheComplete(id, file, 25);
    return file;
  }

  test('default order: the cache before streaming', () async {
    final file = await cache('v');
    expect(await playback().play('v', track), YouTubePlayedVia.cache);
    expect(backend.opened, [file.path]);
    expect(calls, isEmpty);
  });

  test('the user\'s order: NewPipe first skips a cached copy', () async {
    await cache('v');
    await settings.setPlaybackMethodOrder([
      YouTubePlaybackMethod.newPipe,
      YouTubePlaybackMethod.cache,
      YouTubePlaybackMethod.explode,
      YouTubePlaybackMethod.ytDlpServer,
      YouTubePlaybackMethod.youtubeApp,
    ]);
    expect(await playback().play('v', track), YouTubePlayedVia.stream);
    expect(backend.opened, ['https://s/v']);
  });

  test('when streaming fails, the YouTube app is the last resort', () async {
    newPipeFails = true;
    var connecting = 0;
    expect(
      await playback().play('v', track, onConnecting: () => connecting++),
      YouTubePlayedVia.youtubeApp,
    );
    expect(calls, ['newPipe']);
    expect(opened, [Uri.parse('https://www.youtube.com/watch?v=v')]);
    expect(connecting, 1);
  });

  test('nothing switched on that works: the reasons are listed', () async {
    newPipeFails = true;
    await settings.setPlaybackMethod(YouTubePlaybackMethod.youtubeApp, false);
    await expectLater(
      playback().play('v', track),
      throwsA(
        isA<YouTubePlaybackException>().having(
          (e) => e.message,
          'message',
          contains('NewPipe'),
        ),
      ),
    );
  });
}
