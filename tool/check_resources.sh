#!/usr/bin/env bash
# Checks this machine has room for heavy work (a Gradle build, a full test suite) before
# starting it: available RAM, swap in use, and the heavy development processes already running
# with the project each one works in — other Claude sessions run builds and tests of their own
# projects on the same 7.3 GB (the 2026-11-18 freeze).
#
# Usage: tool/check_resources.sh [needed MB, default 2500]
# Exit 0: enough. Exit 1: not enough — the output says what holds the memory; don't start the
# work, show it to the user and let them decide (never kill processes that aren't yours).
set -uo pipefail

NEED_MB="${1:-2500}"
SWAP_LIMIT_PCT=80

read -r avail_mb < <(free -m | awk '/^Mem:/ {print $7}')
read -r swap_total swap_used < <(free -m | awk '/^Swap:/ {print $2, $3}')
swap_pct=0
(( swap_total > 0 )) && swap_pct=$(( swap_used * 100 / swap_total ))

echo "RAM available: ${avail_mb} MB (needed: ${NEED_MB} MB)"
echo "Swap used: ${swap_used} / ${swap_total} MB (${swap_pct}%)"

# Heavy processes from Flutter/Android work and Claude, with the folder each runs in.
echo "Heavy processes (RSS MB, PID, name, folder):"
ps -eo pid=,rss=,comm= --sort=-rss | while read -r pid rss comm; do
  case "$comm" in
    java|dart*|flutter_tester|frontend_server*|qemu*|emulator*|claude|claude-desktop|kotlin*|gradle*) ;;
    *) continue ;;
  esac
  mb=$(( rss / 1024 ))
  (( mb < 100 )) && continue
  cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null || echo '?')"
  if [[ "$comm" == java ]]; then
    args="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"
    [[ "$args" == *GradleDaemon* ]] && comm="java (Gradle daemon)"
    [[ "$args" == *KotlinCompileDaemon* ]] && comm="java (Kotlin daemon)"
  fi
  printf '  %6s  %7s  %-24s %s\n' "$mb" "$pid" "$comm" "${cwd/#$HOME/\~}"
done

ok=1
if (( avail_mb < NEED_MB )); then
  echo "NOT ENOUGH: ${avail_mb} MB available, ${NEED_MB} MB needed."
  ok=0
fi
if (( swap_pct >= SWAP_LIMIT_PCT )); then
  echo "NOT ENOUGH: swap is ${swap_pct}% full — the machine is already short of memory, more work makes it freeze."
  ok=0
fi
if (( ok )); then
  echo "OK"
  exit 0
fi
exit 1
