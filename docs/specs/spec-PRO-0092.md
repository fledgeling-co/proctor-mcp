# PRO-0092: ProctorAgent's mutants mostly survive

**ID:** PRO-0092
**Status:** Ready for AI
**Created:** 2026-08-22
**Last updated:** 2026-08-22
**Brief:** `docs/features-to-triage/85-proctoragents-mutants-mostly-survive.md`

## Feature description

DEF-033 records the largest single statement this campaign has made about how much the suite
knows. PRO-0080 took the first mutation sample ever run against `ProctorAgent` — 24 mutants over a
pool of 3,189 sites across all 84 files, seed 20260821 — and **19 survived**. Two of the five
scored kills ran to exactly 600.0s under a load average that reached 271, and the runner scores a
timeout as a kill, so the honest figure is 3 kills of 22 scored: **86.4% survival**, against
`ProctorCore`'s 50%.

`ProctorAgent` holds the session, the queue, the overlay, the actuation backend and every guest
adapter. It is the half of the product that touches the machine, and it is the weaker half.

PRO-0080 dispositioned all nineteen: 5 killed by new tests (`MutationSurvivorTests`), 1 equivalent
(`SessionMaestro`'s comparator over unique dictionary keys), and 13 recorded as **no seam** or
**uncovered-by-lane** — headless-testable in principle, but with no fake to test them through.
Those thirteen are this item.

## What this item does

**Sample before building.** 24 of 3,189 sites is 0.75% under one seed. A second sample under a
different seed says whether "no seam" is a property of the seven files that seed happened to hit or
of the package.

**Build seams the way this repo already does.** `GuestProvider.init(executable:timeoutMs:run:)`
beside a convenience initialiser binding `Self.liveRun`, and `SignatureVerdictCache.init(identify:verify:)`,
are the pattern: production supplies the live implementation, a test supplies a fake, and the seam
is a parameter rather than a global.

**Every seam earns a killing test, or the survivor is recorded with its reason.** A seam built and
not used moves a survivor from "no seam" to "uncovered", which reads as progress and is not.

**Re-measure, and report what the measurement says.** DEF-033 closes when the number moves, not
when a branch merges. The re-measured rate may be only somewhat better than 86.4%; that is a
result, not a failure.

## Acceptance sketch

- Every one of the thirteen undispositioned survivors carries a verdict argued against source: a
  killing test, or a recorded reason.
- Each new killing test is armed — the mutant re-applied, the named test watched going red, the
  mutant reverted — and the mutation is confirmed to have landed before its verdict is read.
- A fresh mutation sample over the same 84 files under a different seed, with sites, seed, run,
  unrun, killed, survived and unbuildable stated, and the machine's load and thermal state recorded
  at both ends.
- Any mutant scored at or near the timeout bound is reported apart from the kills rather than
  folded into them.
- `./scripts/test.sh` green, and the verdict read from its exit code rather than from a summary line.

## Assumptions made writing this

- Assuming the equivalent mutant is left alone. A survivor no test can kill is not a gap, and a
  suite contorted to kill one knows less than it did.
- Assuming a mutant killable only by a test that repeats the source literal is recorded rather than
  killed. PRO-0080's five kills each stand on an oracle independent of the source — Carbon's own
  keycodes, a derived mean, a hex alphabet — and that is the standard, not the exception.
- Assuming the honest package-level number comes from a fresh seed rather than from re-running the
  seed whose survivors were the targets. Re-running the targeted set measures the tests, not the
  package.
- Assuming a survivor stands regardless of the load and a kill under contention does not. Starvation
  can turn a survivor into a false kill; it cannot turn a kill into a false survivor.

---

## Triage — 2026-08-22

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions. Thirteen survivors, each already located to a
file and a line by a recorded sample. Nothing a person sees changes; what changes is whether a run
of this suite can be believed about the package that touches the machine.

**UI & logic preview**
- **Where it shows up:** nowhere a customer looks. Every change is a test seam, a test, or an
  instrument in `scripts/campaign/`.
- **Behaviour changes:** none intended. Each seam is an extraction — a value or a decision lifted
  out of a method that could not be called headlessly, with the production call site rewritten to
  go through it. Production behaviour is unchanged by construction, and the extraction is what makes
  that checkable.
- **Design reference:** none. There is no rendered surface in this item.

**Assumptions**
- `[Operations]` A survivor killable only by copying its own literal is recorded, not killed. *(a test that repeats the source is a second copy of it, and this repo's thesis is that a second source drifts.)*
- `[Operations]` The equivalent mutant is not chased. *(already argued against source in PRO-0080.)*
- `[Operations]` The re-measurement uses a fresh seed. *(re-running the targeted seed measures the tests.)*
- `[Operations]` A mutant scored at or near the timeout bound is reported apart from the kills. *(the runner scores a timeout as a kill, and that is the direction that flatters the suite.)*
- `[Data & scope]` Commits name explicit paths. *(a blanket add swept a mutated source file into a real commit elsewhere tonight.)*
- `[Data & scope]` No review lane runs against this worktree while the harness is live. *(a lane handed the worktree mid-run let production source acquire a literal from the mutation table.)*

---

### Pipeline record — PRO-0092 *(machine trailer; not part of the review above)*

**The thirteen were re-derived rather than read off a list, because the list is not in the
repository.** `docs/features-to-triage/85-…` states the aggregate — 7 no-seam, 6 uncovered-by-lane
— and DEF-033's own row states "13 … each with its reason in REPORT.md". `REPORT.md` carries the
`ProctorCore` survivor discussion and not the `ProctorAgent` one, so which survivor held which of
the two labels is not recoverable here. The thirteen themselves are recoverable exactly, from
`docs/test-campaign/evidence/mutation-agent.json`, by removing the five `MutationSurvivorTests`
names and the one equivalent.

**Four of the thirteen no longer resolve at the line the sample recorded**, measured against
`123fa02` (the commit that added `mutation-agent.json`): `Dispatch.swift:381` is now
`window: args.string("window")` and was `includeTiles: args.bool("includeTiles", false)`;
`Dispatch.swift:394` was `presentation: args.bool("presentation", true)`;
`TakeoverOverlay.swift:771` was the plate height; `RunHUDPanel.swift:653` was
`override var canBecomeMain: Bool { false }`. A mutant record anchored to a line number decays as
the file moves, and reading the current line would have dispositioned four wrong sites.

**The survivors group into three classes, and the third is new.** `equivalent` and
`uncovered-by-lane` were PRO-0080's vocabulary. A third class is needed for a mutant whose
behaviour genuinely differs but whose only available oracle is the literal it changed: a 1ms shift
in a capture timeout, one point of plate padding, one unit of a colour channel with no generated
token to check it against. Calling those `equivalent` would be false — behaviour does differ — and
killing them means writing the constant twice. They are recorded as **no-independent-oracle**, with
the argument per site.

**Registry ids.** `main` is at CASE-0456 / REQ-107 / DEF-216 / SURF-025. This item starts at
CASE-0457, REQ-108, DEF-217, SURF-026.

---

## Implementation plan

Implementation plan: `docs/plans/plan-PRO-0092.md` (committed: `eb28a5b`, tier: Standard).

---

## Defects

| Defect | Was | Now | Cases |
|---|---|---|---|
| DEF-217 | new | fixed | CASE-0458, CASE-0459, CASE-0469 |

**Defects:** DEF-217

**Requirements:** REQ-108, REQ-109, REQ-110

**Cases:** CASE-0457 through CASE-0471

**Unused from this item's allocation:** DEF-218 onward, SURF-027 onward, and CASE-0472 onward. One
defect was opened rather than a range, and fifteen cases were needed.

## The row this item was written for, and why it is still open

DEF-033 is not claimed above, and that is the result rather than a shortfall. It is a survival-rate
measurement, not a bug: it closes when the number moves. The re-measured rate is **20 of 24 = 83.3%**
against its recorded **19 of 22 = 86.4%**, and one mutant is 4.2 points at n=24 — so the move is
smaller than the resolution of either sample and the package-level rate has not been shown to move.

The arithmetic behind that is worth stating plainly, because it is the item's most useful finding.
Ten survivors killed is 0.3% of a 3,158-site pool. Killing ten named sites cannot move a rate
sampled at random from the other 3,148, however well those ten are killed. A per-survivor test
closes a survivor; only a class-closing seam can move a package rate, and the one class this item
closed — 34 argument-decode sites checked against their own published schema — is 1.1% of the pool.

## Progress — 2026-08-22

Built on `ai/pro-0092`, stopped before verify. Gate **2,073 tests in 252 suites, exit 0**, against a
baseline of 2,064 in 251 on `main`.

**Ten of the thirteen survivors now die; three are recorded with an argument each.** Six seams were
built, each an extraction with the production call site rewritten in the same change. Three of the
thirteen needed no seam at all and were only untested, which is worth separating from the seven the
brief counted: `SnapshotOptions` was always constructible, `CGWindowIndex.correlate` already took
its records as a parameter, and `RunHUDPalette.light` is a static a test can read.

**The re-measured rate is 83.3% and the honest reading is that nothing moved.** 20 SURVIVED of 24
scored over the same 84 files, count 24, seed 20260823 against PRO-0080's 20260821. One mutant is
4.2 points at n=24. Ten killed sites are 0.3% of a 3,158-site pool, and a rate sampled at random
from the other 3,148 cannot notice them. A per-survivor test closes a survivor; only a class-closing
seam can move a package rate.

**The one class closed did move a mutant it was never pointed at.** The schema-versus-decoder
agreement check covers 34 argument-decode sites, and the fresh seed picked one of them —
`Dispatch.swift:244`, `proctor_capture.normalize` — out of 3,158 sites. Re-applied afterwards to
attribute the kill: `["proctor_capture.normalize decodes false, the schema says true"]`.

**The out-of-family review found the one thing worth changing and it was accepted.** Gemini named
`dispatchDefaultsAgreeWithTheCatalogue` twice — under "asserting an implementation detail" and again
under "raising the measured number without raising what the suite knows" — because it reads
`Dispatch.swift` as text and so registers a kill without asking what an omitted argument resolves to.
`Dispatcher.StabilityArguments` and `Dispatcher.InspectArguments` are the answer: survivors 2 and 8
now die to a decoded value, and the source check stays as the class check over the other 32 sites,
registered as `source-analysis` with its denominator rather than dressed as a behavioural one.

**Moving that decode found a fault in the class check on the way out.** `InspectArguments` was first
declared in the stability section, so the parser attributed `presentation` to `proctor_stability` and
the (tool, argument) join went nil. Each struct now sits under its own tool MARK. It was visible only
because CASE-0458 asserts by name the two pairs it must find — a check that had simply compared
whatever it happened to parse would have passed over zero comparisons.

**The runner no longer scores a timeout as a kill**, armed by driving both versions from one fixture:
`killed` under the runner `main` has, `TIMEOUT` under this one, with a genuine failure unchanged in
both.

### Gates, with their real exit codes

| Gate | Exit | Reading |
|---|---|---|
| `./scripts/test.sh` via `governor-run --weight 6` | **0** | *Test run with 2073 tests in 252 suites passed*. Refused three times first with `no berth available` — the governor's ceiling drops to 3 under critical CPU pressure, so a weight-6 claim cannot be granted at all until it lifts. |
| `defect_gate.py claims` | **0** | One claimed defect, DEF-217, reads `fixed`. |
| `defect_gate.py dropped` | **0** | 2 files, 118 merges, 52,828 id/field pairs examined; no dropped value. |
| `test_instruments.py` | **0** | 62 passed, 0 failed. |
| `operator_path_gate.py` | **0** | 13 operator-path sites, 15 entries classed. |
| `mutation_seam_arm.py` | **0** | 12 of 12 armed, each mutation confirmed landed before its verdict was read; tree clean after. |
| `mutation_timeout_arm.py` | **0** | Both runners driven from one fixture; the decision and the end-to-end summary both differ, and a genuine failure does not. |
| `campaign.py check` (test-campaign 0.9.6) | **1** | **Pre-existing.** The same gate against this branch's merge base `eed148f` also exits 1, and the blocker id sets `diff` identical: REQ-007, REQ-024, REQ-086, CASE-0001, CASE-0318, CASE-0333–0335. None of this item's ids appear. |

### Judged and left alone

- **The equivalent mutant.** `SessionMaestro.swift:242`, a comparator over unique dictionary keys.
  Argued against source in PRO-0080; chasing it produces a test that asserts an implementation detail.
- **`CGWindowIndex.correlate`'s array subscript.** Total under its own `count == 1` guard, so it is
  not a live hazard. Converting it to `matches.first` would make the mutant die as a failing
  assertion rather than as an abort, which is a nicer arming and not a reason to change production.
  Recorded on CASE-0461 with the captured output.
- **DEF-033.** Not flipped. It is a survival-rate measurement and the rate moved by less than one
  mutant. Flipping it on this evidence is the move PRO-0097 wrote the rule against.
- **The four `no-independent-oracle` survivors' constants.** Not hoisted into named constants either:
  a named constant asserted in a test is the same second copy with a better name.
