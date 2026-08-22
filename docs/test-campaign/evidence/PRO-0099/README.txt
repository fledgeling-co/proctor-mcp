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
                            app.fledgeling.procter, taken immediately before the
                            final full suite run. 3,330 files.
operator-census-after.tsv   The same census, taken immediately after that same
                            run. 3,330 files.

                            THE PAIR AND ITS DENOMINATOR (PRO-0099 gap-fix,
                            2026-08-22). Both files come from one run of
                            scripts/campaign/operator_census.py either side of
                            one `./scripts/test.sh`, and the diff is:

                              operator census: 0 changed / 3330 file(s) swept
                              before, 3330 after

                            The pair committed by the first pass was NOT a pair.
                            It differed on audit/audit.jsonl — the live agent
                            appending to the operator's trail while the suite ran
                            — while this file claimed the diff was empty. That is
                            the exact failure this campaign keeps finding: a
                            number stated without the reading it came from. The
                            census is now a committed script rather than a shell
                            one-liner, so the pair can be re-taken identically,
                            and `--diff` prints the denominator beside the count.
sabotage-production-unchanged.txt
                            Production path resolution proved unchanged by
                            forcing the else branch with `guard false` and
                            reading the resolved path back character for
                            character against the pre-change literal.
diversion-positive.txt      The diversion shown as a presence as well as an
                            absence: the same filenames under proctor-test-*.
witness-arming.txt          CASE-0330..0332 watched failing — the path arms by
                            forcing the production branch, and (gap-fix) the
                            WRITE arms by sabotaging the divert target, with the
                            verbatim red output and the denominator of each.
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

  --- PRO-0099 gap-fix, 2026-08-22 ---
  gap-fix run 1             exit 1   2,031 tests, 1 issue, in
                                     CampaignInstrumentTests. NOT this item's
                                     code and not the operator-path work: the
                                     test-campaign skill outside this repo moved
                                     to 0.9.6, which widened
                                     `pass_uncensused` to four return values,
                                     and `seed_strengthen.py` still unpacked two.
                                     `ValueError: too many values to unpack`,
                                     reported as exit 1, reported as a red tree.
                                     Reproduced on the UNCHANGED tree — 48
                                     passed, 6 failed — so it pre-dates this
                                     work. Fixed by taking `[:2]` in
                                     seed_strengthen.py and seed_unclass.py,
                                     which is the population and the findings in
                                     every version of that signature. No check
                                     was weakened to get there.
  gap-fix run 2             exit 0   2,031 tests in 246 suites, 19.839s.
  gap-fix run 3 (final)     exit 0   2,031 tests in 246 suites, 15.803s. The two
                                     census files committed here are the pair
                                     taken either side of THIS run:
                                     0 changed / 3,330 swept before, 3,330 after.

  Production source is untouched by this gap-fix: `git diff --stat Sources/` is
  empty. Everything changed is the gate, its manifest, its fixtures, the witness
  and the record.

  campaign instruments      62 passed, 0 failed (was 48 passed, 6 failed before
                            the unpack fix; the gap-fix added 8 checks across
                            three new gate fixtures).
  operator_path_gate.py     exit 0, both modes and combined: 12 literal + 1
                            composed = 13 sites, 15 entries classed.
  defect_gate.py claims     exit 0, 5 defects claimed, all read `fixed`.
  defect_gate.py dropped    exit 0, 102 merges, 32,078 id/field pairs examined.

Every exit code was read from ./scripts/test.sh into a file rather than through a
pipe. PRO-0098 measured its own unchanged tree at exit 1, 0, 1, 0, so a red that
is not this item's own is a known property of this suite rather than a new
signal; the one seen here is named and registered rather than re-run until quiet.

THE OPERATOR'S ROOT was censused either side of runs 2, 3 and 6: 3,330 files,
0 changed, every time.
