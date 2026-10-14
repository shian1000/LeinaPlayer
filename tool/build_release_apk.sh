#!/usr/bin/env bash
# Builds the release APK numbered by tool/build_info.sh (shown in Informacje i pomoc) and leaves
# that numbering next to it in app-release.version, for check_build_fresh.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

read -r number commit < <(tool/build_info.sh)
flutter build apk --release \
  --build-number="$number" \
  --dart-define=GIT_COMMIT="$commit"
echo "$number $commit" > build/app/outputs/flutter-apk/app-release.version
