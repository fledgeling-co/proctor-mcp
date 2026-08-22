# spec-PRO-0099 — Eight more operator paths with no seam

**Status:** In Progress
**Brief:** `docs/features-to-triage/91-eight-more-operator-paths-with-no-seam.md`
**Defects closed:** DEF-170, DEF-171, DEF-172, DEF-173, DEF-174
**Ids allocated:** CASE-0330..0349, DEF-170..179, REQ-085..087
**Branch:** `ai/pro-0099`

Three defects in this campaign are one shape: **a static that computes a path under the
operator's application-support directory, with no injection seam, so the suite writes
there.** DEF-042/110 came from a brief that happened to ask about test seams, DEF-142 from
narrowing REQ-055 until its witness could bite, DEF-164 from that narrowed claim biting
again on the next run. None was found by looking. This item sweeps the class instead, and
then closes it so the ninth cannot be found the same way.

## Baseline

`./scripts/test.sh` before the code changes: **2,028 tests in 246 suites, exit 0**
(`docs/test-campaign/evidence/PRO-0099/baseline-suite-before.txt`).

## A1 — all eight classed before any is changed

`grep -rn "Application Support" Sources/` names eleven files; three already carry the
interlock. The remaining **eight** are classed in
`scripts/campaign/operator_paths.json`, one entry per declaration with a reason:

| File | Class | Why |
|---|---|---|
| `ProctorCore/SwitchStore.swift` | **writer** | `defaultURL` — the operator's saved switches. `AgentModel` saves through it, `Session.doctor` and `main.swift` load through it. |
| `ProctorAgent/Session/SessionMaestro.swift` | **writer** | `maestroDebugDirectory(run:)` creates a `run-…` directory unconditionally, once per run, and Maestro writes records into it. |
| `ProctorAgent/Session/SessionIOSProcess.swift` | **writer** | `deviceFramePath(udid:label:)` creates the captures directory and three callers write a PNG to the name it returns. |
| `ProctorCore/Wire.swift` | **socket** | `socketPath` is a rendezvous address holding no operator data, already seamed by `PROCTOR_SOCKET` — the one mechanism BOTH processes can use. A test-process predicate would seam only one end. |
| `ProctorCore/GuestInventory.swift` | **socket** ×2 | `defaultRemoteSocket` is a path on another machine handed to ssh as a string; `defaultLocalSocket` is connected to, never created, and already takes `home`. |
| `ProctorReflector/ProctorReflector.swift` | **socket** | `supportDirectory`'s bind path, `reflector-<pid>.sock`, pid-named and unlinked. |
| `ProctorCore/TUISurface.swift` | **prose** | Three lines of copy on the `Reaching the agent` screen. Nothing resolves it. |
| `ProctorCore/ToolCatalogue.swift` | **prose** | Two JSON-schema `description` strings. Read by a model, resolved by nothing. |

**Only the writers are converted.** The brief is explicit that adding the interlock
everywhere as a precaution buys nothing on a read or a rendezvous path and adds a branch
production takes on every call.

`ProctorReflector.supportDirectory` was classed **socket** over an out-of-family verdict
that called it a writer because `bind(2)` creates an inode. The deciding facts: the only
caller of the bare `start()` is ProctorUIApp, the suite already passes an explicit path,
and `ProctorReflector` is a zero-dependency library PRODUCT other packages embed — so
reaching a test-process predicate means either a new dependency edge for every consumer or
a second copy of the predicate. That the suite always passes a path is a fact about the
tests rather than about the code, so it is checked rather than trusted: gate guard
`no_bare_reflector_start` refuses a bare `ProctorReflector.start()` anywhere under `Tests/`.

**Acceptance:** all eight classed with a reason; every writer carries the interlock; no
socket or prose path's behaviour changes. DEF-172, DEF-173, DEF-174.

## A2 — the predicate moved so the fourth writer could reach it

`SwitchStore` lives in `ProctorCore`; `AuditLog.isTestProcess` lived in `ProctorAgent`,
which depends on `ProctorCore` and not the other way round. The body moved verbatim to
`ProctorCore.TestProcess.isActive` and `AuditLog.isTestProcess` forwards to it, so every
existing caller and the regression test guarding that name are unchanged.

It reads `ProcessInfo` directly and never `ProctorEnvironment.current`, deliberately: the
effective dictionary is installed by the agent and can be replaced by a test, so an
interlock reading it could be switched off by the code it exists to contain.

## A3 — production proved unchanged, by forcing the branch rather than reading the diff

REQ-086. Reading the diff proves the literal was moved into an `operator…` accessor; it
does not prove production still reaches it. All three predicates were replaced with `false`
and the resolved paths printed and compared character for character with independently
reconstructed pre-change literals. All three matched exactly, **with
`TestProcess.isActive` reporting `true` on the same run** — which rules out the reading
where the sabotage appeared to work only because the predicate happened to be false.

Evidence: `evidence/PRO-0099/sabotage-production-unchanged.txt`.

## A4 — the diversion proved as a presence, not only an absence

A sweep reporting zero cannot tell a diverted write from a write that never happened. Both
halves come off one run of the full suite:

- **absence** — the operator's root byte-identical: **0 of 3,330 files changed**, sha256,
  size and mtime per file either side.
- **presence** — `proctor-test-settings-<pid>/settings.json`,
  `proctor-test-maestro-<pid>/run-<stamp>-1-<salt>` and `proctor-test-captures-<pid>/`
  under `$TMPDIR`.

The census counts `find -type f`, so an **empty** `run-` directory is invisible to it. The
operator's maestro root was therefore read directly: 17 stray directories, newest
2026-08-20, and nothing created on the day of these runs.

Evidence: `evidence/PRO-0099/diversion-positive.txt`.

## A5 — the class closed, and the check armed against one

REQ-085. `scripts/campaign/operator_path_gate.py` refuses a new operator path that is
classed nowhere (`census`) and a classed writer with no test-process branch (`seams`). It
runs inside the suite through `test_instruments.py`, so a check here that stopped being
able to fire is a red suite rather than a quiet one.

**Arming it found two bugs before it had ever been trusted**, both bare-name collisions in
`PolicyStore.swift` and both **false reds** — the direction that gets argued away rather
than fixed. DEF-170 and DEF-171, each with a regression fixture reproducing the shape.

Evidence: `evidence/PRO-0099/gate-arming.txt`.

## The strays already written stay

The 17 maestro run directories, four zoom PNGs and two flow files under the operator's root
were written by earlier runs. Deleting them is the act REQ-055 forbids, and PRO-0098 and
DEF-164 recorded the same reasoning rather than tidying.

## Defects

| Defect | Was | Now | Cases |
|---|---|---|---|
| DEF-170 | (opened here) | fixed | CASE-0335 |
| DEF-171 | (opened here) | fixed | CASE-0335 |
| DEF-172 | (opened here) | fixed | CASE-0330 |
| DEF-173 | (opened here) | fixed | CASE-0331 |
| DEF-174 | (opened here) | fixed | CASE-0332 |

**Defects:** DEF-170, DEF-171, DEF-172, DEF-173, DEF-174

## One red that was not this item's

Five full runs of this tree read exit 0 (2,028 tests, before the code changes), then 0, 0, 1, 0
with the same **2,031 tests in 246 suites**. The single red carried one issue, in
`HoldAttributionWiringTests`, which this item does not touch: the case awaits the hold on
`RunControl` and then reads the scheduler's ticket immediately, and those are updated separately,
so a loaded machine lands the read in the window between them. Recorded as **DEF-175, open**, with
the repair named and not taken, exactly as PRO-0098 recorded DEF-165 rather than fixing it. That
commit measured its own unchanged tree at exit 1, 0, 1, 0, so a red that is not the item's own is a
known property of this suite. DEF-175 is deliberately absent from the Defects table above, because
that table is what `defect_gate.py claims` reads.

## What this spec does not do

It deletes nothing under the operator's directories, changes what no path resolves to in
production, and does not touch the socket paths' behaviour. REQ-087 of the allocated range
is unused: two requirements cover this item's guarantees and a third would be invented to
fill a quota.

## What is not armed, and why

The positive arm of CASE-0330..0332 is deliberately not armed by sabotage. Under sabotage
those arms would write the operator's real `settings.json`, create a run directory in the
operator's maestro root and create the operator's captures directory — the act REQ-055
forbids. Their path arms are armed; the write arms stand on their own readback through the
product's loader plus CASE-0272, which proves the same reader can see a file written one
directory down. Recorded rather than glossed.
