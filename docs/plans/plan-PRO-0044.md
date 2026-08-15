# Plan — PRO-0044: Cua becomes the actuation backend

**Spec:** `docs/specs/spec-PRO-0044.md`
**Plan size:** Large
**Branch / worktree:** `ai/pro-0044` in `.worktrees/PRO-0044`
**Gate:** `swift build` + `swift test` (no Playwright in this repo)

## Intent, in one paragraph

Extract Proctor's single actuation call into its own injected protocol, add a Cua backend
beside the native one, and make the result honest about what the delegated driver actually
did. `cua-driver` is not installed on this machine and installing it is forbidden
(PRO-0023), so the Cua lane is built and tested entirely behind a fake transport, and every
claim about Cua's wire is treated as an unverified reading enforced by a capability probe
rather than as fact. Four wave-7 items build on the contract this defines.

## Ground truth established before planning

Verified by reading, not assumed:

| Fact | Location |
|---|---|
| The **single** actuation call site in the agent | `Sources/ProctorAgent/Session/SessionAct.swift:318` |
| The protocol that owns it today | `AXEngine.perform`, `Sources/ProctorAgent/Contracts.swift:37` |
| Native implementation, builds the target then delegates | `Sources/ProctorAgent/AX/AXEngineImpl.swift:284` |
| The actuation body that must not change | `Sources/ProctorAgent/AX/Actuator.swift` (791 lines) |
| Injection point, protocols with defaults | `Session.init`, `Sources/ProctorAgent/Session/Session.swift:558` |
| **Refuses synthetic kinds when `foreground: false`, before any backend** | `Session.refusal(for:foreground:)`, `SessionAct.swift:454` |
| **Lane + foreground demand derived from step KINDS, before any backend** | `Session.foregroundDemand`, `SessionAct.swift:24`; `lanes(for:)`, `SessionQueue.swift:25` |
| Precedent for `ok: true` carrying a non-nil `error` | `SessionAct.swift:365-372` |
| The agent's fake | `FakeAX`, `Tests/ProctorAgentTests/Fakes.swift:13` |
| Plane / route / actuation / step result | `Sources/ProctorCore/Wire.swift:456-575` |
| Counts `.syntheticEvent` to decide "took the machine" | `ForegroundReport.from`, `Sources/ProctorCore/ForegroundDemand.swift:200` |
| Folds **state hashes only** — no timing in the score | `StabilityScore.fold`, `Sources/ProctorCore/StabilityCaptures.swift:209` |
| Never-execute-a-detected-binary rule | `Sources/ProctorCore/ToolPresence.swift`, `ToolProbe.swift` |
| Pre-post declaration the guards arm from | `SyntheticPost`, `Overlay/RunHUDGeometry.swift:92` |
| Event tag telling Proctor's events from a person's | `ProctorEventTag`, `Sources/ProctorCore/Contention.swift:87` |
| **Dependency direction: Agent → Core. Core cannot see Agent types.** | `Package.swift:44-55` |
| **`ProctorCoreTests` links Core only** — no Agent type may be tested there | `Package.swift:49` |

No rendered-appearance claims appear anywhere in this plan — the feature has no UI surface,
so the MEASURED/ASSUMED marking has nothing to attach to.

## The correction that reorganised this plan

The out-of-family review found that the first draft would have shipped a Cua lane in which
**background clicks are unreachable** — which is the entire reason for adopting Cua.

`Session.refusal(for:foreground:)` refuses `.click`, `.key`, `.hover` and `.dragPath`
whenever `foreground` is false, and it runs *before* any backend is consulted. That rule is
correct — but it is a property of **Proctor's native plane**, not of the step: it is true
because Proctor can only express those kinds as CGEventPost into the shared stream. Cua can
deliver them to one process without the foreground. The same mistake is in
`foregroundDemand` and `lanes(for:)`, which derive from step kinds alone, so a Cua batch
that never touches the front would still take the exclusive foreground lane and announce
that it took the machine.

**So the kind→plane prediction becomes a question asked of the backend.** This is a
contract change, not an implementation detail, and it is the part the four dependent items
most need to be right.

## Parity inventory — what a delegated path could silently lose

Every load-bearing behaviour of the native path, marked **keep / port / drop-with-rationale**.
The worker's acceptance review audits against this table.

| # | Native behaviour | Where | Cua lane |
|---|---|---|---|
| P1 | Secure Event Input refusal before any synthetic post | `Actuator.requireEventPlaneAvailable` | **Port, narrowed.** Proctor cannot gate another process's post. The pre-step check still refuses when the backend declares a kind can only travel the shared stream. A step that turns out synthetic *inside* Cua cannot be pre-checked; recorded as a known narrowing on the result. |
| P2 | `SyntheticPost.declare()` before a post, arming the grace window, takeover statement, contention monitor and panel mouse gate | `Actuator` → `SessionAct.runSteps` | **Port by request, not interception.** Proctor requests `background` explicitly, and arms the guards up front when the backend says the kind may take the front. A `_fg` path against a `background` request is flagged `unrequestedForeground`. PRO-0046 owns the behaviour; this ships the signal. |
| P3 | Every posted event tagged `ProctorEventTag` for yield/Stop discrimination | `Actuator.eventSource()` | **Drop, with rationale — the sharpest loss.** Cua's events carry Cua's tag. Unfixable from outside another process. Named so PRO-0046 inherits a stated problem, not a silent one. |
| P4 | Refuse rather than silently take the foreground | `Actuator` | **Keep**, now enforced through the backend's declared capability. |
| P5 | Value writes judged by reading back | `Actuator.valueReads` | **Port to a stronger form** — Cua's `effect` crossed with Proctor's own post-state hash. Two independent observers instead of one read-back. |
| P6 | Pre-flight refusal of synthetic kinds under `foreground: false` | `Session.refusal` | **Keep for native, backend-aware in general** — see above. Native's answers are unchanged, so `BackgroundRouteTests` (165 lines) stays green as written. |
| P7 | Apple Events consent (-1743) mapped to a distinct code and remedy | `Actuator.appleScript` | **Keep, native-only.** Cua has no Apple Events plane. Evidence for PRO-0051. |
| P8 | Shortcut timeout so a prompting shortcut cannot hang | `Actuator.shortcut` | **Keep, native-only**, same reason. |
| P9 | Retained `AXUIElement` refs resolving across Spaces and occlusion | `AXEngineImpl` | **Keep on the observation side.** The Cua backend cannot use them, which is why off-Space windows refuse. |

## Kind routing — which steps the Cua backend takes

The first draft omitted this and it contradicted A2. Refusal, never silent native fallback,
is what keeps "the backend never changes mid-run" true.

| Kind | Cua backend |
|---|---|
| `press`, `confirm`, `cancel`, `raise`, `increment`, `decrement`, `pick`, `close`, `focus`, `setValue`, `type`, `menu`, `scroll`, `move`, `resize` | Delegated |
| `click`, `hover`, `key`, `dragPath` | Delegated — **and this is where `routedEvent` becomes reachable**, which the native lane cannot offer |
| `appleScript`, `shortcut` | **Refused** with `actionUnsupported`, naming these as native-only planes. Not a fallback. |
| `waitFor` | Never reaches a backend; the session layer owns waiting, unchanged |

## Slices, in order

Each ends green (`swift build && swift test`). Slices 1–2 are the contract the dependent
items need; stopping after slice 2 leaves the repo coherent.

### Slice 1 — Wire contract (ProctorCore)

`Wire.swift`, `ForegroundDemand.swift`, new `ActuationBackendID.swift`.

1. `ActuationPlane` gains `routedEvent` and `unknown`; the compiler enumerates every
   exhaustive switch that must close.
2. `ActuationBackendID { native, cua }`; `BackgroundCapability { never, maybe, yes }`.
3. `Actuation` gains `backend` (defaulted `.native`, so no existing construction changes)
   and `reportedMode: String?`.
4. `StepResult` gains optionals so an undelegated result encodes byte-identically:
   `backend`, `reportedMode`, `effect: ActuationEffect?`
   (`confirmed | unverifiable | suspectedNoOp`), `retriedOnStale`, `unrequestedForeground`,
   `transportMs` (**its own field** — `elapsedMs` already includes settle, so it cannot
   carry the transport cost).
5. `ForegroundReport` gains `unproven` (count of `.unknown`) and **`note` becomes non-nil
   whenever `unproven > 0`** — `note == nil` is the signal existing readers already use, so
   a new field alone would leave the lie in place. `note` also states an
   `unrequestedForeground` step in words.
6. `laneOverrides: [String]?` on `ActResult`, carrying `unsupportedVersionForced` /
   `unsignedBinaryAccepted`, so "stamps every record" has somewhere to land. (The audit-row
   half is PRO-0045's.)
7. New `AgentError.Code`: `targetMoved`, `targetUnresolved`, `targetAmbiguous`,
   `backendUnavailable`, `backendUnsupported`, `actionNoOp`.

Tests (`Tests/ProctorCoreTests/ActuationWireTests.swift`): `unproven > 0` ⇒ non-nil note;
`.routedEvent` not counted by `measured`; new cases round-trip; a `StepResult` with no
delegated fields encodes as before (golden).

### Slice 2 — The seam, and the backend-aware prediction (ProctorAgent)

`Contracts.swift`, new `Actuation/ActuationBackend.swift`,
`Actuation/NativeActuationBackend.swift`, `Session.swift`, `SessionAct.swift`,
`SessionQueue.swift`.

1. ```
   protocol ActuationBackend: AnyObject, Sendable {
       var id: ActuationBackendID { get }
       func backgroundCapability(for kind: ActionStep.Kind) -> BackgroundCapability
       func preflight() async throws
       func perform(step: ActionStep, target: StepTarget,
                    foreground: Bool) async throws -> Actuation
   }
   ```
   `preflight` is **async** — the capability and grant probes need the transport.
2. `NativeActuationBackend` forwards to `ax.perform(...)` and answers `.never` for
   `.dragPath/.hover/.click/.key`, `.maybe` for `.type/.scroll`, `.yes` otherwise —
   reproducing today's `syntheticKinds`/`conditionalKinds` exactly. `AXEngine.perform`
   **stays**; `Actuator.swift` is not opened.
3. `Session.refusal`, `foregroundDemand` and `lanes(for:)` take the capability answers
   instead of the two static kind sets. Native's answers are identical to the sets, so
   every existing test — `BackgroundRouteTests`, `ForegroundWiringTests`,
   `RunQueueWiringTests` — passes unedited.
4. `StepTarget` (window, app, nodeId, identity) in Agent; `Session` gains an injected
   `actuator` defaulted to the native backend; the call site becomes
   `try await actuator.perform(...)`.

Tests: the existing agent suite unedited, plus `FakeActuationBackend` in `Fakes.swift`
(scriptable capability, plane, route, effect, error) and a test that a backend declaring
`.maybe` for `.click` lets a `foreground: false` click through where native refuses it.

### Slice 3 — Identity and matching (pure, entirely in ProctorCore)

New `Sources/ProctorCore/ElementMatch.swift`; `Agent/Actuation/IdentityResolver.swift`
computes an `ElementIdentity` from AX and holds no matching logic.

**`ElementIdentity` and the candidate record both live in ProctorCore**, because Core cannot
import Agent and the matcher must be unit-testable in `ProctorCoreTests`. Signature:

```
static func match(identity: ElementIdentity,
                  candidates: [ElementCandidate],
                  truncated: Bool) -> ElementMatchOutcome   // matched(Int) | ambiguous | absent
```

`truncated` is an **explicit parameter** — the first draft demanded "truncated ⇒ never
absent" from a signature that could not observe truncation.

Rules: join on the `(role, label)` ancestor chain via `parentIndex`/`depth`; `axIdentifier`
is recorded but never the join key (Cua has no such field); frame corroborates and never
decides alone; candidates separable only by frame are `ambiguous`; when `truncated`, a
no-match is `ambiguous`, never `absent`. Agreement check: role + label equal and frames
overlapping > 50%, else refuse.

Tests (`Tests/ProctorCoreTests/ElementMatchTests.swift`): unique chain; two "OK" buttons
under different parents disambiguate; two under the same parent are ambiguous; frame-only
separation is ambiguous; truncation converts absent to ambiguous; frame disagreement past
threshold refuses.

### Slice 4 — Transport and client (ProctorAgent)

New `Actuation/CuaTransport.swift`, `CuaEndpointTransport.swift`, `CuaOneShotTransport.swift`,
`CuaClient.swift`.

`protocol CuaTransport: Sendable { func send(_ request: CuaRequest) async throws -> CuaResponse }`.
Endpoint client default; `PROCTOR_CUA_TRANSPORT=oneshot` selects the per-step CLI.
**Neither is ever an automatic fallback for the other**; endpoint failure refuses the step
(`backendUnavailable`). Round-trip lands in `transportMs`. The path→plane mapping is a
**data table**; an unrecognised value yields `.unknown`.

### Slice 5 — Preflight, ordered and fail-closed (ProctorAgent)

New `Actuation/CuaPreflight.swift`; pure version arithmetic in
`Sources/ProctorCore/CuaVersion.swift`.

1. **Presence** — joins the existing read-only search. Executes nothing.
2. **Signature** — `SecStaticCodeCreateWithPath` + `SecStaticCodeCheckValidity` against one
   requirement constant, refusing unsigned / ad-hoc / wrong-identity and naming which.
   **Both artefacts are checked**: the CLI on `PATH` *and* the `CuaDriver.app` bundle it
   talks to — verifying the client says nothing about the app that holds the TCC grants and
   does the actuation, which is the thing whose identity matters.
   `PROCTOR_CUA_ALLOW_UNSIGNED=1` accepts and stamps `laneOverrides`.
3. **Version** — `>= 0.13.0, < 0.14.0`. `PROCTOR_CUA_ALLOW_UNSUPPORTED=1` accepts and stamps.
4. **Capability probe** — reads the installed vocabulary; a value outside the mapping table
   refuses **here**, not at the first schema error.
5. **Grants** — asks the driver for its own health/permission report. No `TCC.db`, no Full
   Disk Access. Returned as the driver's claim, labelled as such.

Tests: `CuaVersionTests` in `ProctorCoreTests` (pure); `CuaPreflightTests` in
**`ProctorAgentTests`** (Agent types cannot be tested in `ProctorCoreTests`). Each refusal
fires in order with found/supported/remedy; each override stamps; the presence probe is
asserted to execute nothing.

### Slice 6 — `CuaActuationBackend`, end to end behind the fake

New `Actuation/CuaActuationBackend.swift`; `Tests/ProctorAgentTests/FakeCuaTransport.swift`.

Per step: resolve identity → snapshot → match → agree → request with an explicit
`delivery_mode` → act → map the reported path → carry effect, mode, timing.
`PROCTOR_ACTUATION=cua` selects the lane; default native.

**The no-op rule, which is the fix for A13.** An optional `effect` beside `ok: true` would
leave every existing reader seeing a success, which is the same defect as `unproven`
without changing `note`. So: `suspectedNoOp` **and** an unchanged post-state hash ⇒
`ok: false` with `actionNoOp` — two independent observers agreeing nothing happened. If
they disagree (Cua suspects a no-op but Proctor's hash moved), `ok: true` with the effect
recorded, following the existing `ok: true` + non-nil `error` precedent at
`SessionAct.swift:365`.

Tests (`CuaBackendTests.swift`), all behind the fake transport: happy path; background click
reaching `.routedEvent`; cross-tree disagreement; stale retry recording `retriedOnStale`;
`targetMoved`; `targetUnresolved`; `targetAmbiguous` from truncation; off-Space refusal
naming the reason; version refusal; unknown path ⇒ `.unknown` + non-nil note;
`unrequestedForeground`; `suspectedNoOp` both ways (hash unchanged ⇒ `ok: false`, hash moved
⇒ `ok: true` + effect); endpoint dying mid-step; `appleScript`/`shortcut` refused rather
than falling back.

### Slice 7 — Replay guard, docs, changelog

The meaningful mixed-backend guard is **recording versus replay**, not pass versus pass: a
single session has one actuator, so every pass in a sweep matches trivially. The backend is
stamped into the recorded flow, and a replay whose backend differs from the recording's is
refused (or scored with that fact attached) — which is the case that actually corrupts a
determinism number. `docs/architecture.md` gains the seam. `CHANGELOG.md` `## [Unreleased]`
only, prose through `/create-luke-content` (format `marketing`).

## Acceptance criteria → the test that proves each

| Clause | Proof |
|---|---|
| A1 native untouched | Whole existing agent suite green **unedited**, plus a finalize-gate script asserting the branch diff vs `main` contains no `Actuator.swift`. *(A unit test cannot certify a PR did not touch a file — the first draft claimed it could.)* |
| A2 explicit backend, no mid-run change | Backend stamped per step; `appleScript`/`shortcut` refuse rather than fall back; replay-vs-recording backend mismatch refuses |
| A3 structural join key, ambiguity refuses | `ElementMatchTests` chain + ambiguity cases |
| A4 two trees agree before the strike | agreement test incl. the first-attempt mutation case |
| A5 moved-target table | six refusal tests, one per row, `truncated` explicit |
| A6 version + vocabulary refuse first | preflight order tests |
| A7 signature pinned, probe executes nothing | CLI **and** app-bundle refusal tests; non-executing probe assertion |
| A8 driver's own grants, labelled as its claim | preflight test *(surfacing it beside Proctor's is PRO-0050)* |
| A9 dead endpoint refuses, no silent replane | transport-failure test asserts no native call |
| A10 map path not request | mapping-table tests incl. unrecognised |
| A11 unrequested escalation flagged and said in words | `_fg` against a `background` request; `note` asserted |
| A12 unproven never reads safe | `note != nil` when `unproven > 0` |
| A13 suspected no-op ≠ plain success | both directions of the hash cross; `ok: false` on agreement |
| A14 cost recorded | `transportMs`, distinct from `elapsedMs` |
| A15 whole lane without the binary | the fourteen `CuaBackendTests` above |
| — background click reachable | a `foreground: false` click reaching `.routedEvent` on a backend declaring `.maybe`, refused on native |

## First contact — what to check the day the binary exists

Everything about Cua's wire is asserted against a fake, so a wrong reading still ships
green. Ordered, and the first two can invalidate design decisions:

1. Does every client mode mediate through `CuaDriver.app`? If so the transport question in
   spec §1 is smaller than the brief supposes.
2. The reported path vocabulary and the `effect` values, against the mapping table.
3. Snapshot truncation: how it is reported, and the real caps.
4. Whether a background `click` genuinely reaches a window without the foreground.
5. Endpoint versus one-shot timing, against the reversal threshold in spec §1.

## Out of scope

Deleting native planes (PRO-0051) · audit row shape/sealing (PRO-0045) · Stop/yield/cursor/
HUD behaviour under delegation (PRO-0046) · doctor's toolchain report (PRO-0050) · iOS and
Maestro (PRO-0048/0049) · consuming Cua's capture or tree as observation (forbidden by the
direction file) · Cua's CDP browser lane.

**Scope-narrowing check:** every out-of-scope line maps to a named sibling item or a
direction-file prohibition. No triage assumption is narrowed — each of the eighteen is
carried by a slice. Assumption 4 (both transports available) is slice 4; assumption 9
(driver's own permissions) is slice 5 step 5; assumption 12 (off-Space undrivable) is
slices 3 and 6.

## Risks

- **Every claim about Cua's wire is unverified**, mitigated structurally (mapping as data,
  probe refuses unknown vocabulary) and by the first-contact checklist above.
- **P3, event tagging, is a real and unfixable-from-here loss**, landing on PRO-0046.
- **Two new `ActuationPlane` cases break exhaustive switches** — intended; the compiler
  enumerates them.
- **Making the demand computation backend-aware touches the queue**, which is PRO-0016's.
  Native's answers are byte-identical to today's kind sets, so the blast radius is a
  refactor the existing suite already pins.

## Gate note

**Mechanical path check: PASS.** Every backtick-quoted path resolves, except those the plan
marks to be created.

**Out-of-family review: grok-4.6, xhigh, read-only — MATERIAL DEFECTS, all seven resolved.**
Codex is off for this repo by instruction, so grok is the out-of-family lane. It read the
repo rather than only the plan, and it changed the plan's structure:

1. **`Session.refusal` made background clicks unreachable on the Cua lane** — the feature's
   whole purpose. Accepted; the kind→plane prediction became a backend question, which is
   now the plan's central change. Verified at `SessionAct.swift:454` and
   `SessionQueue.swift:25`.
2. **A13 reproduced the exact lie A12 fixes** — an optional `effect` beside `ok: true`
   leaves every existing reader seeing success. Accepted; the two-observer no-op rule now
   sets `ok: false`.
3. **A1 was unprovable by a unit test** — `git diff --exit-code` is empty once committed.
   Accepted; moved to a finalize-gate diff check.
4. **Slice 3 could not follow slice 2** — `ElementIdentity` in Agent, matcher in Core, and
   Core cannot import Agent (verified `Package.swift:44-55`); and truncation was
   unobservable from the stated signature. Accepted; both types moved to Core and
   `truncated` became a parameter.
5. **Slice 5 could not close** — sync `preflight` needing the async transport, Agent tests
   filed under `ProctorCoreTests` (which links Core only), a signature check pinning the CLI
   rather than the app that holds the grants, and stamps with no field to land in. All four
   accepted.
6. **Kind routing was missing and contradicted A2.** Accepted; explicit table, refusal
   rather than fallback.
7. **The mixed-backend stability guard was dead code** — one session, one actuator. Accepted;
   the real guard is recording versus replay.

Nothing was rejected. Its closing caution — that a wrong Cua wire still ships green because
everything is asserted against a fake — is inherent to a lane that may not be installed, and
is answered by the first-contact checklist rather than by a test.
