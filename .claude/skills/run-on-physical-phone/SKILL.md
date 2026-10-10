---
name: run-on-physical-phone
description: 'Build the current code in this repo as a release APK (skipped when the existing APK is already current), install it on a connected physical Android phone (USB or wireless debugging — never an emulator), launch the app, and open scrcpy so the user can see and control the phone screen from this computer. Trigger on requests like "uruchom na telefonie", "wrzuć najnowszego builda na telefon", "pokaż mi to na telefonie", "run on phone", "deploy to my phone", or when the user wants to see current code running on real hardware. Do not trigger for emulators (no physical phone involved) or when the user just wants `flutter analyze`/`flutter test` run — this skill always does a real build + install + on-screen launch.'
---

# Run on physical phone

## What this does, in order

1. Find connected physical phones.
2. Skip the build if the APK is already current; otherwise check there is enough free memory.
3. Build a release APK and install it (never `flutter run` — see below).
4. Launch the app on the phone.
5. Open scrcpy so the user can see and click/type into the phone from this computer.

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
debugging enabled, or wireless debugging on the same Wi-Fi network; the one-time
pairing is done by the user on the phone) — don't try to guess or wait silently.

If more than one physical device is listed and the skill was invoked with an argument naming one
(e.g. "pixel", "huawei"), match it against the model/product string. Otherwise ask the user which
one to target — don't default to picking one silently.

## Step 2 — Skip the build if the APK is current

```bash
.claude/skills/share-build-tailscale/scripts/check_build_fresh.sh
```

If it prints `fresh`, the existing release APK already contains the current code: skip the memory
check and the build, and go straight to the install in Step 3. Otherwise (`missing` or
`stale: <file>`) continue below. Rebuild anyway if the user asks for it.

## Step 2b — Check memory before building

This machine has only ~7.6 GB of RAM and a release build (of the sibling CustomMapMarker project)
previously got OOM-killed (exit code 137), forcing the user to reboot. Check memory **before**
every build:

```bash
free -m
pgrep -af 'GradleDaemon|KotlinCompileDaemon'
```

- Leftover Gradle/Kotlin daemons from earlier builds of this project are ours — stop them first to
  reclaim their memory: `(cd android && JAVA_HOME=/snap/android-studio/current/jbr ./gradlew --stop)`.
- Then read the `available` column of `free -m`. With the caps below, a release build succeeded
  starting from ~2.7 GB available (plus 4 GB swap); the OOM kill happened with the uncapped
  template settings.
  - **≥ 2500 MB available**: build.
  - **Below 2500 MB**: don't build yet. Show the user the biggest memory users
    (`ps -eo pid,rss,comm --sort=-rss | head -8`; RSS is in KB, convert to MB when reporting) and
    ask whether they want to close something first or build anyway. Never kill the user's own
    processes yourself.
- Keep the memory caps in `android/gradle.properties` (`-Xmx2G`, `kotlin.daemon.jvmargs=-Xmx1G`).
  The Flutter template default is `-Xmx8G`, more than the machine's whole RAM; if a Flutter upgrade
  or `flutter create` restores it, put the caps back before building.

## Step 3 — Build and install (not `flutter run`)

Deliberately use a one-shot build + install, not `flutter run`: `flutter run` stays attached
indefinitely for hot-reload, which previously left multiple orphaned background processes running
for hours after the user had moved on. This skill should leave nothing running afterward except
scrcpy.

```bash
flutter build apk --release
(cd android && JAVA_HOME=/snap/android-studio/current/jbr ./gradlew --stop)
adb -s <device-id> install -r build/app/outputs/flutter-apk/app-release.apk
```

`JAVA_HOME` must point at the JDK Flutter builds with (Android Studio's bundled JBR, see
`flutter doctor -v`): `./gradlew --stop` only stops daemons running on the same JVM, so with the
system Java it prints nothing useful and leaves the ~2 GB daemon alive. Confirm it reports
`1 Daemon stopped` (or that `pgrep -af GradleDaemon` is empty afterwards).

Stop the Gradle daemon right after the build: it otherwise keeps ~2 GB resident in the background,
which is exactly what squeezed the next build out of memory.

(`-r` reinstalls over any existing copy.) The project's application id is
`com.shian1000.music_database_app` (from `android/app/build.gradle.kts`) — only re-check that file
if the install step reports a different id than expected.

The release build is currently signed with the debug key (`signingConfig = debug` in
`android/app/build.gradle.kts`), so it installs over earlier `flutter run` debug builds without
trouble. If install fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE` (signature mismatch, e.g. after
a real release key is configured), tell the user that reinstalling requires uninstalling the
existing app first — which wipes all of the app's local data on the phone — and only run
`adb -s <device-id> uninstall com.shian1000.music_database_app` after they confirm.

## Step 4 — Launch the app

```bash
adb -s <device-id> shell monkey -p com.shian1000.music_database_app -c android.intent.category.LAUNCHER 1
```

This starts the launcher activity without needing to know its exact class name.

## Step 5 — Open scrcpy

```bash
DISPLAY=:0 SNAP_LAUNCHER_NOTICE_ENABLED=false setsid nohup scrcpy -s <device-id> > <scratchpad>/scrcpy.log 2>&1 < /dev/null &
disown
```

`SNAP_LAUNCHER_NOTICE_ENABLED=false` matters: after a snap update the scrcpy snap shows a
one-off "unofficial distribution" notice instead of mirroring (the log then holds only that
notice and no `[server] INFO: Device:` line).

Launch it exactly this way (`setsid` + `nohup` + background `&` + `disown` in one Bash call) — a
plain background launch was observed to get reaped as soon as the tool call that started it
returned. After launching, check the log after a couple seconds to confirm it's actually mirroring
and not stuck on an error.

**Restarting scrcpy** (e.g. the window is blank): find it by exact process name, never with
`pgrep -f`/`pkill -f` — a pattern also matches the Bash tool's own command line and kills the
call (exit code 144). Use `for p in $(pgrep -x scrcpy); do kill "$p"; done`, then launch it again
as above. A blank window is also what you get while the phone is asleep:
`adb -s <device-id> shell dumpsys power | grep mWakefulness`; wake it with
`adb -s <device-id> shell input keyevent KEYCODE_WAKEUP` (unlocking stays with the user).

**Known device quirk:** older/budget phones (observed on a Huawei SNE-LX1, Android 10) can fail
with `[server] ERROR: Capture/encoding error: android.media.MediaCodec$CodecException` at full
resolution/bitrate. If that happens, retry with reduced settings:

```bash
scrcpy -s <device-id> --max-size=1024 --video-bit-rate=4M
```

Try default settings first; only fall back to reduced settings if the default run errors.

## Step 6 — Report back

Tell the user which device got the build, that scrcpy is open, and to check their screen. If
scrcpy needed the reduced-settings fallback, mention that so it's not a surprise.
