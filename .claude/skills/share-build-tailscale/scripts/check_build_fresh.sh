#!/usr/bin/env bash
# Exit 0 and print "fresh" when the release APK is newer than every input that
# goes into it; otherwise exit 1 and print why ("missing" or "stale: <file>").
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
echo "fresh"
