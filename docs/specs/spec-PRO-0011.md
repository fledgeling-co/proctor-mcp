# PRO-0011: Pointer marker in stability per-step artifacts

**ID:** PRO-0011
**Status:** Merged
**Created:** 2026-08-13
**Last updated:** 2026-08-14
**Plan:** docs/plans/plan-PRO-0011.md
**Branch:** ai/pro-0011 (worktree `.worktrees/PRO-0011`)

## Feature description

# Pointer marker in proctor_stability per-step artifacts

**Status:** untriaged · **Value:** low · **Effort:** med · **Source:** deferred child of PRO-0010 (scheduled 2026-08-13 via whats-left ingest)
<!-- Promoted from ORCHESTRATOR.md "Deferred children" on the reader's all-three answer. Cosmetic, and gated behind a real capability change. -->

## What it is
Draw the per-step target marker (as PRO-0010 does for `flow`) into `proctor_stability` per-step artifacts too.

## Why it was deferred, not done
`proctor_stability` currently emits per-step **hashes**, not per-step **PNGs**. There is no image to composite a marker onto. So this is not a small overlay add: it needs `stability` to emit a per-step PNG first, then the marker reuses PRO-0010's compositing path.

## Scope
- In: per-step PNG emission from `stability` (opt-in), then the target marker on each.
- Out: changing the divergence/hash logic; a live cursor sprite (same honesty caveat as PRO-0010 — this is the intended target point, not a real cursor).

## Success looks like
A divergent stability run shows, per step, exactly where Proctor acted, the same way a `flow` recording does now.

## Dependencies / notes
- Parent: PRO-0010 (shares the compositing path).
- The underlying change (per-step PNG emission) is the real cost; the marker is cheap on top of it. The reader accepted that commitment by scheduling this.

---

## Triage — 2026-08-14

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions (macOS agent capability; no customer-facing product UI)

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** the determinism-measuring tool an agent or test harness calls *(behind the scenes — nothing visible changes in any app)*. Nothing customer-facing changes. No new screen.
- **What users will see:** nothing on screen. A caller who opts in gets, per step of each replay, a saved picture of the window plus a marked copy with a small marker at the point that step acted on, alongside the existing determinism numbers.
- **Behaviour changes:**
  - Two new opt-in switches on the determinism tool, both off by default, so today's callers get exactly today's output and today's speed.
  - When picture-saving is on, the run reports that timings shifted because of it, so a determinism score from a picture-saving run is never quietly compared against one without.

**Assumptions**
- `[Experience]` Both switches off by default; the run behaves exactly as today when unset. *(no cost or output change for existing callers)*
- `[Experience]` Asking for the marker with pictures off turns picture-saving on and says so in the report, rather than silently ignoring the request as the replay tool does today. *(a switch that does nothing reads as a broken feature)*
- `[Data & scope]` Pictures are saved for every step of every replay, not only steps that later disagreed. *(disagreement is only known after all runs; comparing the same step across runs is the point)*
- `[Data & scope]` Pictures land where every other Proctor picture lands, under the existing naming. *(no new naming scheme; identity comes from the report, below)*
- `[Operations]` The run's report gains a list of saved pictures in which every entry carries its replay number, its step number and the file locations — the plain picture and, where drawn, the marked one — so one step can be compared across replays. *(a flat per-step list cannot say which replay a picture came from)*
- `[Operations]` The determinism numbers, the first-disagreement index and the disagreement detail are untouched. *(the brief rules out touching the scoring)*
- `[Operations]` No new clean-up or size limit — pictures accumulate like today's do, and the switch description says an opt-in run writes roughly runs × steps pictures (doubled where a marker is drawn). *(named as a known cost rather than solved here; a retention story would be its own change)*
- `[Operations]` A step whose picture or marker could not be produced is reported as that step failing to produce one, and does not fail the run or change its score. *(matches how a failed capture is already carried alongside a step)*
- `[Experience]` Described as where the step acted, never as a live cursor — Proctor does not move the system pointer. *(same honesty caveat as its parent)*
- `[Compliance]` Gating this tool behind the permission and audit trail stays out of scope. *(a separate scheduled item owns that)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0011` before the planner picks this up.*

**Grounding note:** the determinism tool today replays a flow N times with per-step capture switched off and returns hashes only, so there is genuinely no image to mark — the brief's framing is accurate. The shared step-running path already supports per-step capture and the marker compositing that its parent added, so the work is exposing those two switches on this tool, carrying the resulting picture locations into its report shape, and covering it in tests. Pictures must come from that step-running path: the captures `includeTiles` takes today happen in a loop that runs *after* the replay has finished, so they all show the same end state and are not per-step images. That existing tile-hash behaviour is noted for the planner, not changed here. Swift package; the gate is `swift build` + `swift test` (web design and end-to-end stages do not apply). Its parent is In Progress, so this one should not start before that lands.

**Out-of-family review:** ran on grok (`grok-4.6`, effort `xhigh`, read-only) per the repo's external-CLI policy — Codex is off in this repo and was not invoked. Verdict: grounding confirmed; one High and two Medium findings, all four findings accepted and folded in (the multi-replay shape of the picture list, the contradiction over what the marker switch does with pictures off, the file-naming claim, and the tile-capture caveat above), none rejected, none escalated to a question. The assumptions review is covered by that pass, which reviewed the assumption set for internal consistency and missing defaults.

---

## Progress — 2026-08-14

**Built.** `proctor_stability` takes `captureEach` and `pointerMarks`, both off by
default. `captureEach` routes the replay through the same per-step capture
`proctor_act` and `proctor_flow` replay already use, so the frames are genuinely
per-step rather than the post-replay `includeTiles` captures (untouched). The report
gains a `captures` ledger; the scoring is computed from the same hashes as before and
is built from a different array than the ledger.

| File | Change |
|---|---|
| `Sources/ProctorCore/StabilityCaptures.swift` | **new** — `StepArtifact` (+ its JSON), `StabilityCapture`, `StabilityCaptureOptions.resolve` / `.entry` / `.ledger`, `StabilityScore.fold` (lifted unchanged out of `stability()`), the two arg-name constants |
| `Sources/ProctorCore/Wire.swift` | `StabilityReport.captures: [StabilityCapture]?`, defaulted nil |
| `Sources/ProctorCore/ToolCatalogue.swift` | the two switches on the stability input schema |
| `Sources/ProctorCore/ToolOutputSchemas.swift` | `captures` on the stability output schema |
| `Sources/ProctorAgent/Session/SessionAct.swift` | `StepRun.stepArtifacts` typed; `captures` computed; `captureForStep` returns `StepArtifact` |
| `Sources/ProctorAgent/Session/SessionFlow.swift` | `stability` honours both switches and assembles the ledger |
| `Sources/ProctorAgent/Dispatch.swift` | reads the two args via the shared constants |
| `Tests/ProctorCoreTests/ProctorCoreTests.swift` | `Stability per-step artifacts` suite, 19 tests |

**Gate.** `swift build` clean; `swift test` 192 tests / 25 suites passing from a clean `.build` (173 / 24 at
HEAD `101511b`, so +19 tests, +1 suite, none dropped).

| Clause | Proved by |
|---|---|
| Both switches off = today's run, byte for byte | `defaultRunIsUnchanged`, `noCapturesOmitsTheKey` (both encoders) |
| Marker with capture off turns capture on and says so | `markerForcesCapture` |
| A capturing run reports its timings moved | `capturingRunWarnsAboutTimings` |
| Every entry names replay, step and files, for every step a replay attempted | `entryCarriesBothPaths`, `ledgerKeepsReplayIdentity`, `ledgerCoversEveryStepOfEveryReplay` |
| A step producing no frame or no marker is reported, not fatal | `failedCaptureIsReportedNotFatal`, `missingMarkerIsReportedOnlyWhenRequested`, `ledgerReportsTheFailingStepAndNothingAfterIt`, `ledgerKeepsFailedCapturesInPlace` |
| Scoring untouched | `foldTakesHashesOnly`, `foldReportsShortRuns`, `scoringUntouched` (the fold takes hash columns and has no artifact parameter) |
| Volume cost + honesty caveat on the switches | `stabilityAdvertisesTheSwitches` |
| Ledger advertised on the output schema | `outputSchemaAdvertisesCaptures`, `argumentNamesAreShared` |
| act / flow replay output unchanged by the shared-path rewrite | `stepArtifactEncodesACapture`, `stepArtifactEncodesAFailure` (golden JSON for all three shapes) |

**Known limit of the gate.** The agent wiring in `Session.stability` is not covered:
`ProctorCoreTests` depends on `ProctorCore` alone, and `ProctorAgent` is an
`executableTarget`, which SwiftPM cannot link into a test target. So a regression that
stopped calling the ledger, or dropped `failedAt`, would not turn a test red. Both grok
passes raised this; extracting `StabilityScore.fold` into Core closed the score half of it
and shrank what is left to argument passing and ledger accumulation. Closing the rest
means splitting `ProctorAgent` into a library plus a thin `main` — a repo-wide change
affecting every feature, so it is logged as child work rather than taken here.

**Deferred.** Nothing in this item. Retention and size limits for the written PNGs stay out of scope
per the spec (named as a known cost); the policy/audit gating of this tool belongs to
PRO-0012.

**Discovered child work.** `ProctorAgent` is an `executableTarget` with no test target, so no feature in this repo can red-green its agent-side wiring. Splitting it into `ProctorAgentCore` (library) plus a thin executable would give every feature that coverage. Repo-wide, orchestrator's call.

**Out-of-family gates.** Plan review ran on grok (`grok-4.6`, `xhigh`, read-only): 3
High, 3 Medium, 1 Low, all seven dispositioned in the plan (six accepted outright, H2
accepted in part with the claim narrowed rather than overstated). Completeness critic ran twice on grok: one High, one Medium and two Low accepted and
fixed (the vacuous A6 test, the empty-`annotatedPath` marker, the spot-check goldens, the
bare output schema, the A4 overclaim), and one High accepted as a stated limit rather than
closed (see above). Codex is off in this repo and was not invoked.
