// AudioDeviceType is marked experimental; the package's version is pinned by pubspec.lock.
// ignore_for_file: experimental_member_use

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/playback/interrupted_players.dart';

AudioDevice _device(
  String id,
  AudioDeviceType type, {
  String name = 'Głośnik',
}) =>
    AudioDevice(id: id, name: name, isInput: false, isOutput: true, type: type);

void main() {
  final phone = _device('1', AudioDeviceType.builtInSpeaker, name: 'Telefon');
  final speaker = _device('2', AudioDeviceType.bluetoothA2dp);
  final speakerCalls = _device('3', AudioDeviceType.bluetoothSco);

  Future<Set<AudioDevice>> Function() outputs(Set<AudioDevice> devices) =>
      () async => devices;

  test('resumes when the outputs did not change', () async {
    final interrupted = InterruptedPlayers<String>();
    interrupted.began(['a'], outputs({phone, speaker}));
    expect(await interrupted.ended(outputs({phone, speaker})), ['a']);
  });

  test('stays paused when the speaker went away during the call', () async {
    final interrupted = InterruptedPlayers<String>();
    interrupted.began(['a', 'b'], outputs({phone, speaker, speakerCalls}));
    expect(await interrupted.ended(outputs({phone})), isEmpty);
  });

  test('resumes when only the call side of the speaker went away', () async {
    final interrupted = InterruptedPlayers<String>();
    interrupted.began(['a'], outputs({phone, speaker, speakerCalls}));
    expect(await interrupted.ended(outputs({phone, speaker})), ['a']);
  });

  test('resumes when a speaker connected during the call', () async {
    final interrupted = InterruptedPlayers<String>();
    interrupted.began(['a'], outputs({phone}));
    expect(await interrupted.ended(outputs({phone, speaker})), ['a']);
  });

  test('resumes when the speaker came back with a new id', () async {
    final interrupted = InterruptedPlayers<String>();
    interrupted.began(['a'], outputs({phone, speaker}));
    final back = _device('9', AudioDeviceType.bluetoothA2dp);
    expect(await interrupted.ended(outputs({phone, back})), ['a']);
  });

  test('does not resume a player started by hand during the call', () async {
    final interrupted = InterruptedPlayers<String>();
    interrupted.began(['a'], outputs({phone}));
    interrupted.startedPlaying('a');
    expect(await interrupted.ended(outputs({phone})), isEmpty);
  });

  test('resumes only once', () async {
    final interrupted = InterruptedPlayers<String>();
    interrupted.began(['a'], outputs({phone}));
    await interrupted.ended(outputs({phone}));
    expect(await interrupted.ended(outputs({phone})), isEmpty);
  });

  test('a second interruption keeps the outputs from the first', () async {
    final interrupted = InterruptedPlayers<String>();
    interrupted.began(['a'], outputs({phone, speaker}));
    interrupted.began(['b'], outputs({phone}));
    expect(await interrupted.ended(outputs({phone})), isEmpty);
  });
}
