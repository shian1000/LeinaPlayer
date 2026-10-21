---
name: share-build-tailscale
description: 'Make sure the release APK of this repo is up to date (rebuilding it if not), then copy it to music_database_app.apk and serve it over the Tailscale network for 15 minutes under a fixed download link that always points at the newest build, after which the server stops by itself. Trigger on "/share-build-tailscale", "udostępnij builda", "daj link do apki", "share the build", "send me the APK link", or when the user wants to download/install the current build on a device without a USB cable. Do not trigger when the user wants it installed on the USB-connected phone right now — that is run-on-physical-phone. Do not trigger when the user wants the existing build shared without building — that is share-existing-build-tailscale.'
---

# Share build over Tailscale

Adapted from the same skill in `../CustomMapMarker`. Differences: file name
`music_database_app.apk` and port **8001** (CustomMapMarker uses 8000, so both projects can share
a build at the same time without either link changing).

## What this does, in order

1. Check whether the release APK reflects the current code.
2. If not, rebuild it (with the same memory precautions as run-on-physical-phone).
3. Serve only that APK over Tailscale for 15 minutes; the server then stops on its own.
4. Give the user the direct download link and the time it expires.

Run everything from the repo root.

## Step 1 — Is the build current?

```bash
.claude/skills/share-build-tailscale/scripts/check_build_fresh.sh
```

It compares `build/app/outputs/flutter-apk/app-release.apk` with everything that goes into it
(`lib/`, `pubspec.yaml`, `pubspec.lock`, `android/` minus build outputs, `assets/` if present).

- `fresh` → skip to Step 3.
- `missing` or `stale: <file>` → Step 2. Mention which file made it stale.

The script only compares file times. If the user says code changed in a way it can't see
(e.g. a dependency in the pub cache was edited), rebuild anyway.

## Step 2 — Rebuild

Follow **Step 2b (memory check)** and **Step 3 (build)** of
`.claude/skills/run-on-physical-phone/SKILL.md`, but skip the install. That means: stop leftover
Gradle daemons, check `free -m` (ask the user before building below 2500 MB available), run
`tool/build_release_apk.sh` (the release build with its version numbering), then stop the Gradle daemon with the Studio JBR as `JAVA_HOME`.
Don't copy those commands here from memory; read that file so both skills stay in sync.

Re-run `check_build_fresh.sh` afterwards; it must print `fresh`.

## Step 3 — Serve it

```bash
.claude/skills/share-build-tailscale/scripts/serve_apk.sh 15
```

The script:

- binds to this machine's **Tailscale** IPv4 (`tailscale ip -4`), so
  only devices on the user's tailnet can reach it. Never bind to `0.0.0.0` or the LAN address.
  If Tailscale is down, the script exits with code 2; tell the user, don't fall back to another
  interface.
- copies the APK to `build/share/music_database_app.apk` and serves only that directory. The file
  name, port and Tailscale IP don't change, so the link is always the same:
  `http://<tailscale-ip>:8001/music_database_app.apk` (the script prints it as `URL=`), and it always points at the build just
  checked. Every response carries `Cache-Control: no-store` (`scripts/no_cache_server.py`), so the
  phone's browser can't hand out a previously downloaded, older APK under the same URL.
- runs the server under `timeout` in its own session (`setsid nohup … & disown`, the same pattern
  that keeps scrcpy alive), so it stops by itself after 15 minutes even if this conversation ends.
- replaces an earlier share started by this script (PID in `build/share-server.pid`). If port
  8001 is taken by some other program, it exits with code 4 instead of switching ports (that
  would change the link): show the user what holds the port (`ss -ltnp 'sport = :8001'`) and ask.
- checks the link with `curl` before printing `URL=…`, `BUILT=…` (APK build time) and
  `EXPIRES=HH:MM`.

Run it as one foreground Bash call; it returns within a few seconds. Never stop the server with
`pkill -f <pattern>`: the pattern also matches the Bash tool's own shell and kills the call.
To stop it early, use `kill -- -$(cat build/share-server.pid)`.

## Step 4 — Report back

Answer in Polish with:

- the link (from `URL=`), as a plain clickable URL, noting it's the same permanent link as always,
- which build it serves (from `BUILT=`),
- when it expires (from `EXPIRES=`),
- whether the APK was rebuilt or already current,
- a reminder that the phone must be connected to Tailscale and allow installing apps from the
  browser ("nieznane źródła"). The release APK is signed with the debug key
  (`android/app/build.gradle.kts`), so it updates an existing install of this app in place.
