# PRO-0078 — implementation plan

**Spec:** `docs/specs/spec-PRO-0078.md` · **Tier:** Standard · **Branch:** `ai/pro-0078` ·
**Worktree:** `.worktrees/PRO-0078`

## Goal

Eight `effect-witness` cases on the `macos-glass` lane, one per requirement, each with a recorder
that is not the code under test, a non-zero count, and a sabotage artifact showing the count at
zero. Where a witness cannot be built, one `inconclusive:` case naming the instrument.

## What already exists, and is reused rather than rebuilt

`scripts/campaign/glass_probe.swift` reads `CGWindowListCopyWindowInfo` and the accessibility-side
window count for a named process, and prints one JSON object. It is the recorder for A2 and half
of A6, unchanged.

`scripts/campaign/mcp_drive.py` drives `proctor-shim` over real MCP stdio, takes `--env KEY=VALUE`,
and writes every raw response plus a transcript. Every production entry point in this item is
reached through it, which is what makes the effect "driven from a production entry point" rather
than from a test calling a generator.

`scripts/campaign/capture_with_manifest.py` photographs a named surface through `proctor_capture`
and writes the manifest row `capture-lineage.py` later checks. A1's capture goes through it.

`docs/test-campaign/campaign.json` already carries the `macos-glass` `laneProof`. It is read, not
rewritten.

## New harness

One new file, `scripts/campaign/event_witness.swift`, because nothing in the tree can currently
observe or generate a session event from outside the agent. It is a single Swift script with three
modes, so one program holds the whole event-plane instrument rather than three that can drift:

- `observe <seconds> <out.json>` — a listen-only `CGEventTap` on the session. Records every event's
  type, `eventSourceUnixProcessID` and `eventSourceUserData`, plus the
  `CGEventSource.counterForEventType(.combinedSessionState, …)` readings taken at start and end.
  This is A3's recorder and A5's negative control.
- `post <count> [--tag]` — posts `count` zero-delta scroll events into the session, optionally
  stamped with `ProctorEventTag.value`. This is A4's and A5's driver, and it runs as a separate
  process so the recorder and the driver are not the same thing. Zero-delta scroll is chosen
  because it is in both the block's mask and the contention monitor's mask while changing nothing
  in whatever application receives it.
- `windows <needle> <out.json>` — a thin wrapper that adds `NSWorkspace.frontmostApplication` to
  what `glass_probe` already reports, so A6 can show the front was not taken.

The script prints JSON and nothing else, so its output is the artifact rather than a description
of one.

## Steps

**1. Build and attach the lane.** Build with the Developer ID identity, record `codesign -dv`,
start an agent from `.build/Proctor.app/Contents/MacOS/proctor-agent` on
`PROCTOR_SOCKET=/tmp/pro0078-agent.sock`, and confirm with `proctor_doctor` that it answers
`ready: true` with Accessibility, Screen Recording and Input Monitoring granted. Acceptance: the
doctor reply names the private socket and all three grants; `/Applications/Proctor.app` is
untouched and its launchd job still answers.

*If Input Monitoring is not granted to this build, A4 and A5 cannot run and both resolve
`inconclusive:` naming `CGEvent.tapCreate` and the grant. That is the honest outcome, not a
reason to install over the operator's app.*

**2. A1, REQ-004.** Capture a window through `capture_with_manifest.py`, read `frameStatus` and
`framesWaited` out of the raw reply, and record the count as complete frames. Sabotage: the same
call against a window id that no longer exists. Acceptance: a PNG on disk with a manifest row, a
`frameStatus` of `complete`, and a refusal in the sabotage artifact.

**3. A2, REQ-006.** Start a synthetic run, and while it is in flight run `event_witness windows
Proctor`. Acceptance: at least one window entry owned by the agent's pid at the HUD's level, and
zero entries for the same probe with `PROCTOR_HUD=0`.

**4. A3, REQ-003.** Start `event_witness observe` in one process, drive a synthetic step through
`mcp_drive.py` in another. Acceptance: at least one observed event whose source pid is the agent's
and whose user data is `ProctorEventTag.value`; the session counter delta agrees in direction; the
accessibility-plane control observes zero tagged events.

**5. A4 and A5, REQ-007 and REQ-008.** With `PROCTOR_YIELD=1` and `PROCTOR_TAKEOVER_INPUT=1`,
drive a multi-step synthetic run and have `event_witness post` fire untagged events into the
session partway through. Acceptance: `takeover.swallowed` greater than zero and at least one entry
in `yields`. Two-way sabotage: the same run with `--tag` yields nothing and swallows nothing; a
third run with `PROCTOR_TAKEOVER_INPUT` unset reports `blocked: false` while the observer's own tap
sees the helper's events reach the session.

*Ordering matters here. Run the tagged control first, so a positive result is not the first thing
the instrument has ever produced.*

**6. A6, REQ-002.** Drive a `press` step on the accessibility plane against a window owned by a
different pid, reading `event_witness windows` either side. Acceptance: the window server reports
the target window changed, the frontmost application is identical before and after, and the step's
reported plane is `accessibility` rather than `syntheticEvent`. Sabotage: the same step after the
target has quit, which must refuse with a reason.

**7. A7, REQ-012.** Drive a settle over the same other-process window. Acceptance:
`axNotificationsSeen` greater than zero with `ax` among `signals`. Sabotage: a settle after the
target quits reports zero and omits `ax`.

**8. A8, REQ-014.** Drive `proctor_assert kind: agree` against the other-process window and read
the findings count and the node count out of the reply. Acceptance: a count sourced from the
target's own AX server with the frame's `frameStatus` beside it — or, if no count can be sourced
from anything but Proctor's own walk, an `inconclusive:` case naming the mach-message trace as the
instrument SIP denies. Decide this from the measurement, not from the plan.

**9. Register the rows.** Append eight cases through `campaign.py add --kind case`, then resolve
each with `campaign.py set … --status … --recorder … --effect-class … --effect-count …
--evidence …`. No existing row is edited. `campaign.py set` has no `--oracle` flag, so the rung is
carried in the JSON handed to `add`.

**10. Run the three gates.** `campaign.py check`, `capture-lineage.py --gate`, and
`./scripts/test.sh`. Acceptance: `check` reports a non-zero `witnessed`; the lineage gate exits 0;
the suite exits 0 through `test.sh`, which owns the verdict.

**11. Out-of-family review of the finished evidence** on `grok-4.6` at `xhigh`, read-only, with the
case notes and the recorder claims inlined. An empty or absent response is a lane failure and falls
back in family with the downgrade logged in the artifact.

## Test strategy

The product is not being changed, so the unit suite is a regression floor rather than the evidence:
`./scripts/test.sh` must stay green at its current count, and any drop is a finding rather than an
acceptable cost.

The evidence itself is graded by three properties, each of which has a way to fail:

**A recorder that is not the driver.** Checked per case by naming both and showing they are
different processes. A4 and A5 are the two where this is structurally hardest and are the two the
plan spends a two-way sabotage on.

**A count that came out of a recorder's own output.** Checked by quoting the field and its value in
the case note, so a later reader can find the number in the artifact rather than take it on trust.

**A sabotage that actually flips.** Checked by running it and keeping the artifact. A sabotage that
was reasoned about rather than run is not recorded as one.

Two failure modes are watched for specifically. **Asserting a value the test itself wrote** is
DEF-019's shape and was found in this repo once; every count here is read from a process other than
the one that produced it, or the case says why it could not be. **A filename standing in for a
subject** is what `capture-lineage.py` exists to catch, so every new capture gets its manifest row
at capture time.

## Open decisions

**A8's count.** Recorded above as a decision the measurement makes. The plan does not pre-commit to
a pass, because the honest floor for an untraceable boundary is `inconclusive` and the whole point
of the rung is that it holds the gate shut rather than clearing it quietly.

**Whether A4's yield can be produced without holding the operator's input.** The block has to be
armed for the tap to exist at all, so for the seconds the run lasts this machine's keyboard and
mouse are held by the agent. The hold is deadline-bounded on the tap's own thread and Escape
releases it, both of which are existing product behaviour rather than something this item adds. The
alternative is not running A4 and A5 at all, which leaves two device-class requirements unwitnessed.
The run is kept to the shortest sequence that produces a swallow, and the deadline is recorded in
the artifact.

## Out of scope

The four off-glass requirements in brief `70` (PRO-0077). The blind-pass work in brief `72`
(PRO-0079). The gate-arming work in brief `73` (PRO-0080). No product source file changes; the only
new file is the harness script named above.
