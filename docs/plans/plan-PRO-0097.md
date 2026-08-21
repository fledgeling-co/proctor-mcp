# Plan — PRO-0097: the registry says open where the code says fixed

**Spec:** `docs/specs/spec-PRO-0097.md` · **Tier:** Standard · **Branch:** `ai/pro-0097`
**Gate:** `./scripts/test.sh` (baseline 1,934 tests in 236 suites, exit 0) plus
`campaign.py check` and `scripts/campaign/wall_clock_census.py`.

## Order, and why it is this order

The reconciliation lands first because every other item in the wave reads its evidence against these
registries. Then the mechanism that keeps them honest, then the gate findings, then DEF-106.

## Slice 1 — reconcile the 23, and restore what merges dropped

Read each open defect against the tree rather than against the item that claimed it. The
dispositions, each with what settled it:

**Flipped, fix present in source on this branch (12).** DEF-025 and DEF-028 (`FrameContent.swift`
content gate, `CursorOverlay.swift:98` sharing type through `place`, recorded as DEF-097 and
DEF-095); DEF-029 and DEF-051 (`ScreenRecordingProbeWiringTests` asserts the injected timer, no
`elapsed <` remains); DEF-030 (`seed_unclass.py` supplies the second census pass); DEF-032
(`mutate_swift.py` lookbehind excludes `$0`); DEF-035 (`StatusSurface.Copy.toolsNote` and
`toolsNoteInDesign`, both read by `MainWindow`); DEF-042 (`PolicyStore.live` behind
`AuditLog.isTestProcess`); DEF-043 (→ DEF-100, `verifyOffThePool` on its own `Thread`); DEF-044
(→ DEF-050, single-flight through `waiting`); DEF-055 (CASE-0074 reads 22.92); DEF-057
(CASE-0102..0105 on `source-analysis` with their source blocks); DEF-058 (FLOW-010 present);
DEF-041 (0.9.4 prints the denominator beside every capped list).

**Flipped by restoring the value a merge dropped (1).** DEF-040 — PRO-0091 recorded REQ-024
`vacuous` at `6e5094e` and `f509842` took ours.

**Left open with the reason (7).** DEF-026, DEF-027 (PRO-0093 is `Ready for AI`); DEF-037, DEF-039,
DEF-056 (PRO-0090 is `Ready for AI`, and DEF-039 re-measured live at 71 of 91); DEF-033 (a survival
rate, closes when the number moves); DEF-099 (excluded by the brief, with the measurement that it
no longer holds recorded in its note rather than acted on).

Restore the eleven dropped values from the commits that set them. Write
`evidence/PRO-0097/defect-reconciliation.md` — one row per defect, its disposition and what settled
it — and `evidence/PRO-0097/dropped-values.txt` from a live run of the detector below.

## Slice 2 — `scripts/campaign/defect_gate.py`, beside `merge_registry.py`

Two subcommands, both exiting non-zero on a finding.

- `claims <spec.md> <registry-dir>` — parses the spec's `**Defects:**` line and its `## Defects`
  table, and refuses when a claimed defect still reads `open`. This is REQ-067's mechanism.
- `dropped <registry-dir>` — walks non-merge ancestor commits of HEAD, and reports every
  `id.field` a commit set that HEAD does not carry and whose HEAD value equals the value that
  commit's parent held. That last clause is what separates a merge dropping a value from an item
  legitimately changing one.

Both get gate tests in `scripts/campaign/test_instruments.py`, which
`Tests/ProctorCoreTests/CampaignInstrumentTests.swift` runs, so `./scripts/test.sh` owns the
verdict. Each is armed in both directions on a fixture: `claims` against a registry holding an
`open` defect the spec claims, and `dropped` against a throwaway git repository built to hold one
dropped value and one legitimate change, so a check that cannot fire is distinguishable from one
that found nothing.

## Slice 3 — the gate findings

- CASE-0126, CASE-0127: run `status_literals.py`'s analogue for each — the analyzer that ran and the
  file count it ran over — and write `source.analyzer` and an integer `source.examined` inside the
  `source` block, which is where the guard at `campaign.py:772-781` reads them.
- CASE-0124, CASE-0125: move to `outcome`. Neither measures pixels off a display server.
- CASE-0128, CASE-0129: witness blocks from `evidence/PRO-0088/glass/*.json` — recorder, effect
  class from the closed list, count read out of the file rather than asserted.
- REQ-055, REQ-063: recorded as DEF-110 and DEF-111. Building either witness is an item's work.

## Slice 4 — DEF-106

`SocketClient` takes the socket-option setter it spends its bound through, defaulted to
`setsockopt`. `ProctorCoreTests.swift:232` keeps its real listener, its real `agentUnavailable` and
its real message, drops `started`/`waited` entirely, and asserts the applier was asked for
`tv_sec == ioTimeoutSeconds` on both `SO_RCVTIMEO` and `SO_SNDTIMEO`. `ioTimeoutSeconds` stays 1.
A second case covers the seam's default so the injected path is not the only one exercised.

Then `wall_clock_census.py --arm` and a live run: 0 offenders with the denominator printed, armed at
2 of 2. CASE-0139 returns to `pass` with the run's own numbers.

## Test strategy

| Clause | Seam | Check |
|---|---|---|
| A1, A2 | the registries | `defect_gate.py dropped` over the real history reports nothing after the restoration |
| A3 | `claims` | fixture registry + fixture spec, red then green in one session |
| A4 | `dropped` | fixture git repository holding one dropped value and one legitimate change |
| A5, A6, A7 | `campaign.py check` | findings before and after, captured to evidence |
| A8 | the injected applier | the recorder sees `tv_sec == 1` twice; no `Date()` in the test |
| A9 | `wall_clock_census.py` | `--arm` catches 2 of 2, live run reports 0 of its denominator |
| A10 | `./scripts/test.sh` | run, not cited, before and after |

## What this plan does not do

It does not edit `campaign.py`, which lives in a plugin cache this repo does not own. It does not
touch `docs/feature-specs/LEDGER.md`. It does not move the 1s bound, raise a ratchet, or reclassify
a case to make a gate green.
