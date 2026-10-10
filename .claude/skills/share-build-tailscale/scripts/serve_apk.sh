#!/usr/bin/env bash
# Serves the current release APK over Tailscale for a limited time, then the
# server stops on its own. The URL never changes between builds:
# http://<tailscale-ip>:<port>/music_database_app.apk
# Usage: serve_apk.sh [minutes=15] [port=8001]
# Prints URL=..., BUILT=... and EXPIRES=HH:MM on success.
set -euo pipefail

MINUTES="${1:-15}"
PORT="${2:-8001}"
[[ "$MINUTES" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: minutes must be a whole number, got '$MINUTES'" >&2; exit 1; }
SECONDS_TOTAL=$((MINUTES * 60))

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
SHARE_DIR="$ROOT/build/share"
# Kept outside SHARE_DIR so they don't show up in the served directory listing.
PID_FILE="$ROOT/build/share-server.pid"
LOG_FILE="$ROOT/build/share-server.log"

[[ -f "$APK" ]] || { echo "ERROR: no APK at $APK" >&2; exit 1; }

IP="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
[[ -n "$IP" ]] || { echo "ERROR: no Tailscale IPv4 address (is Tailscale up?)" >&2; exit 2; }

# Replace a share started earlier by this script (its own process group).
if [[ -f "$PID_FILE" ]]; then
  old="$(cat "$PID_FILE")"
  if kill -0 "$old" 2>/dev/null; then
    kill -- "-$old" 2>/dev/null || kill "$old" 2>/dev/null || true
    sleep 0.5
  fi
  rm -f "$PID_FILE"
fi

# Only a copy of the current APK is served, always under the same name so the
# link stays the same. Caching is prevented by the server (no-store), not by
# the file name.
NAME="music_database_app.apk"
rm -rf "$SHARE_DIR"
mkdir -p "$SHARE_DIR"
cp -p "$APK" "$SHARE_DIR/$NAME"

# A fixed port keeps the link stable, so don't silently move to another one.
if ss -ltnH "sport = :$PORT" | grep -q .; then
  echo "ERROR: port $PORT is already in use by another program" >&2
  exit 4
fi

setsid nohup timeout "${SECONDS_TOTAL}s" \
  python3 "$(dirname "$0")/no_cache_server.py" "$PORT" "$IP" "$SHARE_DIR" \
  > "$LOG_FILE" 2>&1 < /dev/null &
echo $! > "$PID_FILE"
disown

URL="http://$IP:$PORT/$NAME"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -sfI "$URL" > /dev/null 2>&1 && break
  sleep 0.5
done
curl -sfI "$URL" > /dev/null 2>&1 || {
  echo "ERROR: server did not come up; see $LOG_FILE" >&2
  exit 3
}

echo "URL=$URL"
echo "BUILT=$(date -r "$APK" '+%Y-%m-%d %H:%M')"
echo "EXPIRES=$(date -d "@$(( $(date +%s) + SECONDS_TOTAL ))" +%H:%M)"
