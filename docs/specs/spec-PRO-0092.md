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
