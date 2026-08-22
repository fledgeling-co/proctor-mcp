# PRO-0082 — What the status window still owes, and one permission that may lie

**Status:** In Progress · **Brief:** `docs/features-to-triage/75-what-the-status-window-still-owes.md`
· **Defects:** DEF-180..DEF-183 · **Lane:** headless `./scripts/test.sh`, with a glass attempt for
item 6 · **Branch:** `ai/pro-0082` off `ai/wave-9` · **Wave:** 11b
· **Ids:** CASE-0350..0369, DEF-180..189, REQ-088..090.

## Measured

`./scripts/test.sh` before this item, at `2bd01be`: **2,028 tests in 246 suites, exit 0.**
After it: **2,055 tests in 250 suites, exit 0** —
`docs/test-campaign/evidence/pro-0082/suite-verdict.txt`. Every clause below was armed by
mutation and watched fail: `docs/test-campaign/evidence/pro-0082/arming.json`, six mutations,
six red runs, exit 1 each.

Six child-work items PRO-0036 recorded and nobody picked up. Two of them are already closed by
work that landed after the brief was written, and the brief predates both, so the first act here
is a survey of the merged source rather than a build.

## What the survey found, before anything was built

| Brief item | State on `ai/wave-9` at `2bd01be` | Evidence |
|---|---|---|
| 1 — Shortcuts CLI listed as a permission | **Open.** The agent appends it to `grants`, and only when it is missing | `Sources/ProctorAgent/Session/SessionDoctor.swift:103` |
| 2 — per-lane readiness on the wire, unrendered | **Already closed** by PRO-0066 | `LanesSection`, `Sources/ProctorUI/MainWindow.swift:1098`; `StatusSurface.Section.lanes` |
| 3 — policy posture on the wire, unrendered | **Open.** No reader of `report.policy` exists in any surface | `grep -rn policy Sources/ProctorUI` returns activation policy only |
| 4 — the walkthrough's "Already allowed?" line | **Open**, unchanged since PRO-0041 recorded it | `Sources/ProctorCore/WalkthroughFlow.swift:376` |
| 5 — the window mock has drifted | **Open.** Still carries the `Re-check now` menu row PRO-0028 deleted | `mocks/onboarding-and-menu.html:950` |
| 6 — a revoked Screen Recording grant reported as granted | **Open, and now measured.** See below | `Sources/ProctorCore/GrantProbe.swift` |

Item 2 is closed by reading the merged source, not by taking the brief's word. The brief was
written against a tree in which `LanesSection` did not exist.

## Item 6 — the measurement, and what it can and cannot settle

**The live baseline.** `proctor_doctor` against the installed agent, pid 52976, started
`Fri 21 Aug 17:37:20 2026` and running unrestarted since:

```
{"granted":true,"name":"Screen Recording","required":true,"state":"granted", …}
```

Captured at `docs/test-campaign/evidence/pro-0082/doctor-baseline.json`, with the process start
stamp beside it at `agent-start.txt`. That is step 2 of the brief's procedure: a long-lived agent
reporting the grant it holds.

**Steps 3 and 4 — revoke and re-read — were attempted on this machine and could not be
completed, and the reason is a measurement rather than a decision.** System Settings ▸ Privacy &
Security ▸ Screen & System Audio Recording was driven over the accessibility plane. The row's
switch resolved as `Proctor_Toggle`, node `nd:427831a66ed52dee`, value `1`. One `AXPress` took it
to `0` and macOS raised a sheet at the same moment reading, verbatim:

```
Privacy & Security is trying to modify your system settings.
Touch ID or enter your password to allow this.
```

with `Use Password…` and `Cancel` as its only buttons. **The `0` was a proposal, not a change**:
`Cancel` returned the node to `1` in the same tree diff, `doctor` afterwards reads `granted`, and
pid 52976 is the same process with the same start stamp throughout. So on macOS 26.6 this
revocation cannot be performed by a background runner at all — the pane gates its write behind a
person. The full record, both `doctor` replies included, is at
`docs/test-campaign/evidence/pro-0082/revocation-measurement.md`.

The reading taken after the attempt is a reading of an **intact** grant and is recorded as such
rather than as the after-shot the brief asked for.

Reading the code says the same thing the brief predicted, and the code is where the claim can
still be armed in both directions:

- `GrantProbeKeeper.definite` is written in exactly one place, `GrantProbe.swift:165`, inside
  `record(_:token:now:)`, which only ever assigns.
- Nothing clears it. There is no reset, no invalidation, no expiry, and no other writer.
- `claim(now:)` returns `.cached(definite)` as its first branch, so once a definite answer is
  held, no probe is ever started again for the life of the process.
- `Session` holds one `ScreenRecordingProbe` for the life of the process
  (`Session.swift:39`, assigned once at `:743`), and `doctor` reads it at
  `SessionDoctor.swift:26`.

So the claim is established at the layer that owns it and where any fix would land, by a two-way
armed test rather than by a code read (A6 below). What is missing is the glass rung, and it is
missing for a reason no runner can remove.

**What the glass rung would still add.** It would show the freeze end-to-end on a real
revocation, which is a stronger oracle than the mechanism test. One authenticated toggle by a
person, followed by a `doctor` call before anything else is touched, closes it. It is recorded as
an open question with the evidence that makes the outcome predictable, not as a settled one.

**DEF-180 is the record. The fix is not taken here**, because whether the agent re-probes on a
revocation signal changes what the agent does rather than what a window draws. PRO-0036 declined
that decision and this item declines it for the same reason, deliberately and on the record.

## Acceptance clauses

- **A1 — the report's permissions list contains only permissions.** The agent stops filing the
  Shortcuts CLI under `grants`; `StatusChecks.misfiledTools(in: report.grants)` is empty for every
  machine state the doctor can produce, missing CLI included. The fact itself is not lost: it is
  already on the wire twice, as `shortcutsCLIAvailable` and as the `tools` row
  `StatusChecks.shortcutsRow(available:)` appends.
- **A2 — the readers stop mislabelling an older agent's report.** `StatusChecks.known` and
  `misfiledTools` stay, because an agent from before this change still sends the grant and a newer
  shim still has to decode it. `TUISurface.readiness(from:)` routes its grants through the same
  partition the window already uses, so no reader draws a tool in the permissions pane.
- **A3 — the policy posture is rendered.** A `policy` section between `switches` and `activity`,
  drawing the gate's posture and the trail's health, with every string from `StatusSurface.Copy`
  and every row carrying an identifier from `StatusSurface.ID`. It renders **what a person needs**
  rather than everything on the wire: the two questions the block's own documentation says it
  exists to answer — whether a call is likely to be refused, and whether it will be recorded —
  plus whether the recording verifies. It carries no bundle id, path, key or token, because the
  wire carries none.
- **A4 — the walkthrough's line matches the grant row's corrected wording.** `Copy.openSettings`
  in `WalkthroughFlow` reads what `StatusSurface.Copy.openSettings` reads. The misdirecting
  "Already allowed?" question goes: the answer for a person who has already allowed it is a
  restart, which `Copy.restartNote` already says, not a trip to a pane that will show them a
  switch that is already on. Two constants with one value and a test binding them, rather than one
  constant read from two files — the reason `introCalloutTitle` gives.
- **A5 — the drifted mock is decided.** `mocks/onboarding-and-menu.html` is marked a dated record
  of a past state, in the artifact itself, naming `design/surfaces/proctor-surfaces.html` as the
  design of record for these surfaces. The decision is forced by which artifact the build is
  measured against: `SurfaceFidelity` reads `design/surfaces/proctor-surfaces.html`
  (`SurfaceFidelity.swift:5`) and nothing reads `mocks/`. Maintaining a second drawing of the same
  surfaces that no instrument reads is how it drifted in the first place.
- **A6 — the freeze is armed, not asserted.** A test drives `ScreenRecordingProbe` with an
  injected platform that answers `granted` and then `denied`, and reads `granted` back from the
  second call. Its two-way control is the same probe whose first answer is `unconfirmed`, which is
  never cached and does re-probe — so the instrument is shown able to report the other answer
  before the frozen one is believed.

## Assumptions taken

- `[Data & scope]` The `Shortcuts CLI` entry is removed from `grants` rather than kept and
  flagged. *(It is already on the wire twice over. A third spelling that every reader must learn to
  exclude is the defect, not the cure.)*
- `[Experience]` The policy section draws posture and trail health and omits the four counts'
  meaning as rules. *(The wire's own documentation names a count as "close to a rule at the
  extremes". The counts are drawn because the operator owns this machine and the window is their
  surface; they are drawn as sizes, with no list and no name.)*
- `[Experience]` The walkthrough footer's button is left visible for an unconfirmed grant.
  *(PRO-0041 hid the grant row's button because that row's remedy was the button. The walkthrough's
  remedy is its own in-process `Allow` prompt, which works whatever the probe did, and the footer
  is a secondary route beside it. The wording was the weak spot PRO-0041 named; the visibility was
  not.)*
- `[Operations]` No revocation was completed on this machine, and none could be. *(See Item 6:
  the pane authenticates. The attempt, the sheet's words and the revert are on the record.)*

## Child work found

- **Whether the agent re-probes Screen Recording on a revocation signal.** DEF-180. Untaken here
  by design; it changes agent behaviour.
- **`mocks/run-hud.html` has the same standing as the window mock** and was not touched: the brief
  names only the window mock and scope discipline is why.

## Defects

| Defect | What it is | Disposition |
|---|---|---|
| DEF-180 | A Screen Recording answer is frozen for the life of the agent process, so a revoked grant reads granted until it restarts (recorded) | recorded, not fixed — a re-probe on a revocation signal changes what the agent does rather than what a window draws, and PRO-0036 declined that decision for the same reason |
| DEF-181 | The health report filed the Shortcuts CLI under `grants`, so every reader but the status window drew a program on a disk as a permission | fixed here |
| DEF-182 | The walkthrough's Settings button carried the "Already allowed?" misdirection PRO-0041 removed from the grant row | fixed here |
| DEF-183 | The policy posture has been on the wire since PRO-0050 and no surface read it | fixed here |

## Registry

Cases `CASE-0350`..`CASE-0369` over `REQ-088`, `REQ-089`, `REQ-090` and `REQ-032`. The freeze's
two cases sit under `REQ-032` — the window listing the permissions macOS holds about Proctor —
because a stale grant is that requirement failing, and this item allocates no requirement of its
own for a defect it deliberately does not fix.
