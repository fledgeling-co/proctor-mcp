# PRO-0106: Instruments that do not prove their own step

**ID:** PRO-0106
**Status:** Developer Review
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Defects:** DEF-200, DEF-205..DEF-208, DEF-215, DEF-226, DEF-227, DEF-240..DEF-247
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
  result is more useful than the assertion first written: over those six the pre-repair slice is wrong
  on **four**, not two. An untracked entry and a staged addition survive a strip intact, which is
  exactly why the defect went unnoticed and why the fixture had to be a modified tracked file. **Six
  was not the population, and "four" is a statement about the fixture rather than about the parse** —
  enumerated from the code and driven one at a time in a reset tree there are **thirteen** kinds, and
  the slice is wrong on **nine** of them: two from the strip eating a leading status space, two from a
  quoted path left quoted, and five from a rename naming both sides on one line. The four it gets
  right are the four with no leading space, no quote and no arrow. The verifier's own recount put it
  at three of eight; that enumeration is not recoverable from here and does not reproduce against this
  one, so the figure above is the measured one with its population named and every raw porcelain line
  in the selftest.
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

## What the verifier sent back, and it is this item's own subject twice

Two acceptance clauses came back `Needs More Work`, and both are the same shape: **a repair
inherited the property it was repairing.** Each fixed the path its own fixture drove and left a
sibling path carrying the original defect — which is precisely what PRO-0106 exists to stop, so
closing them is closing the item rather than patching around it.

**DEF-244 — the arming scored ARMED where zero tests ran.** The instrument's own docstring names the
three events `armed = code != 0` conflated: a setup death, a `--filter` matching nothing, and a check
firing. The repair separated the first from the third **and graded the second a pass**. Driven end to
end: CASE-0461's real, landing mutation with only its Swift function name changed produced
`[CASE-0461] ARMED … exit 1 · Test run with 0 tests in 0 suites passed`, `armed 1 of 1 ·
inconclusive 0`, process exit 0, tree clean. The started-line guard could not see it — `started` is
empty so `display is not None and started and display not in started` is skipped, and `display` was
None anyway because `display_name` correctly refused. Worse, the non-zero exit is
`scripts/test.sh`'s **own** zero-test refusal, in a block whose comment says a filter matching
nothing is not a pass: the rule was reading the harness's refusal to grade as a grade. The count is
read back out of the published verdict line now, and a verdict over zero tests is `inconclusive`
naming why, exactly as a setup death is. **Every route through `score_arming` is enumerated from the
code**, eleven of them, one fixture each, with `armed = code != 0` reintroduced against every one; it
agrees on three — a reported failure, a reported pass, and the trap — and differs on the other eight.

**DEF-245 — `porcelain_paths` re-created DEF-206 on the rename branch the repair added.** The first
repair split from the RIGHT, reasoning that an unconditional split re-creates DEF-206 on a path
containing the arrow. Splitting from the right re-creates it on a different input:
`git mv src.png "stage-1 -> stage-2.png"` gives `R  src.png -> "stage-1 -> stage-2.png"`, whose last
` -> ` is inside the quoted destination, so the parse returned `stage-2.png"` and `--allow-dirty`
wrote that phantom permanently into `run.json.dirty_inputs` — DEF-206's original harm, restored by
DEF-206's own repair. **Neither naive split survives git**, and that is the finding: the first ` -> `
is wrong when the SOURCE is quoted and holds an arrow, the last is wrong when the destination is.
Both forms were measured against git 2.50.1. The separator is findable only by reading the quoting,
so that is what `rename_destination` does — porcelain v1 quotes a path holding a space (git's own
`QUOTE_PATH_QUOTE_SP`), so an unquoted side cannot contain the separator, and a quoted side is
scanned to its closing quote honouring backslash escapes. Thirteen kinds are enumerated from
`porcelain_paths`' branches and each is driven ALONE in a reset tree, with three parses computed
against every one: the pre-repair slice (wrong on nine), the rsplit repair (wrong on exactly the two
whose last ` -> ` is inside a quoted destination), and the code as it stands (wrong on none). The
`--allow-dirty` harm is driven end to end in both directions.

## The verifier's six non-acceptance findings

Four repaired, two recorded with their reason.

| Finding | What was done |
|---|---|
| `audit()` globs `*.png` while `cite_paths` accepts twelve suffixes, so a cited `.mov` under `evidence/shots` fails as *absent from this audit* | **DEF-246, fixed.** Reproduced first. `audit()` cannot widen — `measure()` reads a PNG IHDR out of bytes 16..24 and hands the file to PIL — so the population is declared once as `AUDIT_SUFFIX`, the glob is built from it, and the citation branch reads it. A cited file outside the population is a notice, checked for existence and no further. Armed by moving the population rather than the branch: at a `.mov` population the same citation fails and the `.png` becomes the notice. |
| `cite_paths` skips any path containing a space, and any dict key | **DEF-247, fixed.** Keys are walked, and a spaced string that resolves on disk is a citation. **Residual, stated:** a citation of a MISSING file whose name holds a space still reads as prose, because that and a sentence naming a file are not separable by any rule this has. |
| `citations` checks nothing outside `evidence/shots` | **Recorded, with a correction.** Existence IS checked for every cited path wherever it lives; what is scoped to `evidence/shots/` is the disposition and the publishing subject, because a disposition is a fact about that directory and nowhere else holds one. The function now says so in its own docstring rather than leaving it to be found. DEF-243 is the row for the standard the mock lane still has no gate for. |
| `sweep()` witnesses no mode bits | **Recorded, unchanged.** A scope decision in the instrument's design rather than a step it failed to prove, and the same call as the one already recorded above. |
| gemini's ` R` unstaged-rename claim | **Does not reproduce, and now driven rather than argued.** git 2.50.1 has no rename to report until a side is staged, so a plain `mv` arrives as ` D` plus `??`. The new guard reads both status columns anyway, and the selftest records the measurement so a guard resting on an unchecked claim is not what this leaves behind. |

## Where absence claims were checked

**The `code != 0`-as-verdict pattern is not in these 25 files.** Every `.py` under `scripts/campaign/`
and `scripts/reckoning/` was grepped for a verdict taken from an exit code and every hit read in
place. The count said 27 and `git ls-tree` says **25**, at HEAD and at the merge base; the sweep is
unchanged and the number was wrong. The verifier extended it to the ten `.py` outside that window and
found one hit, `design/surfaces/tui/build_specs.py:328`, a compiler-invocation check inside
`defect_gate`'s own class rather than a verdict. `mutation_timeout_arm.py` compares scored verdicts; `skill_doc_arm.py` and
`spec_citation_arm.py` read named PASS/FAIL verdicts out of their subject's output;
`defect_gate.py` and `spec_citation_measure.py` use `returncode` only to decide whether a git
subprocess produced usable output, which is a different question. **The Swift suite was not
searched**, so this is a statement about the 35 `.py` files in the tree rather than about the
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
| DEF-244 | fixed |
| DEF-245 | fixed |
| DEF-246 | fixed |
| DEF-247 | fixed |
| DEF-243 | (recorded) `evidence/shots/mock/` is excluded from capture-lineage and from this audit's glob, both correctly and for the same reason, and nothing checks that lane at all. A disposition standard for the design of record is a different piece of work.
| DEF-215 | (recorded) four ledger rows carry no spec file. Writing retrospective specs for two retired items is a decision about those items and belongs to whoever takes it, so it is recorded open rather than closed here. |
