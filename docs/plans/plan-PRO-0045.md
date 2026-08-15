# Plan — PRO-0045: A delegated call is still gated and recorded

**Spec:** `docs/specs/spec-PRO-0045.md`
**Branch:** `ai/pro-0045` (worktree `.worktrees/PRO-0045`)
**Tier:** Standard
**Baseline:** `swift build` clean; `./scripts/test.sh` = **1105 tests, 118 suites, exit 0**
(rebased onto `main` at `ca54833`, which is where `scripts/test.sh` arrived via PRO-0053).
The gate is the script, never a bare or piped `swift test`: a pipe returns the pipe's exit
status, the XCTest summary line reports `Executed 0 tests` on a failing swift-testing run, and
a `--filter` matching nothing prints a genuine passing verdict.

## Shape of the change

Six slices, ordered so each compiles and tests on its own. Slices 1–2 are the feature; 3–4
are the subprocess failure modes; 5 is the surface; 6 is the guard. The native path is
untouched throughout, which is what makes A11 checkable by running the existing suite
without editing it.

One structural decision that shapes several slices, **revised by the plan review**: lane
events and the failure classification both travel **on the value returned by the call that
produced them**, never through a shared accumulator the `Session` drains afterwards.

The first draft had the backend collect events in an actor and `SessionAct` drain them after
each `perform`. That is wrong on a reentrant actor: `await perform` and `await drain` are two
suspension points, so a second batch can complete between them and a "take all" drain
attributes one call's events to another. There is no hop between produce and take if the
events come back with the result, so:

- `Actuation` gains `laneEvents: [LaneEvent]` for the success path;
- `ActuationFailure` — a typed error carrying an `AgentError`, its lane events, and the
  backend's **own** classification of whether the outcome is indeterminate — for the failure
  path.

The typed error also removes the second fragility the review named: the step loop was going to
decide "indeterminate" by matching an error *code*, and a code is not an identity — the same
raw value can arrive from a different domain, and a native backend could emit it. Only the
backend knows whether a request may already have been delivered, so the backend says so and
the loop obeys. `SessionAct` matches on the type, not on a number.

---

## Slice 1 — The record vocabulary (`ProctorCore`)

Pure data and pure functions; no behaviour yet. Everything here is additive.

**`Sources/ProctorCore/Policy.swift`**
- `AuditRecord` gains five optional fields after PRO-0047's six: `by`, `mode`, `eff`, `obs`,
  `lane` (all `String?`). Appended, so a row sealed before this decodes with them nil, and
  neither the signed material nor the chain link changes — both are computed over the sealed
  ciphertext.
- `AuditRecord.Outcome` gains `indeterminate`.
- `AuditRecord.forStep` gains the five parameters, all defaulted nil so every existing call
  site compiles unchanged.
- A small `Observation` enum (`changed` / `unchanged` / `unread`) with a `String` raw value,
  and `AuditRecord.Outcome.indeterminate = "indeterminate"`.

**`Sources/ProctorCore/RunHistory.swift`**
- `Outcome` gains `indeterminate`.
- `outcome(of:)` maps the new string to it. The existing `default: return .failed` stays, so
  an older build reading a newer trail degrades safely.
- `reduce(_:)` gains one rule, placed after `.halted` and before everything else: a run
  containing an indeterminate step is `.indeterminate`. A person's Stop still wins, because
  it is the dominant fact about why the run ended; nothing else outranks not knowing.

**`Sources/ProctorCore/StepDescription.swift`**
- `Outcome` gains `indeterminate`.
- `line(for:node:outcome:)` renders it with the **noun** form and wording that does not
  assert: `"Press \"Send invoice\" — could not tell whether it happened"`. The existing
  `refused` and `failed` lines are untouched.
- `past(for:node:)` gains a variant (or a parameter) that returns the noun form, for the
  `act` field on an indeterminate row. `Wording.noun` already exists for every kind, so this
  selects rather than authors.

**`Sources/ProctorCore/Wire.swift`**
- `AgentError.Code` gains `actionIndeterminate` — "the backend stopped answering mid-step and
  Proctor cannot say whether the action landed". Placed beside `actionNoOp`.

**Tests — `Tests/ProctorCoreTests/`**
- A row encoded without the new fields decodes with them nil (backward compatibility).
- A row with them round-trips.
- `RunHistory.reduce` returns `.indeterminate` for a mixed run containing one, and `.halted`
  when a person also stopped it.
- **A9's walk:** for every `ActionStep.Kind`, the `indeterminate` line does **not** contain
  that kind's `past` verb. This is the test that would have caught the defect grok found.

---

## Slice 2 — The step row carries three facts (`ProctorAgent`)

**`Sources/ProctorAgent/Session/SessionPolicy.swift`**
- `auditStep` gains an `Actuation?` parameter and an `Observation?` parameter, and maps them
  onto the five fields: `by` from `outcome.backend`, `mode` from `outcome.reportedMode`
  **through `StepDescription.sanitised`**, `eff` from `outcome.effect`, `obs` from the
  observation, `lane` from the session's current lane id.
- Its header comment becomes the attestation paragraph from the spec, verbatim (A12).
- `auditStep` gains an `outcome:` string rather than the current `ok: Bool`, so an
  indeterminate step is expressible. The two existing `ok`/`failed` call sites pass the
  constants; nothing else changes.

**`Sources/ProctorAgent/Session/SessionAct.swift`**
- `observation(before:after:)` — a small static that returns `.unread` when either hash is
  nil, else `.changed` / `.unchanged`. Nil in, nil out, so the native path (which takes no
  before-hash) records no observation.
- The success call site passes the `Actuation` and the observation.
- `hashBefore` is already read for a non-native backend; it now also feeds this.

**Tests — `Tests/ProctorAgentTests/`**
- A delegated step with a recording backend and an injected audit sink produces a row with
  `by: cua`, the driver's `mode` and `eff`, and an `obs` matching a driven state change (A2).
- The same step on the native backend produces `by: native` and four nils (A2, A11).
- `suspectedNoOp` + changed tree → `outcome: ok`, both fields present; `suspectedNoOp` +
  unchanged tree → `outcome: failed` (A3). This asserts PRO-0044's verdict is unchanged and
  that its inputs are now visible beside it.

---

## Slice 3 — Indeterminate outcomes and the post-death reading

**`Sources/ProctorAgent/Session/SessionAct.swift`**
- The catch arm matches the **typed** `ActuationFailure` and reads its own classification,
  rather than matching an error code. Only the backend knows whether a request may already
  have been delivered; a code can arrive from another domain and a native backend could emit
  the same one. For a failure the backend classifies as indeterminate:
  - walk the window once more and compute the observation from `hashBefore`;
  - record `outcome: indeterminate` with the observation attached;
  - write the lane events the failure carried;
  - stop the batch, as every failure arm already does.
- Every other error keeps `failed` exactly as today, including every native failure — a native
  throw genuinely means nothing was posted.
- The step's `act` is written in noun form when the outcome is indeterminate.

**Tests**
- A backend throwing an indeterminate-classified `ActuationFailure` produces `outcome:
  indeterminate`, a populated `obs`, and a stopped batch (A4).
- A backend throwing an ordinary `AgentError`, and every native failure, still produce
  `failed` (A11) — including one carrying the same error code, which is what pins the
  type-not-code decision.
- No path re-runs the step (A10): the run's result list contains it exactly once and
  `failedAt` is set.

---

## Slice 4 — The deadline, the poison, and identity by pid

The riskiest slice, and the one with a defect to fix first.

**`Sources/ProctorAgent/Actuation/CuaClients.swift`**
- **`CuaLineReader`** — a new small type owning a file descriptor and a residual buffer,
  with `readLine(deadline:)`. It is the seam that makes the deadline testable **without a
  driver binary**: a test drives it against a bare `Pipe()`. Five bugs the plan review found
  in the first sketch, all of which would have shipped, are designed out here:
  1. **Serve a buffered line before polling.** If the residual already holds a complete line,
     return it without a syscall. Polling first can block on a healthy child whose answer is
     already in hand, blow the deadline and poison the lane over a reply that had arrived.
  2. **Drain the residual once more on expiry**, before poisoning, for the same reason.
  3. **EOF is not a timeout.** `POLLHUP` with a trailing unterminated line returns that line;
     a clean EOF is its own error. Treating a finished child as a deadline breach poisons a
     lane that had simply closed.
  4. **Floor the `poll` timeout at 1 ms** whenever the remaining budget is positive. Integer
     millisecond truncation turns a 0.4 ms budget into `poll(…, 0)`, which returns instantly
     and poisons the lane.
  5. **Monotonic clock only.** The budget is computed from `DispatchTime.now().uptimeNanoseconds`,
     as the rest of this file already does for elapsed time; a wall clock jumps when the
     machine sleeps.
- `CuaEndpointTransport.exchange` uses it with `callTimeout` — the constant that is currently
  declared and never read.
- **Poison.** On expiry: terminate the child, set a `poisoned` reason, and return a typed
  failure classified indeterminate. Every later `send` on that transport throws immediately
  with the reason, and no new child is started. Lane-wide and for the agent's life, which is
  deliberately conservative and matches what `CuaClients` already does on a death; the review
  flagged the cost, and it is recorded as child work rather than softened here.
- **Identity by audit token, not by pid.** The review was right that
  `kSecGuestAttributePid` names a number rather than an incarnation: a pid can be recycled,
  and validating a recycled pid attests the wrong process — the exact false-attestation
  failure this item exists to avoid. So the child's `audit_token_t` is read with
  `proc_pidinfo(pid, PROC_PIDAUDITTOKEN, …)`, guested with `kSecGuestAttributeAudit`, and
  checked with `SecCodeCheckValidityWithErrors` against the requirement `CuaPreflight`
  already builds. The cdhash is read back and **recorded as evidence, never used as the
  check** — the requirement is what pins identity.
  **If the audit token cannot be obtained, the lane records identity as unattested** rather
  than falling back to a pid check, because a weaker check wearing the stronger name is the
  thing being designed against.

**`Sources/ProctorAgent/Actuation/CuaPreflight.swift`**
- `CuaLaneReport` gains `identityPinned: Bool`, `cdhash: String?` and `transport: String`.
- The path-based `verifySignature` stays as the pre-execution gate — it still decides whether
  to run the binary at all, which is a real and separate job — but it is no longer what the
  lane record attests.

**`Sources/ProctorAgent/Actuation/CuaActuationBackend.swift`**
- `LaneEvent` values are returned on `Actuation.laneEvents` (success) or on the typed
  `ActuationFailure` (failure), never accumulated for a later drain.
- Events: `opened` (path, version, cdhash, overrides, transport, identityPinned), `refused`
  (stage, reason), `identityChanged` (old/new version), `died`, `timedOut`.
- For the unpinned transport, `preflight()` re-runs per batch and emits `identityChanged`
  when the reported version moves; the pinned transport keeps PRO-0044's once-per-lane
  behaviour.

**`Sources/ProctorAgent/Session/SessionPolicy.swift`**
- `auditLane(_:)` writes one lane event through `auditSink`, tool `proctor_actuation`, no
  step kind — so `RunHistory` attributes it to the run rather than to the step list.

**`Sources/ProctorAgent/Session/SessionAct.swift`**
- Writes the lane events carried back by each `perform` — from the returned `Actuation` on
  success, from the caught `ActuationFailure` on failure — before the step row, so the trail
  reads in causal order. No drain, no shared accumulator, nothing to interleave.

**Tests**
- `CuaLineReader`: two lines written in one chunk both read; a buffered line returns without
  blocking past the deadline; a tight sub-millisecond budget does not instant-poison; EOF with
  an unterminated trailing line returns that line rather than timing out; nothing written
  returns within the deadline (A5).
- A poisoned transport refuses subsequent calls with a reason naming the timeout, and starts
  no new child (A5).
- A recording backend returning lane events produces the matching audit rows with no step kind
  (A6), and an `identityChanged` event refuses the batch before any step runs.
- **Two overlapping `runSteps` on one `Session`**, each on a backend emitting a distinct lane
  event, assert every event lands on the run that produced it. This is the test the review
  asked for, and it is the one that fails against a drain-based design.

---

## Slice 5 — The surface

**`Sources/ProctorUI/HistoryWindow.swift`** — three switches gain the case: label
("\(count), outcome unknown"), glyph (`questionmark.circle.fill`), colour (`.orange`).
**`Sources/ProctorUI/HistoryModel.swift`** — no change needed; it decodes through
`RunHistory.Outcome`'s raw value.

Nothing else in the UI moves. The run HUD, the menu bar and the queue are untouched — the HUD
draws a step in flight and this outcome only exists once a step has ended.

---

## Slice 6 — The guards

**A1 — the gate precedes the spawn.** A test installs a blocking policy, runs a batch on a
recording backend, and asserts the backend saw **zero** calls (no `preflight`, no `perform`)
and the trail holds exactly one `refused` row. This pins the ordering structurally rather than
by reading the call graph.

**A7 — nothing widens.** A redaction test drives a step whose text, node label and window
title are all distinctive sentinels, with a driver returning an over-long `mode`, and asserts:
no sentinel appears anywhere in any row this item added; `mode` is capped at
`StepDescription.objectLimit`; the lane rows carry the driver path and version and nothing
else.

**A12 — the attestation is in the code.** A test reads `SessionPolicy.swift` and asserts the
attestation paragraph's load-bearing sentence is present in `auditStep`'s header comment. A
documentation test is unusual, and it is here because the spec makes the sentence a
deliverable — a comment nothing checks is a comment that will be deleted by the next refactor.

---

## Plan review gate — grok-4.6, xhigh, read-only

Design and plan only; no key-handling code, no sealing pair, no `AuditKeyStore`. The first
call died mid-reasoning after it began reading the workspace (a lane failure, not a pass);
the retry pinned the evidence inline and forbade file reads, and answered. Findings, all
accepted:

1. **Draining lane events after `perform` interleaves on a reentrant actor.** Two suspension
   points, a "take all" drain, and a second batch finishing between them attributes one call's
   events to another. Events now ride the returned value; the drain is gone.
2. **`kSecGuestAttributePid` names a number, not an incarnation.** A recycled pid attests the
   wrong process. Switched to the child's `audit_token_t` via `kSecGuestAttributeAudit`, with
   an explicit unattested outcome when the token cannot be read.
3. **Splitting the catch arm on an error code is fragile.** Codes are not identities. Replaced
   with a typed failure carrying the backend's own classification.
4. **Five concrete bugs in the line reader** — polling ahead of a buffered line, discarding the
   residual on expiry, reading EOF as a timeout, millisecond truncation to `poll(…, 0)`, and a
   wall clock. All five designed out and each has a test.
5. **Missing test:** two overlapping `perform`s with events bound to their producing call.
   Added, and it is the test that fails against the design this gate replaced.

The reviewer also noted the poison is lane-wide and permanent. That is deliberate and matches
`CuaClients`' existing stance on a death; the better fix is request ids on the driver's wire,
already recorded as child work.

## Verification

Per acceptance clause, red→green, plus the full suite after every slice. The full sweep runs
at the end with the count read back, because `swift test --filter` matches the Swift **function**
name rather than the `@Test` display string and a filter that matches nothing reports green.

**Before running any suite that appends:** confirm `PolicyStore.isTestProcess` fires by taking
the real trail's line count and md5 before and after. Verified at baseline (577 lines, md5
`d2e2ad29…`, byte-identical across a full run) and re-checked at the end.

## Risks

- **The deadline is the only behaviour change that can affect a healthy run.** A slow-but-alive
  driver on a 30-second step would now be cut off and its lane closed. The constant is
  PRO-0044's own and is not being re-derived here; if it proves wrong, it is one number.
- **`SecCodeCopyGuestWithAttributes` cannot be exercised end to end**, because the driver is not
  installed and PRO-0023 forbids installing it. The verification path is unit-tested against
  Proctor's own process (which has a known identity) and the failure branch against a binary that
  is not the driver. That is the same limit PRO-0044 recorded, not a new one.
- **The poison rule is deliberately aggressive.** One session's timeout closes a lane a second
  session may be sharing. Recorded as child work in the spec; the correct fix is request ids on
  the driver's wire.
