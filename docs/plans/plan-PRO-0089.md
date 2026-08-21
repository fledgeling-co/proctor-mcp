# Plan — PRO-0089

**Spec:** `docs/specs/spec-PRO-0089.md` · **Branch:** `ai/pro-0089` ·
**Tier:** Small (three seams, two test files, no new surface) · **Lane:** headless.

## Order, and why

1. **`PolicyStore` first.** It is the only open defect that can damage the machine the suite runs
   on, and step 2's new tests configure a policy — writing them before the seam exists is writing
   the incident.
2. The probe timer.
3. The line-reader clock.

## Step 1 — `PolicyStore` takes its root

`Sources/ProctorAgent/Session/PolicyStore.swift`

- `enum PolicyStore` → `struct PolicyStore: Sendable` with `let directory: URL`,
  `init(directory:)`, instance `url`, `load()`, `save(_:)`.
- `static var operatorDirectory: URL` — the real Application Support path, always.
- `static let live: PolicyStore` — `operatorDirectory` in a normal process; in a test process a
  per-process directory under `NSTemporaryDirectory()`, matching what `AuditLog.directory`
  already does at line 189 of the same file.

`Sources/ProctorAgent/Session/Session.swift`

- `var policyStore: PolicyStore = .live`, in the block that already holds `auditSink` and
  `clock`, with the reason written where the reader meets it.

`Sources/ProctorAgent/Session/SessionPolicy.swift`

- `loadPolicyIfNeeded` → `policyStore.load()`; `configurePolicy` → `policyStore.save(policy)`.
- `setPolicyStore(_:)` beside `setAuditSink` and `setClock` in the Seams block.

## Step 2 — the probe's bound becomes observable

`Sources/ProctorAgent/Session/ScreenRecordingProbe.swift`

- `let timer: @Sendable (Double) async -> Void`, defaulted in `init` to the `Task.sleep` the
  second detached task performs today. `bounded(token:)` calls `await timer(bound)`.
- `static let live` is unchanged in behaviour: it takes the default timer.

## Step 3 — the line reader's clock becomes injectable

`Sources/ProctorAgent/Actuation/CuaLineReader.swift`

- `init(fd:now:)` with `now` defaulting to `{ DispatchTime.now().uptimeNanoseconds }`; the two
  existing call sites of that expression read `now()`.

## Tests

`Tests/ProctorAgentTests/PolicyStoreSeamTests.swift` — new suite, `.serialized`.

| Case | Claim |
|---|---|
| CASE-0130 | `configurePolicy` through an injected store writes the injected directory: the file appears there and decodes to the configured lists |
| CASE-0131 | the operator's real `policy.json` is byte-identical and mtime-identical across that call — read before, read after, compared |
| CASE-0132 | `PolicyStore.live.directory` in this process is not under `PolicyStore.operatorDirectory`, so an un-injected session cannot reach it either |
| CASE-0133 | the interlock is armed: `AuditLog.isTestProcess` is true here, so CASE-0132 is a measurement rather than a tautology |
| CASE-0134 | `load()` on an empty directory is an empty policy, and a round trip through `save`/`load` returns what was saved — the pre-existing contract, now on the instance |

CASE-0131 is the brief's own proof obligation and is written so it cannot pass vacuously: it
fails if the real file is absent, so "unchanged" can never mean "never looked".

`Tests/ProctorAgentTests/ScreenRecordingProbeWiringTests.swift` — `aParkedCallDoesNotHang`
replaced.

| Case | Claim |
|---|---|
| CASE-0135 | a never-answering platform returns `unconfirmed` **because the bound timer fired** — the injected timer was asked for `GrantProbe.bound` |
| CASE-0136 | a platform answering inside the bound wins even when the timer never returns |
| CASE-0137 | `ScreenRecordingProbe.live.bound == GrantProbe.bound`, so the production probe is bounded by the constant the report quotes |

`Tests/ProctorAgentTests/CuaLineReaderTests.swift` — `silenceExpires` replaced.

| Case | Claim |
|---|---|
| CASE-0138 | with a stepping clock the reader throws `timedOut` once the budget it was given is spent on that clock |
| CASE-0139 | with a frozen clock it does not give up: a line written 300ms late is returned, which on the real clock would be a timeout |

## Registry

Defects DEF-065..069 and requirements REQ-055..056 appended to
`docs/test-campaign/inventory.json` in the file's own format; cases appended to `cases.json`.
Rows are appended, never re-sorted, and `docs/feature-specs/LEDGER.md` is not touched.

## Evidence

`docs/test-campaign/evidence/PRO-0089/` — the gate log, the before/after policy-file readings,
the wall-clock grep census with its denominator, and the under-load run.

## Risk

`PolicyStore` changing from an `enum` of statics to a `struct` touches two call sites and no
callers outside `ProctorAgent`. `ScreenRecordingProbe` and `CuaLineReader` gain defaulted
parameters, so every existing construction compiles unchanged.
