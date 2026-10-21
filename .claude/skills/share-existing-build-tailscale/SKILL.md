---
name: share-existing-build-tailscale
description: 'Serve the release APK that is already built in this repo over Tailscale for 15 minutes, under the same fixed download link as share-build-tailscale, without building anything — even if the APK is older than the code. Trigger on "/share-existing-build-tailscale", "udostępnij istniejący build", "udostępnij ostatni build bez budowania", "daj link do apki bez builda", "share the existing build", "share without rebuilding", or when the user wants the link right away and explicitly does not want a build. If the user wants the build brought up to date first, use share-build-tailscale instead.'
---

# Share existing build over Tailscale

Same as `share-build-tailscale`, minus the build: it never runs `flutter build`, Gradle, or
anything else that compiles. It serves whatever `build/app/outputs/flutter-apk/app-release.apk`
is there right now, under the same link (`http://<tailscale-ip>:8001/music_database_app.apk`).

It reuses the scripts of `share-build-tailscale` instead of having its own copies, so both skills
always serve the same way and replace each other's running share (shared PID file
`build/share-server.pid`). Read `.claude/skills/share-build-tailscale/SKILL.md` Step 3 for how the
server behaves; don't duplicate those scripts here.

Run everything from the repo root.

## Step 1 — Check the APK exists, and how old it is

```bash
.claude/skills/share-build-tailscale/scripts/check_build_fresh.sh
```

Use the result only for information, never as a reason to build:

- `missing` → there is nothing to share. Stop and tell the user; suggest `share-build-tailscale`
  if they want one built. Do not build it yourself.
- `stale: <file>` → share it anyway, but remember to tell the user the APK is older than the code
  (and which file is newer).
- `fresh` → share it.

## Step 2 — Serve it

```bash
.claude/skills/share-build-tailscale/scripts/serve_apk.sh 15
```

Run it as one foreground Bash call; it returns within a few seconds. Exit codes:

- `2` → Tailscale is down. Tell the user; don't fall back to another interface.
- `4` → port 8001 is held by another program. Show `ss -ltnp 'sport = :8001'` and ask; don't
  change the port.
- `3` → the server didn't come up; show `build/share-server.log`.

Never stop the server with `pkill -f <pattern>` (it kills the Bash tool's own shell). To stop it
early: `kill -- -$(cat build/share-server.pid)`.

## Step 3 — Report back

Answer in Polish with:

- the link (from `URL=`), as a plain clickable URL, noting it's the same permanent link as always,
- which build it serves (from `BUILT=`) and that nothing was rebuilt,
- if Step 1 said `stale`, a clear note that this build doesn't include the latest code changes
  (name the newer file),
- when it expires (from `EXPIRES=`),
- a reminder that the phone must be connected to Tailscale and allow installing apps from the
  browser ("nieznane źródła"). The release APK is signed with the debug key, so it updates an
  existing install of this app in place.
