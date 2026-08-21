# PRO-0097: the registry says open where the code says fixed

**ID:** PRO-0097 · **Status:** To Do · **Created:** 2026-08-22
**Brief:** `docs/features-to-triage/89-the-registry-says-open-and-the-code-says-fixed.md` (Wave 14)
**Branch:** `ai/pro-0097` off `ai/wave-9` · **Lane:** headless `./scripts/test.sh`
**Requirements:** REQ-067, REQ-068 · **Defects:** DEF-110..DEF-114 · **Cases:** CASE-0210..CASE-0229
**Ledger id:** allocated by the orchestrator. This item does not write `docs/feature-specs/LEDGER.md`.

## Ready for implementation plan

`inventory.json` reports 23 open defects. Reading each one against the tree rather than against the
item that claimed it establishes that most are fixed and merged, a handful are honestly open, and —
the finding that changes what this item builds — **eleven registry values were set by a merged item
and are not at HEAD**. The five defect flips PRO-0091 made with evidence, REQ-024's `vacuous`,
CASE-0032's two PRO-0088 evidence paths and its note, CASE-0059's `capture` block, CASE-0063's
`witness` block and DEF-024's whole row were dropped by merges. That is DEF-058 recurring, and it is
why the registry drifts: nothing reads a merge back.

So the drift is not carelessness to be remembered against. It is a merge that keeps ours by default
over a registry it does not understand, and it is detectable from history.

### Assumptions

1. **A record flips only with the evidence that closes it.** Seven of the 23 stay open, each with
   the reason: DEF-026 and DEF-027 wait on PRO-0093, DEF-037, DEF-039 and DEF-056 on PRO-0090, all
   `Ready for AI` rather than merged; DEF-033 is a survival-rate measurement that closes when the
   number moves; DEF-099 is excluded by the brief. Where a defect is a duplicate of one already
   fixed (DEF-043→DEF-100, DEF-044→DEF-050) the flip cites the fixing record and the source.
2. **A dropped value is restored, not re-derived.** Each restoration cites the non-merge ancestor
   commit that set it, so the reinstated value is the one its item measured rather than one written
   here. These are same-id corrections to rows this item did not create, and they are declared.
3. **`campaign.py check` reports findings, not cases.** The brief names four cases; the gate also
   flags CASE-0128 and CASE-0129 as hollow witnesses and REQ-055 and REQ-063 as unbacked. Those are
   unowned findings of the same class, so the two that have their evidence already on disk are
   closed and the two that need a witness built are recorded as defects rather than fixed here.
4. **CASE-0124 and CASE-0125 move rung rather than gain a capture.** Both measure
   `FramePixels.contentSummary` over a synthesised BGRA buffer in a unit test. No pixels came off a
   display server, so `raster-visual` is a claim neither can support and `outcome` is the rung each
   actually stands on. CASE-0129 is the raster claim that has real pixels and it keeps its rung.
   This is correcting a mislabel, not reclassifying to clear a gate: the raster count falls 11 → 9
   and what the registry knows goes up.
5. **DEF-106 takes the injected seam, following PRO-0089 rather than re-deriving it.** The bound in
   `SocketClient` is spent through `setsockopt(SO_RCVTIMEO/SO_SNDTIMEO)`, so that call *is* the
   bound mechanism the way `ScreenRecordingProbe.timer` is. It is injected, the test asserts the
   kernel was asked for `ioTimeoutSeconds`, and the 1s bound does not move.

## Requirements

| Id | Text |
|---|---|
| REQ-067 | An item that claims to fix a defect cannot merge while that defect still reads `open`: the claim is read out of the item's own spec and checked against the registry by a gate, not by whoever remembers |
| REQ-068 | A registry value set by a merged item is present at HEAD, and a merge that drops one is found by reading history rather than by noticing later |

## Acceptance

| # | Clause | Evidence |
|---|---|---|
| A1 | Each of the 23 open defects carries a disposition: flipped with the evidence that closed it, or left open with the reason | CASE-0210, `evidence/PRO-0097/defect-reconciliation.md` |
| A2 | The eleven values a merge dropped are restored, each citing the commit that set it | CASE-0211, `evidence/PRO-0097/dropped-values.txt` |
| A3 | `defect_gate.py claims` refuses a spec whose claimed defect still reads `open`, and passes when it reads `fixed` | CASE-0212, CASE-0213 |
| A4 | `defect_gate.py dropped` reports a value an ancestor commit set and HEAD lacks, armed on a fixture history built to hold one | CASE-0214, CASE-0215 |
| A5 | CASE-0126 and CASE-0127 carry `source.analyzer` and an integer `source.examined` taken from a live run | CASE-0216 |
| A6 | CASE-0124 and CASE-0125 stand on the rung their measurement supports, and the raster findings are gone | CASE-0217 |
| A7 | CASE-0128 and CASE-0129 carry a recorder, an effect class and a non-zero count from their own glass evidence | CASE-0218 |
| A8 | `SocketClient` takes its bound mechanism; the test asserts the kernel was asked for the bound and reads no clock; `ioTimeoutSeconds` is still 1 | CASE-0219, CASE-0220 |
| A9 | The wall-clock census returns 0 offenders with its denominator, and reports armed at 2 of 2 | CASE-0221, `evidence/PRO-0097/census-after.txt` |
| A10 | `./scripts/test.sh` green, with the suite count before and after | `evidence/PRO-0097/gate-before.txt`, `evidence/PRO-0097/gate-after.txt` |

## Defects

| Id | What |
|---|---|
| DEF-110 | REQ-055 declares a `filesystem-write` effect and no case backing it stands at `effect-witness`, so the gate has flagged it unowned since the census closed |
| DEF-111 | REQ-063 declares a `filesystem-write` effect with the same gap; its five cases are all `outcome` |
| DEF-112 | The PRO-0091 merge dropped five defect flips and REQ-024's `vacuous` evidence, and the PRO-0078 and PRO-0088 merges dropped four more values — DEF-058 recurring across four merges |
| DEF-113 | CASE-0128 and CASE-0129 claim `effect-witness` and carry no `witness` block, so six of the gate's findings were nobody's |
| DEF-114 | DEF-024's row is absent from `inventory.json` at HEAD, having been present at `2420282` |

## Non-goals

It does not close DEF-033, which is a measurement and closes when the number moves. It does not
close DEF-099. It does not build the two witnesses DEF-110 and DEF-111 name. It does not raise any
ratchet and it does not change a case's status to clear a gate.
