# Plan — PRO-0082

**Tier: Small.** Four code changes, one artifact decision, one measurement already taken. No
protocol change: every fact this item renders is already on the wire, and the one field it removes
is present twice elsewhere.

## Slices, in dependency order

**S1 — the report's shape (A1, A2).** Delete the `grants.append(… "Shortcuts CLI" …)` block at
`SessionDoctor.swift:103`. Keep `StatusChecks.known`'s `.tool` entry and `misfiledTools(in:)`:
they are the decode path for an agent older than this change, which is the reason the map exists.
Route `TUISurface.readiness(from:)`'s grant loop through the same partition the window uses.

Seam: `StatusChecks.permissions(in:)` / `misfiledTools(in:)` are pure over `[DoctorReport.Grant]`,
so A1 tests as a property of a real `session.doctor()` report and A2 as a property of a fixture
report that still carries the old spelling.

**S2 — the policy section (A3).** `StatusSurface.Section.policy` added to the enum and to
`sections(for:)` between `.switches` and `.activity`; constants added to `Copy` and to `Copy.all`;
identifiers added to `ID` and `ID.all`; a `PolicySection` view in `MainWindow.swift` reading
`model.report?.policy`. Rows: the gate's mode, whether an approval token is live, the filesystem
jail, and the trail — writable, verifying, entries, and anything dropped this run.

Seam: the deciding half is pure. `StatusSurface` gains the row derivation so a test reads rows
from a `PolicyPosture` value with no window, the way `LaneState` and the grant rows already work.
`status_literals.py` is the gate on the view half.

**S3 — the walkthrough line (A4).** `WalkthroughFlow.Copy.openSettings` takes
`StatusSurface.Copy.openSettings`'s value. Test binds the two constants and asserts the old
question-form string appears nowhere in `Sources/`.

**S4 — the mock decision (A5).** A dated banner in `mocks/onboarding-and-menu.html` naming
`design/surfaces/proctor-surfaces.html` as the design of record, what this file was drawn against,
and the two ways it is known to disagree with the build. No test: it is an artifact decision, and
a test over an artifact declared stale would be asserting the drift it records.

**S5 — the freeze, armed (A6).** Tests in `ProctorAgentTests` over `ScreenRecordingProbe` with an
injected platform closure. Three cases: granted-then-denied reads granted (the freeze),
unconfirmed-then-granted reads granted (the control that proves the probe can re-ask, so the
freeze is a property of caching a definite answer and not of the harness), and `doctor` reporting
the frozen value end-to-end through `Session`.

## Test strategy

| Clause | Where | Oracle rung | Arming |
|---|---|---|---|
| A1 | `ProctorAgentTests` — a live `session.doctor()` on this machine and a fake with the CLI absent | outcome | restore the append and watch it red |
| A2 | `ProctorCoreTests/TUISurfaceTests` over a fixture report carrying the old grant | outcome | remove the partition call and watch it red |
| A3 | `ProctorCoreTests/StatusSurfaceTests` over `PolicyPosture` values; `status_literals.py` over `MainWindow.swift` | value + mechanical | drop a row from the derivation; add a literal to the view |
| A4 | `ProctorCoreTests/WalkthroughFlowTests` | value | revert the constant |
| A6 | `ProctorAgentTests` | outcome | the unconfirmed control is itself the arming |

`status_literals.py` must stay at `display: 0` for `MainWindow.swift`; `defect_gate.py` runs in
both modes before reporting; `./scripts/test.sh` owns the verdict with its exit read off the
script into a file.

## What this plan does not do

It does not change what the agent does on a revocation signal, does not add a warning about a
revoked permission, does not touch `mocks/run-hud.html`, and does not touch
`docs/feature-specs/LEDGER.md`.
