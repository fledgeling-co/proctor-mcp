# Plan — PRO-0084, The cua path leaves Proctor's plane silently

**Spec:** `docs/specs/spec-PRO-0084.md` · **Tier:** Small · **Branch:** `ai/pro-0084` off `ai/wave-9`

Two facts already on the wire have to reach the screen, and two ceilings have to be written down.
No new surface, no new window, no new switch: both facts land on the run panel's **exception line**,
which `RunHUDState` documents as "the one sentence the panel ever says about a plane", plus the
takeover statement that already exists.

## Slices

### Slice 1 — `RunHUDState` learns the two disclosures (ProctorCore, pure)

`Sources/ProctorCore/RunHUD.swift`

- Two `RunHUDEvent` cases: `.escalatedToForeground` and `.pointerDeferred`. Both no-argument: the
  app name is already held by the state from `runBegan`, and a second copy could disagree with it.
- Two `private var` flags on `RunHUDState`, reset by `runBegan` alongside `delegated`.
- Two static line builders beside `exceptionLine(app:)`, so the wording is testable without a state
  machine.
- One resolver used by both `runBegan` and `setPlaneStatement`, so a later `stepApproaching` cannot
  silently overwrite a disclosure. **This is the load-bearing detail**: `setPlaneStatement`
  recomputes `model.exception` on every step, so a disclosure written once would survive exactly
  until the next step and no longer.
- Precedence: guest wins over everything (a guest run does not take *this* Mac, and the existing
  guard already says so); then escalation; then a deferred pointer; then today's wording, unchanged.

### Slice 2 — the run emits them (ProctorAgent)

`Sources/ProctorAgent/Session/SessionAct.swift`

- After `run.pointerOwner = pointerOwner` (`:352`): emit `.pointerDeferred` when the owner is
  `.deferredToDriver`. Once per run, where the decision is already made — not re-derived.
- After the existing `if plane == .syntheticEvent { … }` late-raise block (`:653`):
  `if outcome.unrequestedForeground { await hud(.escalatedToForeground) }`.

  **No second `takeoverShow`.** A first cut added one and arming proved it dead: every path that
  sets `unrequestedForeground` is in `CuaVocabulary.foregroundPaths`, and every member of that set
  maps to `.syntheticEvent`, which the branch above already raises the statement for. The statement
  was never missing; the wording was. Removed rather than kept as harmless, and the coupling that
  makes it redundant is now pinned by a test that nothing previously held.

### Slice 3 — the ceilings, in source

`Sources/ProctorAgent/Session/SessionCursor.swift` — at the `guard owner == .proctor` stand-down,
say why the covered-target rule stops here: it places or hides Proctor's own panel, and the pointer
now on screen belongs to another process. Recorded, not worked around.

## Test strategy

The verdict is `./scripts/test.sh`, read from a file. Never `swift test`, never through a pipe.

**Unit, `Tests/ProctorCoreTests/RunHUDTests.swift`** — pure, no window server:

| Case | Guards |
|---|---|
| CASE-0230 | `.escalatedToForeground` puts the escalation sentence on the exception line |
| CASE-0231 | it **survives the next `stepApproaching`** — the overwrite this slice exists to prevent |
| CASE-0232 | `.pointerDeferred` puts the pointer sentence up, and it survives a step too |
| CASE-0233 | escalation outranks a deferred pointer when both hold |
| CASE-0234 | a guest run shows the guest line and neither disclosure |
| CASE-0235 | `runBegan` clears both flags, so one run's disclosure cannot leak into the next |

| CASE-0241 | the existing synthetic wording still wins when no disclosure is latched |

**Coupling, `Tests/ProctorAgentTests/` (pure)** — the guard that replaced the dead predicate:

| Case | Guards |
|---|---|
| CASE-0236 | every `CuaVocabulary.foregroundPaths` member maps to the plane that raises the statement |
| CASE-0237 | no background path maps to it — the arming control against a vocabulary that mapped everything |
| CASE-0238 | an unrecognised path stays `.unknown` rather than being guessed background-safe |

**Wiring, `Tests/ProctorAgentTests/`** — `FakeActuationBackend` + `FakeTakeover`, both existing:

| Case | Guards |
|---|---|
| CASE-0242 | a driver that cannot stand its cursor down leaves a run with no Proctor pointer |
| CASE-0243 | one that can leaves Proctor drawing — the arming control for CASE-0242 |
| CASE-0244 | the native lane never defers, whatever a driver would have said |

**Arming, not reading.** CASE-0237 and CASE-0240 are the predicates that make CASE-0236's non-zero
mean something: five dead predicates have been found in this wave and every one was caught by
arming. Each new assertion is run once against the unpatched behaviour to confirm it can fail.

**Not covered, named, with the reason:**

- A real cua-driver escalating on a real Mac; a panel presenting; pixels. The wiring lane proves the
  seam, not the paint — the boundary `TakeoverWiringTests` already declares.
- **The two `hud(...)` emissions in `SessionAct` are not witnessed by any test**, and that is a
  ceiling in the harness rather than an omission. `Session.hud(_:)` calls
  `RunHUDPanel.shared.apply`, whose `feed` is hardcoded to `RunHUDFeed.shared` (`RunHUDPanel.swift:77`)
  — so a wiring assertion would read a process-wide singleton that other suites are concurrently
  writing, which is a flaky test rather than a measurement. `Session.hudFeed` is injectable and its
  own doc comment states it exists so "a test can drive the switch and read the phase without
  reaching into a singleton another test is also using" — the panel simply does not consult it.
  Routing `hud(_:)` through the session's feed would close this; it is a change to a shared surface
  outside this item's scope and is reported rather than taken. Probe F in the arming ledger records
  the consequence honestly: deleting the `.pointerDeferred` emission reddens nothing.

## Registry

Cases CASE-0230..0240 in `docs/test-campaign/inventory.json`, appended, never re-sorted.
REQ-070..072 appended likewise. REQ-072 is recorded `inconclusive` against a stated ceiling rather
than passed: no Proctor surface can cover another automation stack's run, and claiming otherwise
would be the exact over-claim this repo's campaign rules exist to refuse.

No defect ids are consumed: DEF-120..129 stay unallocated, because the two findings here are the
item's own subject rather than incidental defects found beside it.
