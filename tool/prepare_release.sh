#!/usr/bin/env bash
# Gets the APK for a GitHub release ready: builds it when the existing one isn't current,
# refuses a build with uncommitted changes or without tool/release.env, copies the universal APK
# to build/release/LeinaRadio-<version>+<build>.apk and the arm64 one to …-arm64-v8a.apk, and
# prints the tag the app's update check expects (<version>+<build>, docs/agent-notes/releases.md).
# Publishing is done by hand.
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

# The universal APK (app-release.apk) is reused when it's current; the split ones are always
# built — Flutter makes no universal APK in a split build, so these are two builds.
if ! .claude/skills/share-build-tailscale/scripts/check_build_fresh.sh >/dev/null; then
  tool/build_release_apk.sh
fi

version="$(sed -nE 's/^version: *([^+ ]+).*/\1/p' pubspec.yaml)"
tag="$version+$number"
mkdir -p build/release
rm -f build/release/LeinaRadio-"$tag"*.apk
universal="build/release/LeinaRadio-$tag.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$universal"

tool/build_release_apk.sh --split-per-abi
arm64="build/release/LeinaRadio-$tag-arm64-v8a.apk"
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$arm64"

echo "TAG=$tag"
echo "APK_UNIVERSAL=$universal"
echo "APK_ARM64=$arm64"
echo "COMMIT=$commit"
