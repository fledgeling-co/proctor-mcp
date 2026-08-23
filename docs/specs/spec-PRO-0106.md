# PRO-0106: Instruments that do not prove their own step

**ID:** PRO-0106
**Status:** Developer Review
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Defects:** DEF-200, DEF-205..DEF-208, DEF-215, DEF-226, DEF-227, DEF-240, DEF-241, DEF-242, DEF-243
**Brief:** `docs/features-to-triage/99-instruments-that-do-not-prove-their-own-step.md`

## Feature description

Four defects in three instruments, all of the form *the tool performed a step and published the result
without establishing the step happened*. `mutate_swift.py` splices by byte offset and never reads back
(DEF-207); `mutation_seam_arm.py` scores `armed = code != 0`, so a process dying in setup counts as red
(DEF-208); `cmd_take` stores filenames while `sweep()` computed digests, so the witness cannot say what
was in the files (DEF-205); and `resolve_tree` prints a path missing its first character in its own
refusal, writing that phantom permanently into `run.json.dirty_inputs` under `--allow-dirty` (DEF-206).

## What and why

DEF-207 is the worst of the four and the reason is worth stating precisely. An anchor-string mutator
that aborts at least **reports** INERT, so something in the log disagrees with the verdict. An
unconditional splice by byte offset writes regardless, so there is nothing to report and **a
wrong-offset write is silent** — the harness grades pristine or wrongly-edited code and nothing
anywhere contradicts it. **A survivor has two readings: the guard is decorative, or the mutation never
happened.** PRO-0092's twenty survivors were each shown to land by a verifier reconstructing all 24
mutants against the tree the run used; that is a verifier's proof, not the instrument's, and the next
sample does not get one.

The repair for DEF-207 is porting a check this same repository already contains: its sibling arm
asserts an occurrence count of 1 and re-reads, requiring `after` present and `before` gone.

## Acceptance sketch

- Every instrument proves its own step before grading the outcome: the edit is read back, the artifact
  is opened, the verdict line is confirmed to exist.
- Where a step cannot be proved, the result is `inconclusive` naming why, rather than a pass or a fail.
- An arming with no verdict line is `inconclusive`, not armed — a process that died in setup is not a
  test that failed.
- The witness stores what `sweep()` already computes.
- An instrument's own refusal message is part of its output and carries a test.

## Assumptions made writing this

- Assuming an instrument owes the same standard it applies to its subject: a mutation harness demanding
  a test prove itself, while not proving its own edit, is holding its subject to a rule it does not keep.
- Assuming DEF-200 and DEF-215 ride along as smaller separate rows rather than justifying their own
  item: arming CASE-0392 with an artifact closes one, and the other is a decision about two retired
  items rather than a repair.

## Two more, opened after this spec was written

**DEF-226.** `shot_disposition.py --write` adopted any new content as the baseline. A flat magenta
frame over `surf-007-zoom.png` took the check to exit 1, and `--write` returned it to 0 with the row
still recording `publishedAs: SURF-007` and `distinctRGBA: 1`. That is DEF-207's shape one level on: a
step that performs an action and then treats its own result as the standard, with nothing able to
disagree.

**DEF-227,** and the sharpest of the six. The same instrument checked `captures.json` against the disk
and **never read `cases.json`**, so a case citing an unpublished, misnamed or absent image was
invisible to it. DEF-224 and DEF-225 are both instances of a class the instrument cannot see — which
is why both were found by a person reading rather than by a gate running.

## What was delivered

Six repairs, each armed on its own fixture, because a fixture covering two of them together proves
neither individually.

| Defect | The step it did not prove | What proves it now |
|---|---|---|
| DEF-207 | `apply()` spliced by byte offset and returned nothing | The bytes at the recorded offsets must equal the recorded `before`, and the file re-read from disk must equal the spliced text **exactly** — not `after in reread`, which a file already holding that token elsewhere would satisfy while the splice went somewhere else. A mutant failing either is `inconclusive`, out of the denominator, and the suite is not run for it. |
| DEF-208 | `armed = code != 0` read three events as one | The verdict comes from swift-testing's own lines. A trap is armed only when the log shows the named test started and never finished, and the display string is read out of the Swift source. Everything else is `inconclusive`, at exit 3 rather than 1. |
| DEF-205 | `cmd_take` stored names where `sweep()` had digests | The effect block carries bytes and sha256 per file written, plus the before-and-after pair for any file **rewritten** between sweeps — the case a name-only witness could not see at all. |
| DEF-206 | `git()` stripped, and `[3:]` ate the first character | Porcelain lines parse through `git_raw`, with a rename resolved to its destination and a quoted path unquoted. |
| DEF-226 | `--write` took its own re-measurement as the standard | A rewrite must be named: `--adopt <file>`, one at a time. There is no blanket flag, because a flag that adopts everything is the hole. |
| DEF-227 | The gate never read `cases.json` | Every cited image is checked three ways. The nine rows DEF-224 and DEF-225 already record are named rather than failed, and an entry that stops reproducing prints as resolved rather than reding on the fix. |

**DEF-200** closed without a change to the check. CASE-0392 was armable all along; the flag stayed down
because the probe that showed it left no artifact. The design's refusing primary was redrawn in the
accent fill, `WalkthroughFlowTests.theDesignDrawsTheRefusingPrimaryPlain` red at line 397, and the
artifact is kept.

## What the item found in its own work

**DEF-240**, and it is DEF-208's shape inside `mutate_swift.py` rather than beside it. `run_suite`
read `p.returncode == 0` as the whole verdict once a build error was ruled out, so a runner that died
after linking and before printing anything scored `failed` and then `killed` — the direction that
flatters the suite, because it credits the tests with catching a fault they were never run against.
Repaired here: a non-zero exit with no `Test run with N tests` line is `inconclusive`.

**A check that could not fire, found by arming it.** `display_name`'s ambiguity refusal armed as a
no-op on the first pass: no function under this repository's `Tests/` resolves two ways, so nothing in
the tree could make that branch fire. It was given a `tests_root` and a fixture — two files declaring
one function under different `@Test` names. It is recorded here rather than as a defect row because it
never shipped; it was written and armed inside this item, and a ledger row for a fault that existed
for twenty minutes inside one branch would be noise. Worth stating anyway, because it is this item's
own principle turning on this item: a check nobody has watched fire is indistinguishable from a check
that cannot.

**A citation the recorded set did not cover.** DEF-227's new check first fired on
`evidence/shots/mock/surf-008-status-window.png`, cited by CASE-0039 and absent from the audit's
population. Not a fault: `capture-lineage.py` excludes any path with a `mock` directory component for
the same reason, and CASE-0039 cites the mock and the capture side by side, which is the comparison.
The `mock/` lane is checked for existence only, and the exclusion says why.

**DEF-241**, found by asserting a count instead of reading it. The audit's own sentence said "none of
those **eleven** files is any subject's shot"; the four byte-identical groups cover **ten**, and the
instrument's own `redundantFiles` field says 6, which agrees with the data rather than with the
sentence. Both that number and "the smallest is 10,680" beside it were literals inside a string the
instrument writes into the published audit — a claim nothing re-derives, in the file whose whole
argument is that a claim nothing re-derives is an opinion. Both are built from the rows now, and a
check asserts the published sentence states the count that run computed.

**DEF-242**, and it is a gate that had been red on `main` since the change it measures was merged.
`mutation_timeout_arm.py --baseline-ref` defaulted to `main`, which absorbed PRO-0092's timeout fix at
that merge, so the gate loaded the same file twice and reported `before=TIMEOUT after=TIMEOUT`. Checked
on two trees rather than argued: identical exit 1 on a clean detached worktree of `main` and on this
branch. Nothing noticed because this gate is not in the per-merge list — the same gap that let
`capture-lineage` sit red across three trees before PRO-0107. Pinned to `fc1b9a4~1`, and it now arms at
exit 0 with `before=killed scored=1 survivalRate=0.0` against `after=TIMEOUT scored=0 survivalRate=None`.

## The failure mode this item was warned about, and what the audit found

`main` named it while this was in flight: *a repair that proves the step on the path the harness
exercises while leaving another path undriven*. Four paths were undriven, and each is now driven with
the original defect reintroduced on it.

- **`porcelain_paths` accepts six kinds of status entry and one was driven.** All six now, and the
  result is more useful than the assertion first written: the pre-repair slice is wrong on **four**,
  not two. An untracked entry and a staged addition survive a strip intact, which is exactly why the
  defect went unnoticed and why the fixture had to be a modified tracked file.
- **The witness had two kinds of change and there are three.** Under `--force` a re-take runs over a
  directory that already holds a reading, and a file the build stopped writing leaves no trace in
  either name set. `removed` records it.
- **`mutation_seam_arm.py` has its own `apply()`**, with its own occurrence-count and read-back check,
  and nothing was driving it. Both halves are driven to refuse now, and the passing direction in the
  same run.
- **`--manifest` is a second output path** emitting digests and byte counts that nothing checked
  against the disk. All 35 entries are re-derived.

The open question `main` recorded is answered rather than left: byte-identity grouping is what DEF-221
and DEF-222 rest on, and nothing would have failed if it silently stopped grouping. `verify()` now
fails on a change to it.

## The out-of-family review, and what survived checking

`gemini-3.7-flash-high` via `agy --new-project --dangerously-skip-permissions` from `/tmp`. It answered
about PRO-0106, citing this item's own files, so the lane held. **Six findings survived checking and
are repaired; two did not and are recorded here rather than acted on.**

Repaired:

1. **`apply()` proved a valid splice, not the intended one.** An edit above can slide a different `==`
   into exactly the recorded offset — the offset check agrees, the read-back agrees, and the verdict is
   attributed to a line nothing touched. The recorded line number is a second coordinate on the same
   site, and the two move independently. A no-op mutation is refused too.
2. **`revert()` was `check=True` and nothing else** — a fact about the git command rather than about
   the file, which is DEF-207's own distinction one call further down. It reads the span back, and the
   run stops rather than grading later mutants against a tree nobody chose.
3. **A trap needs exactly one started test.** swift-testing runs tests concurrently unless a suite is
   serialized, so two started lines with no completions cannot say which died. A verdict line for a run
   that never started the named test is inconclusive too.
4. **`display_name` guessed `function()`** when an `@Test` did not open with a display string. A
   guessed name never matches the log, so a real arming becomes a silent mismatch; it refuses instead.
5. **`porcelain_paths` split on `" -> "` unconditionally**, re-creating DEF-206 on any path containing
   the arrow. Gated on an `R`/`C` status and split from the right.
6. **Three more routes into the baseline**: a new file whose stem already carried a disposition written
   for other bytes, a file that left the directory, and deleting the audit outright. Plus `cite_paths`
   reading `.png` alone, and a pinned baseline ref that does not resolve in a shallow clone.

Did not survive:

- **"`run_suite` classifies the DEF-240 fixture as `build-failed` before reaching the verdict-line
  test."** The review quoted a `run_suite` body this file does not contain. The real guard is
  `if "error:" in out and "Build complete" not in out`, and the fixture carries `Build complete!`, so
  it reaches `no-verdict-line`. Checked against the file rather than the quotation.
- **"Character offsets may diverge from UTF-8 byte offsets."** `candidates()` and `apply()` both index
  the same `path.read_text()` string, so the two coordinate systems are one. The concern assumes an
  external AST emitting byte offsets, which is not where these mutants come from.

What it raised and this item is **not** closing: `sweep()` witnesses bytes and digests and not mode
bits, and `cmd_take` sweeps only its own output directory, so a write elsewhere is unwitnessed. Both
are scope decisions in the instrument's design rather than steps it failed to prove. And **DEF-243**,
recorded rather than fixed.

## Where absence claims were checked

**The `code != 0`-as-verdict pattern is not in these 27 files.** Every `.py` under `scripts/campaign/`
and `scripts/reckoning/` was grepped for a verdict taken from an exit code and every hit read in
place. `mutation_timeout_arm.py` compares scored verdicts; `skill_doc_arm.py` and
`spec_citation_arm.py` read named PASS/FAIL verdicts out of their subject's output;
`defect_gate.py` and `spec_citation_measure.py` use `returncode` only to decide whether a git
subprocess produced usable output, which is a different question. **Nothing outside `scripts/` was
searched and the Swift suite was not**, so this is a statement about 27 files rather than about the
repository.

**The strip-then-slice pattern is not in the other three instruments.** `mutate_swift.py` and
`mutation_seam_arm.py` both slice `line[3:]` off `subprocess.run(...).stdout` without stripping,
which is correct; `reckoning.py` was the only one routing porcelain through a stripping helper.
Searched: the four instruments this item names, plus every `git status --porcelain` call under
`scripts/`.

## Defects

| Defect | State |
|---|---|
| DEF-200 | fixed |
| DEF-205 | fixed |
| DEF-206 | fixed |
| DEF-207 | fixed |
| DEF-208 | fixed |
| DEF-226 | fixed |
| DEF-227 | fixed |
| DEF-240 | fixed |
| DEF-241 | fixed |
| DEF-242 | fixed |
| DEF-243 | (recorded) `evidence/shots/mock/` is excluded from capture-lineage and from this audit's glob, both correctly and for the same reason, and nothing checks that lane at all. A disposition standard for the design of record is a different piece of work.
| DEF-215 | (recorded) four ledger rows carry no spec file. Writing retrospective specs for two retired items is a decision about those items and belongs to whoever takes it, so it is recorded open rather than closed here. |
