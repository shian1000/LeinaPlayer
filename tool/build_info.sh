#!/usr/bin/env bash
# Prints "<build number> <commit>" for the next build: the number of commits (Android needs a
# higher versionCode for each update) and the short commit hash, with "+zmiany" when the files
# that go into the APK differ from that commit.
set -euo pipefail
cd "$(dirname "$0")/.."

number="$(git rev-list --count HEAD)"
commit="$(git rev-parse --short HEAD)"
inputs=(lib pubspec.yaml pubspec.lock android)
[[ -d assets ]] && inputs+=(assets)
if [[ -n "$(git status --porcelain -- "${inputs[@]}")" ]]; then
  commit="$commit+zmiany"
fi
echo "$number $commit"
