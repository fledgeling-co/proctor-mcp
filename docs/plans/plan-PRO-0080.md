# Plan — PRO-0080: two gates nobody has watched fail

**Spec:** `docs/specs/spec-PRO-0080.md` · **Branch:** `ai/pro-0080` off `ai/wave-9`
**Tier:** Standard. No product code changes; instrument work, a measurement, and new tests.

## Ordering, and why it is forced

`mutate_swift.py` refuses to start on a dirty tree and compiles the whole package per mutant from
the working directory, so **the tree must be clean for the whole run and no edit may land while it
is in flight.** That inverts the usual order: everything that edits the tree either happens before
the run or after it, and the run sits in the middle as a barrier.

| Phase | Edits tree? | Work |
|---|---|---|
| 0 | yes | Spec, plan, `seed_unclass.py`. Commit. Tree clean. |
| 1 | no | Item 1's two controls (they restore byte-for-byte). Item 3's reconciliation read. |
| 2 | **barrier** | The `ProctorAgent` mutation sample. Nothing else touches the worktree. |
| 3 | yes | Killing tests for survivors, `REPORT.md`, registry rows, brief correction. |
| 4 | yes | Re-run the four gates, regenerate `evidence.html`, `export-warrant`. |

Phase 1 runs before the barrier because both controls write `inventory.json` and restore it, and a
restore that raced the mutation run's `git status` check would abort the run for a reason nobody
could see.

## Phase 1 — the census controls

Run and capture verbatim; the transcript is the artifact, not a summary of it.

1. Read the census **before** anything is seeded: `vacuity-check.py docs/test-campaign --gate`.
   `before=clear` in the control's own output is only load-bearing if the census was clear, so this
   reading is what makes both runs mean something.
2. `--seed-strengthen REQ-017` — external, `subprocess`, witnessed by PRO-0077.
3. `--seed-strengthen REQ-001` — classed `none`.
4. SHA-256 `inventory.json` before and after; `git diff` must be empty.
5. Per-pass decomposition of what the seeded mutation fires, to establish whether both census
   passes are covered. **Expected finding:** only `uncensused`. If the decomposition instead shows
   `unclassed` firing, step 6 is dropped and DEF-030 is not written — the check drives the finding,
   not the other way round.
6. `seed_unclass.py docs/test-campaign REQ-017` — the missing direction. Its refusal arm is proved
   separately against a requirement the vocabulary cannot hit, so the control is known to be able
   to decline rather than only to pass.

## Phase 2 — the mutation barrier

**Targets.** All 84 `Sources/ProctorAgent/**/*.swift`, so the denominator is the whole package
rather than a hand-picked subset that would flatter the rate. Pool measured at 3,189 sites.

**Command.**

```
python3 scripts/campaign/mutate_swift.py \
  --targets $(find Sources/ProctorAgent -name '*.swift' | sort) \
  --count 24 --seed 20260821 --timeout 600 \
  --out docs/test-campaign/evidence/mutation-agent.json
```

`--out` is a new filename. It does not overwrite `mutation-survival-core.json`, which is the
`ProctorCore` measurement and a different population.

**Load is recorded at the start**, because a timeout is scored as a kill and a kill under
contention is not trustworthy. Load at planning time was 11.20 (1-min), the best window today
against a range of 11 to 266. Per-mutant wall-clock seconds are kept in the artifact so a reader
can separate a fast kill from one that may be a timeout.

**Run in the background and polled.** A foreground run is silent long enough to get the agent
killed, and `sleep` in the foreground is blocked by the harness and orphans `swift-test` processes
holding the `.build` lock.

**Recovery.** The script reverts on `atexit`, `SIGTERM` and `SIGINT`, and writes its artifact every
mutant so a killed run still reports what it scored. If it dies anyway, `git status --porcelain`
plus `git checkout -- Sources/ProctorAgent` is the first thing done before anything else is read.

## Phase 3 — survivors

Each survivor is triaged into exactly one of three, and the distinction is kept sharp because
conflating them reports a coverage hole as a mathematical impossibility:

- **killable** — write the test. It goes in the matching `Tests/ProctorAgentTests` file, asserts
  the behaviour rather than the mutant, and never asserts a value the test itself wrote (this repo
  shipped that once, as DEF-019).
- **equivalent** — argued in the report, not asserted. Out-of-scope to chase.
- **uncovered-by-lane** — the site needs a window server or a TCC grant the headless lane lacks.
  A different claim from equivalent, and recorded as such.

**Arming each new test.** A test written to kill a mutant that was never watched failing is the
defect this whole item is about. So per killing test: re-apply that one mutant by hand, run
`./scripts/test.sh --filter <name>`, record the test red, revert the mutant, record it green. That
is a tree edit and therefore strictly after the barrier.

**Registry.** `CASE-0072..0079`, `DEF-030..034`, `REQ-046..047` — the allocated ranges, nothing
discovered. Rows appended in the file's own format; if `campaign.py add` reindents
`inventory.json`, revert and append by hand. If the ranges run short, that is reported rather than
extended.

## Phase 4 — gates

`./scripts/test.sh` owns the verdict and the verdict is its **exit code**; a bare `swift test`
exits 1 while reporting every test passing, so no XCTest summary line is read as a result. Then
`campaign.py check`, `strict-check.py`, `capture-lineage.py --gate`, `vacuity-check.py --gate`,
each with its exit code recorded, then `evidence-page.py` and `export-warrant`.

`campaign.py check` is expected to **exit 1** on PRO-0083's ten unwitnessed requirements. That is
recorded here in advance so it cannot be re-read after the fact as either a pass or a regression
this item caused.

## Risks

| Risk | Handling |
|---|---|
| Machine load spikes mid-run and turns survivors into false kills | Survivors stay trustworthy under load; only kills degrade. Per-mutant seconds kept; load recorded at start and end. |
| The sample lands entirely in display-only files and every survivor is `uncovered-by-lane` | Reported as measured. A sample that found nothing killable is a finding about the lane, not a failure to deliver. |
| Survivor count exceeds what the item can write tests for | Report the count, kill what the lane can reach, record the rest with reasons. A partial sample honestly reported is the deliverable. |
| `DEF-030..034` is five ids and the survivors imply more | Say so in the report rather than taking the next free id. |
