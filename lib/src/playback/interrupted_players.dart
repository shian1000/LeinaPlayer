// AudioDeviceType is marked experimental; the package's version is pinned by pubspec.lock.
// ignore_for_file: experimental_member_use

import 'package:audio_session/audio_session.dart';

/// Outputs music can leave through and that can go away. Bluetooth's SCO entry is left out:
/// it's the telephony side of a speaker, and a call may bring it and take it away.
const _removableMusicOutputs = {
  AudioDeviceType.wiredHeadset,
  AudioDeviceType.wiredHeadphones,
  AudioDeviceType.lineAnalog,
  AudioDeviceType.lineDigital,
  AudioDeviceType.bluetoothA2dp,
  AudioDeviceType.bluetoothLe,
  AudioDeviceType.hdmi,
  AudioDeviceType.hdmiArc,
  AudioDeviceType.usbAudio,
  AudioDeviceType.dock,
  AudioDeviceType.auxLine,
  AudioDeviceType.hearingAid,
  AudioDeviceType.carAudio,
};

/// Whether an output music could use in [before] is missing from [now]. By type and name, as a
/// device reconnected in the meantime has a new id.
bool lostMusicOutput(Set<AudioDevice> before, Set<AudioDevice> now) {
  final left = {for (final d in now) (d.type, d.name)};
  return before.any(
    (d) =>
        d.isOutput &&
        _removableMusicOutputs.contains(d.type) &&
        !left.contains((d.type, d.name)),
  );
}

/// The players a phone call (or another app) paused and which of them should play on after it.
/// Replaces just_audio's own handling, whose "resume" can't be taken back once the player is
/// paused: music would come out of the phone after a call during which the speaker went away.
class InterruptedPlayers<P> {
  final _players = <P>{};
  Future<Set<AudioDevice>>? _outputsBefore;

  void began(Iterable<P> playing, Future<Set<AudioDevice>> Function() outputs) {
    if (playing.isEmpty) return;
    if (_players.isEmpty) _outputsBefore = outputs();
    _players.addAll(playing);
  }

  /// The players to start again.
  Future<List<P>> ended(Future<Set<AudioDevice>> Function() outputs) async {
    final players = _players.toList();
    final before = _outputsBefore;
    forget();
    if (players.isEmpty || before == null) return const [];
    return lostMusicOutput(await before, await outputs()) ? const [] : players;
  }

  /// The user started [player] during the interruption, so it's no longer the interruption's.
  void startedPlaying(P player) => _players.remove(player);

  void forget() {
    _players.clear();
    _outputsBefore = null;
  }
}
