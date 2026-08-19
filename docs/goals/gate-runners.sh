#!/usr/bin/env bash
# Liveness. Whether the work is done and whether the agents doing it are alive
# are independent facts, and only the first one has a gate above.
#
# A ship-fleet runner works in a worktree and commits as it goes. A worktree
# whose HEAD has not moved in STALE_MIN minutes is a runner that died holding a
# slot — the fleet then sits at its concurrency cap doing nothing, which reads
# exactly like a fleet that is busy.
#
# Prints what it examined, because a gate that passes on an empty population and
# a gate that passes on a healthy one must not look the same.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

STALE_MIN=${STALE_MIN:-45}
now=$(date +%s)
examined=0
stale=()

while read -r path _; do
  [ "$path" = "$(pwd)" ] && continue          # the parent is not a runner
  [ -d "$path" ] || continue
  examined=$((examined + 1))
  last=$(git -C "$path" log -1 --format=%ct 2>/dev/null || echo 0)
  age=$(( (now - last) / 60 ))
  [ "$last" -eq 0 ] && { stale+=("$(basename "$path"): no commits"); continue; }
  [ "$age" -gt "$STALE_MIN" ] && stale+=("$(basename "$path"): HEAD ${age}m old")
done < <(git worktree list 2>/dev/null)

if [ ${#stale[@]} -eq 0 ]; then
  echo "runners: examined=$examined stale=0 (threshold ${STALE_MIN}m)"
  [ "$examined" -eq 0 ] && echo "  no worktrees — no runner is alive, which is a pass only while none is expected"
  exit 0
fi

echo "runners: examined=$examined stale=${#stale[@]} (threshold ${STALE_MIN}m)"
printf '  %s\n' "${stale[@]}"
exit 1
