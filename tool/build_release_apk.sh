#!/usr/bin/env bash
# Builds the release APK numbered by tool/build_info.sh (shown in Informacje i pomoc) and leaves
# that numbering next to it in app-release.version, for check_build_fresh.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f android/key.properties && -z "${ALLOW_DEBUG_KEY:-}" ]]; then
  echo "android/key.properties missing: the APK would be signed with the debug key and could not" >&2
  echo "update one installed from a release (docs/agent-notes/signing.md). ALLOW_DEBUG_KEY=1 to build anyway." >&2
  exit 1
fi

read -r number commit < <(tool/build_info.sh)
flutter build apk --release \
  --build-number="$number" \
  --dart-define=GIT_COMMIT="$commit"
echo "$number $commit" > build/app/outputs/flutter-apk/app-release.version
