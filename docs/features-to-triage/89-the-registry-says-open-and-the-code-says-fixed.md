---
sources: [REQ-067, REQ-068, DEF-025, DEF-028, DEF-033]
status: retired
---
# The registry says open where the code says fixed

**Wave 14, brief 1.** Registry reconciliation plus the gate findings nobody owns. Sequence it first:
every other item's evidence is read against these registries, so a registry that lies makes the next
item's verdict unreliable.

## The measurement

`inventory.json` reports **23 open defects**. Many are fixed and merged. DEF-025 and DEF-028 are the
clearest case: PRO-0088 built and merged their fixes, its verifier confirmed them by intervention,
and both records still read `open` — on PRO-0088's own branch as well as on `ai/wave-9`, so this is
not a merge dropping the flip. The items fixed the defects and never updated the records.

The same drift hit the ledger: three rows read `Ready for AI` while their branches were already
ancestors of `ai/wave-9`. That half is repaired, by asking `git merge-base --is-ancestor` per row
rather than pattern-matching a status string, which is what let it drift.

## What to do, and the one thing not to do

**Flip a record only with the evidence that closes it.** Wholesale flipping every defect whose item
merged would raise the number and lower what the registry knows — the same failure as reclassifying
a case to clear a gate. For each of the 23, establish from source or from a run whether the defect
is actually gone, and record what settled it. A defect whose fix you cannot find stays open, and
that is a result rather than a failure.

Expect some to stay open honestly. DEF-033 (ProctorAgent's 86.4% mutant survival) is a measurement
rather than a bug, and it closes when the number moves, not when an item merges. DEF-099 and DEF-106
are recorded open deliberately.

**Then make the drift structural rather than remembered.** An item that fixes a defect should not be
able to merge without the record moving. The mechanism is a check, not an instruction: something
that reads the defects an item's spec claims to fix and refuses when a claimed one still reads
`open`. `scripts/campaign/` is where it belongs, beside `merge_registry.py`.

## The gate findings nobody owns

`campaign.py check` currently exits 1 on four things beyond the two declared `inconclusive` cases:

- **CASE-0126 and CASE-0127 carry empty `source` blocks.** They are `source-analysis` passes, and
  the rung's guard wants `source.analyzer` and an **integer** `source.examined`. Note the shape of
  the mistake already made here once: the fields were written at the top level with `examined` as
  prose, which satisfies neither condition and produced two findings against one case. The guard is
  at `campaign.py:772-781`; read it before writing.
- **Two `raster-visual` claims have no usable capture, and two have no pixel provenance.** A visual
  claim without pixels is a structural assertion in disguise. Either supply the capture and its
  channel, or move the case to the rung it actually stands on.

**One count worth holding while you work:** this gate reports *findings*, not cases. One case missing
two fields produces two findings. Reading its numbers as a case count is what caused the misreading
above.

## DEF-106, and the call this brief makes

`ProctorCoreTests.swift:232` asserts `waited < 10` on a 1s-bounded client — a wall-clock oracle,
arriving from `main`'s `10285df` through the reconciliation, after PRO-0089 had removed the last two.
CASE-0139 is `fail` because its census found it.

The choice was recorded as "delete the assertion or give `SocketClient` a clock". **Give it a
clock.** That is not a new decision: PRO-0089 established the pattern for exactly this shape —
`ScreenRecordingProbe` takes its bound timer, the test asserts the timer was asked for the bound and
reads no clock, and the bound itself never moved. `CuaLineReader` took its monotonic clock the same
way. Deleting the assertion would remove a real guarantee to satisfy an instrument; injecting the
seam keeps the guarantee and makes it measurable. Follow the precedent rather than re-deriving it.

## The conversion contract

- Each of the 23 defect records either flipped with the evidence that closed it, or left open with
  the reason.
- A check that refuses a merge whose spec claims a defect that still reads `open`, with a test that
  it catches one.
- CASE-0126 and CASE-0127 carrying `source.analyzer` and an integer `source.examined`, taken from a
  live run.
- The four `raster-visual` findings resolved by supplying provenance or by moving the rung.
- `SocketClient` takes its clock; `ProctorCoreTests.swift:232` asserts the mechanism; the bound does
  not move; CASE-0139's census returns to 0 offenders and says so with its denominator.
- `./scripts/test.sh` green with the suite count before and after.

## What this brief does not do

It does not close DEF-033, which is a measurement. It does not close DEF-099. It does not raise any
ratchet, and it does not change a case's status to clear a gate.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-067, REQ-068
- surface: SURF-022
- cases: CASE-0063, CASE-0072, CASE-0073, CASE-0150, CASE-0151, CASE-0152
- rungs reached: effect-witness, metamorphic, outcome
- provider: none
