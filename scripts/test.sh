#!/usr/bin/env bash
# Run the test suite and report the verdict honestly.
#
# Call this instead of bare `swift test` from CI and from anything that decides
# whether the tree is green. It exists because the two obvious ways to read the
# result both report a red suite as green, and both were measured on this repo.
#
# THE PIPE EATS THE EXIT CODE. `swift test` itself is correct: it exits 1 on a
# failing run, with or without `--parallel`. But almost nobody runs it bare —
# they run `swift test 2>&1 | tail -20`, and without `set -o pipefail` the shell
# reports the status of `tail`, which is 0. Measured on a run with a genuine
# failure in it:
#
#   swift test                                  rc=1
#   swift test --parallel                       rc=1
#   swift test 2>&1 | tail -3                   rc=0
#   swift test 2>&1 | grep -c Expectation       rc=0
#
# That is the whole of the reported "swift test exits 0 on failure". So: pipefail
# is on, and the runner is not on the left of a pipe at all — its output goes to a
# file and the verdict is read back from the file afterwards.
#
# THE XCTEST LINE IS NOT THE VERDICT. Every run of this package, including a
# failing one, prints:
#
#   Executed 0 tests, with 0 failures (0 unexpected) in 0.000 seconds
#
# That is the XCTest half of the runner reporting on the zero XCTest cases in the
# package. The tests are swift-testing, and their verdict is the line reading
# `Test run with N tests in M suites passed` or `... failed`. A gate grepping the
# XCTest line reads green on a red suite, every single time.
#
# AN ABSENT VERDICT IS A FAILURE. A run that crashed before reporting, or whose
# filter matched nothing, has not passed. Note that `swift test --filter` matches
# the Swift FUNCTION name and not the `@Test` display string, so a filter written
# against the display string runs zero tests — which this refuses rather than
# calling green.
#
# Usage:
#   scripts/test.sh                       whole suite
#   scripts/test.sh --filter FooTests     passed straight through to swift test
#
# Env:
#   PROCTOR_TEST_LOG   where to write the captured output
#                      (default: a temp file, removed on success)

set -euo pipefail

log="${PROCTOR_TEST_LOG:-$(mktemp -t proctor-test)}"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"

echo "==> swift test ${*:-} (output: $log)"

# Not on the left of a pipe. `tee` would hand us its own status even under
# pipefail's cousin, and the point of this script is that no reader of the
# result depends on a pipeline at all.
set +e
swift test "$@" >"$log" 2>&1
runner_rc=$?
set -e

cat "$log"

# The swift-testing verdict. `--parallel` and a plain run both emit it; a suite
# that failed emits the `failed` spelling.
verdict="$(grep -E 'Test run with [0-9]+ test' "$log" | tail -1 || true)"

if [ -z "$verdict" ]; then
    echo
    echo "FAIL: no swift-testing verdict line in the output."
    echo "      Either the run died before reporting, or a --filter matched no"
    echo "      tests. --filter matches the Swift function name, not the @Test"
    echo "      display string. An absent verdict is not a pass."
    exit 1
fi

if [ "$runner_rc" -ne 0 ]; then
    echo
    echo "FAIL: swift test exited $runner_rc"
    echo "      $verdict"
    exit "$runner_rc"
fi

# ZERO TESTS IS NOT A PASS, and this is the trap that catches people. A filter
# that matches nothing produces a real, well-formed verdict line reading
#
#   Test run with 0 tests in 0 suites passed
#
# which every naive parse of this line — including the first draft of this
# script — reports as green. `--filter` matches the Swift function name, so a
# filter written against a `@Test` display string matches nothing and lands here.
count="$(printf '%s' "$verdict" | sed -n 's/.*Test run with \([0-9][0-9]*\) test.*/\1/p')"
if [ "${count:-0}" -eq 0 ]; then
    echo
    echo "FAIL: the run executed 0 tests, which is not a pass."
    echo "      $verdict"
    echo "      --filter matches the Swift function name, never the @Test"
    echo "      display string."
    exit 1
fi

case "$verdict" in
    *failed*)
        echo
        echo "FAIL: the runner exited 0 but the verdict says otherwise."
        echo "      $verdict"
        exit 1
        ;;
    *passed*)
        echo
        echo "PASS: $verdict"
        [ -n "${PROCTOR_TEST_LOG:-}" ] || rm -f "$log"
        exit 0
        ;;
    *)
        echo
        echo "FAIL: could not read a pass or fail from the verdict line."
        echo "      $verdict"
        exit 1
        ;;
esac
