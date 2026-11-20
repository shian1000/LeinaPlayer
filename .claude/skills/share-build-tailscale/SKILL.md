---
name: share-build-tailscale
description: 'Make sure the release APK of this repo is up to date (rebuilding it if not), then copy it to leina-player.apk and serve it over the Tailscale network for 15 minutes under a fixed download link that always points at the newest build, after which the server stops by itself. Trigger on "/share-build-tailscale", "udostępnij builda", "daj link do apki", "share the build", "send me the APK link", or when the user wants to download/install the current build on a device without a USB cable. Do not trigger when the user wants it installed on the USB-connected phone right now — that is run-on-physical-phone. Do not trigger when the user wants the existing build shared without building — that is share-existing-build-tailscale.'
---

# Share build over Tailscale

Adapted from the same skill in `../CustomMapMarker`.
Difference: the file name `leina-player.apk`. All the owner's apps share through Leina APK Manager
(Step 3), so no port belongs to this project.

## What this does, in order

1. Check whether the release APK reflects the current code.
2. If not, rebuild it (after the same machine check as run-on-physical-phone).
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

Follow **Step 2b (check the machine has room)** and **Step 3 (build)** of
`.claude/skills/run-on-physical-phone/SKILL.md`, but skip the install. That means: stop leftover
Gradle daemons of this repo, run `tool/check_resources.sh` (exit 1 → show the user and ask
before building), run
`tool/build_release_apk.sh` (the release build with its version numbering) with the Studio JBR as `JAVA_HOME`, then stop the Gradle daemon.
Don't copy those commands here from memory; read that file so both skills stay in sync.

Re-run `check_build_fresh.sh` afterwards; it must print `fresh`.

## Step 3 — Serve it

```bash
.claude/skills/share-build-tailscale/scripts/serve_apk.sh 15
```

The script hands the APK to **Leina APK Manager** (`../LeinaAPKManager`, the owner's app next to
this repo), which shares the builds of all the owner's apps from one server on one port of this
machine's **Tailscale** address — never `0.0.0.0` or the LAN, and the tailnet policy lets the
phone in only on that port. It:

- copies the APK and serves it as `leina-player.apk`, so the link is always the same:
  `http://<tailscale-ip>:<port>/leina-player.apk` (printed as `URL=`; the port is in the manager's
  `settings.json`), and it always points at the build just checked. Every response carries
  `Cache-Control: no-store`, so the phone's browser can't hand out an older, cached APK.
- keeps it for 15 minutes; builds of other apps shared at the same time keep their own times.
  The server stops by itself once nothing is shared, even if this conversation ends. Sharing
  again replaces the copy and restarts the 15 minutes.
- checks the link before printing `URL=…`, `BUILT=…` (APK build time) and `EXPIRES=HH:MM`.

Exit codes: `2` Tailscale is down — tell the user, don't fall back to another interface; `3` the
server didn't come up — show the message (log: `~/.cache/leina-apk-manager/server.log`); `4` the
port is held by another program — show the message and ask, don't change ports; `5`
`../LeinaAPKManager` is missing — tell the user, don't start a server of your own.

Run it as one foreground Bash call; it returns within a few seconds. To stop sharing early:
`../LeinaAPKManager/apk_manager.py stop --repo .` — never `pkill -f <pattern>`, which also kills
the Bash tool's own shell.

## Step 4 — Report back

Answer in Polish with:

- the link (from `URL=`), as a plain clickable URL, noting it's the same permanent link as always,
- which build it serves (from `BUILT=`),
- when it expires (from `EXPIRES=`),
- whether the APK was rebuilt or already current,
- a reminder that the phone must be connected to Tailscale and allow installing apps from the
  browser ("nieznane źródła"). The release APK is signed with the release key
  (`docs/agent-notes/signing.md`), so it updates an install from a GitHub release or an earlier
  share in place (one signed with the old debug key needs uninstalling first).
