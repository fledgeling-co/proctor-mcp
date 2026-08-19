#!/usr/bin/env bash
# Liveness. Whether the work is done and whether the agents doing it are alive
# are independent facts, and only the first one has a gate above.
#
# A ship-fleet runner works in its own worktree and commits as it goes. A
# worktree whose HEAD has not moved in STALE_MIN minutes is a runner that died
# holding a slot — the fleet then sits at its concurrency cap doing nothing,
# which reads exactly like a fleet that is busy.
#
# Two worktrees are not runners and are skipped by identity rather than by
# position: the main checkout (git worktree list's first row) and the
# integration worktree this gate is running inside.
#
# Prints what it examined, because a gate that passes on an empty population and
# a gate that passes on a healthy one must not look the same.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

STALE_MIN=${STALE_MIN:-45}
now=$(date +%s)
here=$(pwd -P)
main_wt=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
examined=0
stale=()

while read -r path _; do
  [ -d "$path" ] || continue
  real=$(cd "$path" 2>/dev/null && pwd -P) || continue
  [ "$real" = "$main_wt" ] && continue
  [ "$real" = "$here" ] && continue
  examined=$((examined + 1))
  last=$(git -C "$path" log -1 --format=%ct 2>/dev/null || echo 0)
  if [ "${last:-0}" -eq 0 ]; then stale+=("$(basename "$path"): no commits"); continue; fi
  age=$(( (now - last) / 60 ))
  [ "$age" -gt "$STALE_MIN" ] && stale+=("$(basename "$path"): HEAD ${age}m old")
done < <(git worktree list 2>/dev/null)

if [ ${#stale[@]} -eq 0 ]; then
  echo "runners: examined=$examined stale=0 (threshold ${STALE_MIN}m)"
  [ "$examined" -eq 0 ] && echo "  no runner worktrees — a pass only while none is expected"
  exit 0
fi

echo "runners: examined=$examined stale=${#stale[@]} (threshold ${STALE_MIN}m)"
printf '  %s\n' "${stale[@]}"
exit 1
