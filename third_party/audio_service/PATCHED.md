# audio_service 0.18.19, patched

A copy of [audio_service](https://pub.dev/packages/audio_service) 0.18.19 (the newest release
as of 2026-10-20; `example/` left out), used through `dependency_overrides` in the app's
`pubspec.yaml`. Drop the copy once a release fixes the bug below.

## The bug

`AudioService.onDestroy()` calls the static `listener`'s `onDestroy()` and sets it to `null`.
The listener (`AudioServicePlugin.AudioHandlerInterface`) then disposes the Flutter engine —
unless an activity is attached, when the engine is kept. The plugin registers the listener again
only when its `audioHandlerInterface` is `null`, which it no longer is, so the next
`AudioService` (started when music plays again, same process) has no listener: every control
from Android — the notification's and lock screen's buttons, headset and Bluetooth buttons —
ends at `if (listener == null) return`. The app → Android direction still works, so the
notification looks alive. Seen on the Pixel 7a (Android 17) after the app ran for days: the
process was 2 days old, its `AudioService` 1 hour old. Android stops the paused app's service
there ("Stopping service due to app idle" in logcat); the exact way to the dead state couldn't
be triggered on demand.

## The patch

Two places, both marked "Leina Radio patch":

- `AudioService.onDestroy()` clears `listener` before calling it, not after.
- `AudioHandlerInterface.onDestroy()` registers itself again with `AudioService.init(this)`
  when it is still the plugin's handler, i.e. the engine survived. A disposed engine detaches
  the plugin, which clears `audioHandlerInterface`, so nothing is registered then.
