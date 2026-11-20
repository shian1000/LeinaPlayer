#!/usr/bin/env bash
# Serves the current release APK over Tailscale for a limited time through Leina APK Manager
# (../LeinaAPKManager, the owner's app next to this repo): one server on one port shares the
# builds of all the owner's apps at once, each under its own fixed file name, so the link never
# changes between builds: http://<tailscale-ip>:<port>/<file>.apk (file name in the manager's apps.json).
# Usage: serve_apk.sh [minutes=15]
# Prints URL=..., BUILT=... and EXPIRES=HH:MM on success. Exit codes: 2 Tailscale is down,
# 3 the server didn't come up, 4 the port is held by another program, 5 Leina APK Manager is missing.
set -euo pipefail

MINUTES="${1:-15}"
[[ "$MINUTES" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: minutes must be a whole number, got '$MINUTES'" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
# The manager sits next to the main checkout; a git worktree (e.g. a Claude session's, inside
# .claude/worktrees/) finds it through the main repository. The worktree's own APK is served.
MAIN="$(dirname "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$ROOT/.git")")"
MANAGER="$MAIN/../LeinaAPKManager/apk_manager.py"
[[ -x "$MANAGER" ]] || { echo "ERROR: Leina APK Manager not found at ../LeinaAPKManager (it serves the APK)" >&2; exit 5; }

exec "$MANAGER" share --repo "$ROOT" "$MINUTES"
