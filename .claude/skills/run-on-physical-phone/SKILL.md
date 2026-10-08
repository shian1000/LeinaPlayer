---
name: run-on-physical-phone
description: 'Build the current code in this repo as a release APK, install it on a connected physical Android phone (USB or wireless debugging — never an emulator), launch the app, and open scrcpy so the user can see and control the phone screen from this computer. Trigger on requests like "uruchom na telefonie", "wrzuć najnowszego builda na telefon", "pokaż mi to na telefonie", "run on phone", "deploy to my phone", or when the user wants to see current code running on real hardware. Do not trigger for emulators (no physical phone involved) or when the user just wants `flutter analyze`/`flutter test` run — this skill always does a real build + install + on-screen launch.'
---

# Run on physical phone

## What this does, in order

1. Find connected physical phones.
2. Build a release APK and install it (never `flutter run` — see below).
3. Launch the app on the phone.
4. Open scrcpy so the user can see and click/type into the phone from this computer.

## Step 1 — Find the target device

```bash
adb devices -l
```

Only consider entries whose `product:`/model looks like a real phone. Ignore anything containing
`emulator-` — this skill is for physical hardware only; if the user wants an emulator, that's a
different task. A phone can appear two ways:

- **USB**: a serial like `HYFDU19412006823`.
- **Wireless debugging**: an `ip:port` like `192.0.2.15:46499`, or (right after boot, before a
  manual `adb connect`) an mDNS name like `adb-XXXXXXXX..._adb-tls-connect._tcp`. Wireless IPs and
  ports change across reconnects/reboots — always read the current one from `adb devices -l`, never
  reuse an address from a previous session or from this file.

If no physical device is listed, stop and tell the user to connect one (USB cable with USB
debugging enabled, or wireless debugging on the same Wi-Fi network — see `docs/architecture.md` /
project history for the one-time pairing steps) — don't try to guess or wait silently.

If more than one physical device is listed and the skill was invoked with an argument naming one
(e.g. "pixel", "huawei"), match it against the model/product string. Otherwise ask the user which
one to target — don't default to picking one silently.

## Step 2 — Build and install (not `flutter run`)

Deliberately use a one-shot build + install, not `flutter run`: `flutter run` stays attached
indefinitely for hot-reload, which previously left multiple orphaned background processes running
for hours after the user had moved on. This skill should leave nothing running afterward except
scrcpy.

```bash
flutter build apk --release
adb -s <device-id> install -r build/app/outputs/flutter-apk/app-release.apk
```

(`-r` reinstalls over any existing copy.) The project's application id is
`com.shian1000.music_database_app` (from `android/app/build.gradle.kts`) — only re-check that file
if the install step reports a different id than expected.

## Step 3 — Launch the app

```bash
adb -s <device-id> shell monkey -p com.shian1000.music_database_app -c android.intent.category.LAUNCHER 1
```

This starts the launcher activity without needing to know its exact class name.

## Step 4 — Open scrcpy

```bash
DISPLAY=:0 setsid nohup scrcpy -s <device-id> > <scratchpad>/scrcpy.log 2>&1 < /dev/null &
disown
```

Launch it exactly this way (`setsid` + `nohup` + background `&` + `disown` in one Bash call) — a
plain background launch was observed to get reaped as soon as the tool call that started it
returned. After launching, check the log after a couple seconds to confirm it's actually mirroring
and not stuck on an error.

**Known device quirk:** older/budget phones (observed on a Huawei SNE-LX1, Android 10) can fail
with `[server] ERROR: Capture/encoding error: android.media.MediaCodec$CodecException` at full
resolution/bitrate. If that happens, retry with reduced settings:

```bash
scrcpy -s <device-id> --max-size=1024 --video-bit-rate=4M
```

Try default settings first; only fall back to reduced settings if the default run errors.

## Step 5 — Report back

Tell the user which device got the build, that scrcpy is open, and to check their screen. If
scrcpy needed the reduced-settings fallback, mention that so it's not a surprise.
