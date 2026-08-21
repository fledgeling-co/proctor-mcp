# PRO-0091 — The campaign's own instruments

**Brief:** `docs/features-to-triage/84-the-campaigns-own-instruments.md`
**Status:** ready to verify
**Registry ranges:** CASE-0150..0159 · DEF-075..079 · REQ-057..058

Seven findings about the tools that measure this project rather than about the product. They
share one failure mode: an instrument reporting a clean result over a population it never
examined. Every one was found by somebody checking the instrument rather than reading its output.

This spec was written after the work rather than before it. The item was dispatched naming a
spec and a plan that did not exist on any branch, and the brief carries the conversion contract
in full, so the contract below is the brief's rather than a re-derivation of it.

## What the seven are

| Defect | The instrument | What it could not see |
|---|---|---|
| DEF-041 | `campaign.py check` | A capped list of twelve read as a population of eighteen |
| DEF-030 | the census control | Arms one of the gate's two requirement-level passes |
| DEF-032 | `mutate_swift.py` | Spends a sampled slot on an edit the compiler must reject |
| DEF-055 | CASE-0074's note | A load figure contradicting its own evidence file |
| DEF-057 | the oracle ladder | Four armed cases on a rung the ladder does not have |
| DEF-040 | REQ-024's census row | A declared effect naming a boundary the code never crosses |
| DEF-058 | a hand-merged registry | Two keys of five swept, one judged capture unpublished |

## Acceptance

| # | Clause | Evidence |
|---|---|---|
| A1 | `campaign.py check` prints the denominator beside every capped list, truncated or not | `evidence/PRO-0091/def041-denominator.txt`, CASE-0150, CASE-0151 |
| A2 | Both census passes are watched red from a clear baseline, in one session | `evidence/PRO-0091/def030-both-passes-armed.txt`, CASE-0152 |
| A3 | The integer operator no longer matches closure shorthand, proved over a fixture containing `$0` | `evidence/PRO-0091/instrument-suite.txt`, CASE-0153 |
| A4 | CASE-0074's load figure matches its evidence file, and cannot drift again silently | CASE-0154 |
| A5 | DEF-057 decided and recorded, with the fork referred out of family | CASE-0155, CASE-0156 |
| A6 | REQ-024 recorded `vacuous` rather than reclassed to `none` | `evidence/PRO-0091/campaign-check-after.txt` |
| A7 | A registry-merge script sweeps every key, with a test that a dropped key is caught | CASE-0157, CASE-0158 |
| A8 | Every check is watched red on a fixture built to trip it, and green when restored | `evidence/PRO-0091/instrument-arming.txt` |
| A9 | `./scripts/test.sh` owns the verdict on all of it | CASE-0159 |

## The two decisions this item had to make rather than assume

**DEF-057 — the rung.** Referred to grok-4.6 at effort xhigh, which ran its own three-family
panel; fable-5 at high and gemini-3.7-flash-high answered the same way with the options in
swapped order, and the codex lane failed to initialise and was recorded as a lane failure rather
than counted as agreement. The answer was neither option the brief named.

Re-expressing CASE-0102..0105 against the built product is not available: their clause is a
property of the source, and a hardcoded `Text("Open log")` and a `Text(Copy.openLog)` render
identically, so there is no product-side observable. Giving the ladder a `source-analysis` rung
positioned below `outcome` invents a comparison the coverage model does not have — the ladder is
one axis, what a case checked against the running product, and a reader of source text is off
that axis rather than ranked on it.

So `SOURCE_RUNGS` is a parallel set alongside `EFFECT_RUNGS` and `RASTER_RUNGS`: accepted by
`add`, counted in its own bucket, printed on its own `Off-ladder:` line, and absent from
`EFFECT_RUNGS`. Two guards keep it from becoming cheap — a passing case owes its analyzer and
its examined count, and a requirement claiming an external effect may not rest on it alone.
Reclassifying the four to `structural` is the route the brief ruled out and was not taken.

**DEF-041 — where the fix belongs.** `campaign.py` is not in this repo. The same referral
answered this one: it is the project-agnostic auditor and a missing denominator is a bug in
every consumer, so the fix belongs in the plugin's source repository rather than vendored here.
`~/Dev/fledgeling-plugins` is committed at `f37255f` as test-campaign 0.9.4 and unpushed, and
those bytes are mirrored into the active plugin cache so this machine's gate reads them now.
`scripts/campaign/` keeps only the instruments that are specific to this project. A vendored
copy of a 1,658-line auditor would drift, and the submodule already shows that shape: the
vendored tree is 1,319 lines and predates the `effect-witness` rung.

## What this item does not do

It raises no ratchet and changes no case's status to clear a gate. `campaign.py check` still
exits 1, on four unbacked external effects (REQ-007, REQ-023, REQ-027, REQ-028) and one
inconclusive case — all of them PRO-0083's, none of them touched here. REQ-024 left that list by
being recorded `vacuous`, which is the status that exists for a guarantee holding because
nothing performs the thing.
