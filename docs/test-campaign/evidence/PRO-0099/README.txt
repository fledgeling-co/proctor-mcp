PRO-0099 — what each file here is
=================================

baseline-suite-before.txt   The full suite on the tree BEFORE this item's code
                            changes, run by the first attempt at this item.
                            Verdict: 2028 tests in 246 suites passed. (Named
                            `gate-before.txt` by that attempt, which is what it
                            was not: it is a suite log, not a gate run.)
final-suite-after.txt       The full suite on the finished tree.
                            Verdict: 2031 tests in 246 suites passed, exit 0.
operator-census-before.tsv  sha256, size, mtime, path for every regular file
                            under ~/Library/Application Support/
                            app.fledgeling.procter before the work. 3,330 files.
operator-census-after.tsv   The same census after the final suite run. 3,330
                            files, and the diff against the before-census taken
                            either side of that run is empty.
sabotage-production-unchanged.txt
                            Production path resolution proved unchanged by
                            forcing the else branch with `guard false` and
                            reading the resolved path back character for
                            character against the pre-change literal.
diversion-positive.txt      The diversion shown as a presence as well as an
                            absence: the same filenames under proctor-test-*.
witness-arming.txt          CASE-0330..0332 watched failing, and the arm that is
                            deliberately not armed, with the reason.
gate-arming.txt             operator_path_gate.py armed in both directions, and
                            the two bugs arming it found.

THE RUN TALLY
=============

  before the code changes   exit 0   2,028 tests in 246 suites
  run 1                     exit 1   2,031 tests — CASE-0332's own first draft,
                                     an assertion written against the wrong
                                     filename spelling. Fixed; see
                                     witness-arming.txt.
  run 2                     exit 0   2,031 tests in 246 suites
  run 3                     exit 0   2,031 tests in 246 suites
  run 4                     exit 1   2,031 tests — one issue, in
                                     HoldAttributionWiringTests, which this item
                                     does not touch. DEF-175, opened not fixed.
  run 5                     exit 0   2,031 tests, zero issues
  run 6 (final tree)        exit 0   2,031 tests in 246 suites, 44.640s

Every exit code was read from ./scripts/test.sh into a file rather than through a
pipe. PRO-0098 measured its own unchanged tree at exit 1, 0, 1, 0, so a red that
is not this item's own is a known property of this suite rather than a new
signal; the one seen here is named and registered rather than re-run until quiet.

THE OPERATOR'S ROOT was censused either side of runs 2, 3 and 6: 3,330 files,
0 changed, every time.
