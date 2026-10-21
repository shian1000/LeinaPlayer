#!/usr/bin/env bash
# Gets the APK for a GitHub release ready: builds it when the existing one isn't current,
# refuses a build with uncommitted changes or without tool/release.env, copies it to
# build/release/LeinaRadio-<version>+<build>.apk and prints the tag the app's update check
# expects (<version>+<build>, docs/agent-notes/releases.md). Publishing is done by hand.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f tool/release.env ]]; then
  echo "tool/release.env missing: a release build must know its repository (tool/release.env.example)." >&2
  exit 1
fi
if [[ ! -f android/key.properties ]]; then
  echo "android/key.properties missing: a release must be signed with the release key." >&2
  exit 1
fi

read -r number commit < <(tool/build_info.sh)
if [[ "$commit" == *+zmiany ]]; then
  echo "Uncommitted changes in lib/, android/ or pubspec: commit them first, a release is built from a commit." >&2
  exit 1
fi

if ! .claude/skills/share-build-tailscale/scripts/check_build_fresh.sh >/dev/null; then
  tool/build_release_apk.sh
fi

version="$(sed -nE 's/^version: *([^+ ]+).*/\1/p' pubspec.yaml)"
tag="$version+$number"
mkdir -p build/release
apk="build/release/LeinaRadio-$tag.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$apk"

echo "TAG=$tag"
echo "APK=$apk"
echo "COMMIT=$commit"
