#!/usr/bin/env bash
# Run one filter N times and count how many runs failed.
#
# Scratch instrument for PRO-0054, not a gate. It exists because "this passes
# now" is not evidence about a race: the question is always what fraction of
# runs fail, and at what machine load, and nobody can answer that by eye.
#
# It calls scripts/test.sh rather than `swift test`, so the verdict it counts is
# the honest one, and it keeps the runner off the left of a pipe for the reason
# that script's own header gives.
#
# Usage:
#   scripts/measure-flake.sh <label> <runs> [--filter Foo ...]
#
# Prints one line per failing run and a summary carrying the load average
# before and after, because a flake measured on a quiet machine is a flake
# measured under the conditions least likely to show it.

set -uo pipefail

label="$1"; shift
runs="$1"; shift

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"

outdir="${PRO0054_OUT:-/tmp/pro0054}/$label"
mkdir -p "$outdir"

load_before="$(sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1}')"
failures=0
first_failure=""

for i in $(seq 1 "$runs"); do
    log="$outdir/run-$i.log"
    PROCTOR_TEST_LOG="$log" ./scripts/test.sh "$@" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        failures=$((failures + 1))
        echo "  run $i FAILED (rc=$rc)"
        grep -E 'Expectation failed|recorded an issue' "$log" | head -3 | sed 's/^/      /'
        [ -z "$first_failure" ] && first_failure="$log"
    else
        rm -f "$log"
    fi
done

load_after="$(sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1}')"

echo "$label: $failures failures in $runs runs (load $load_before -> $load_after)"
[ -n "$first_failure" ] && echo "  first failing log: $first_failure"
exit 0
