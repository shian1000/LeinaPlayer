#!/usr/bin/env bash
# Exit 0 and print "fresh" when the release APK is newer than every input that
# goes into it and carries the numbering the next build would get (tool/build_info.sh — a
# commit made since changes it); otherwise exit 1 and print why ("missing", "stale: <file>"
# or "stale: version <built> → <now>").
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
cd "$ROOT"

if [[ ! -f "$APK" ]]; then
  echo "missing"
  exit 1
fi

inputs=(lib pubspec.yaml pubspec.lock android)
[[ -d assets ]] && inputs+=(assets)
[[ -f tool/release.env ]] && inputs+=(tool/release.env)

newer="$(find "${inputs[@]}" -type f -newer "$APK" \
  -not -path 'android/.gradle/*' \
  -not -path 'android/.kotlin/*' \
  -not -path 'android/build/*' \
  -not -path 'android/app/build/*' \
  -not -name 'local.properties' \
  -print -quit)"

if [[ -n "$newer" ]]; then
  echo "stale: $newer"
  exit 1
fi

built="$(cat "${APK%.apk}.version" 2>/dev/null || echo "nieznana")"
now="$(tool/build_info.sh)"
if [[ "$built" != "$now" ]]; then
  echo "stale: version $built → $now"
  exit 1
fi
echo "fresh"
