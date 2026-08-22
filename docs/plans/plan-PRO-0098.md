# plan-PRO-0098 — The four nobody owns

Spec: `docs/specs/spec-PRO-0098.md`. Tier: **Standard** — four independent changes, three test
files' worth of new coverage, one new source type, two registry requirements.

Order is set by what can hide what. DEF-136 first: while 28 unswept traps are in the suite, a
red run and a dead run look the same from the outside, so every measurement the other three
clauses take is unreadable until it is done.

## Slice 1 — DEF-136, the census (A1)

1. `grep -rn ')!' Tests` into `evidence/PRO-0098/unwrap-census-raw.txt`, verbatim, before any
   edit. This is the denominator and it is recorded rather than recounted later.
2. Class each line by reading what it unwraps, not by its shape:
   - *unfailable* needs an argument that makes the initializer total. `"x".data(using: .utf8)`
     over a Swift `String` (always valid Unicode), `UnicodeScalar(0xF702)` (a BMP literal outside
     the surrogate range), `TimeZone(identifier: "UTC")` (the one identifier Foundation
     guarantees).
   - everything else is *live*, including every `TimeZone` lookup that is not `"UTC"`, every
     `Toolchain.entry(for:)`, every `AuditSeal` seal/encode/decode, every `range(of:)` over
     product-generated text, and `CGContext(...)`.
3. Convert the live ones. `try #require(expr)` where the enclosing function can throw or be made
   to; a restructure where the unwrap can be removed outright
   (`String(data:encoding:.utf8)!` → `String(decoding:as: UTF8.self)`, which is total).
4. Fixture helpers (`AuditChainTests`'s `Chain` struct, `ToolchainTests`'s `entry(_:)`) become
   `throws` and the ripple is followed with the compiler, not by grep — `swift build --build-tests`
   names every call site that then needs `try`.
5. `#expect` takes a `Comment`, so any message stays a single literal or interpolation; never
   two `String`s concatenated.

**Seam:** none needed — this is test-local.
**Risk:** the `throws` ripple through `AuditChainTests` is wide. Mitigated by letting the
compiler enumerate it; no behaviour changes, so a green suite at the same test count is the
check.

## Slice 2 — DEF-136, the arming (A2)

Pick `Toolchain.entry(for:)` in `ToolchainTests`, the catalogue-lookup shape the brief names.
Sabotage: make the entry lookup miss for one literal id.

- Run A: the pre-conversion source restored at that one site, sabotage applied → expect signal
  5 and `FAIL: no swift-testing verdict line`.
- Run B: converted source, same sabotage → expect a verdict line naming the failing test.

Both runs and their exit codes go to `evidence/PRO-0098/def136-arming.txt`, then the sabotage is
reverted and the suite re-run green.

## Slice 3 — DEF-132, the lifecycle (A3)

New `Sources/ProctorCore/RestartWatch.swift`: a `struct RestartWatch` with

- `begin()` — a restart was asked for; applying becomes true;
- `observed(reachable: Bool)` — one probe landed. Reachable ends the watch and clears applying.
  Unreachable increments a probe count; at the give-up count the watch ends and applying clears
  with the agent reported down;
- `isApplying`, and an `outcome` the caller can read.

No clock inside it: it is fed events, so a test drives ten unreachable probes across any span
without waiting.

`AgentModel.reprobeAfterGrant()` keeps the 1.2 as the delay before the *first* probe, then polls
on the existing refresh cadence, feeding each probe's reachability into the watch and calling
`recomputeRecovery()`. `AgentRecovery.decide(applying:...)` is unchanged — it already takes
`applying` as an input.

**Tests:** `Tests/ProctorCoreTests/RestartWatchTests.swift`, driven through
`AgentRecovery.decide` so the assertion is about what the window *draws*, not about a boolean:
a restart of eight unreachable probes then one reachable never yields the agent-down state, and
the same sequence under the old fixed-clearing rule does. The literal `1.2` is asserted
unchanged by reading `AgentModel.swift`.

## Slice 4 — REQ-055 and REQ-063 witnesses (A4, A5)

1. Lift `FileWitness` out of `PolicyStoreSeamTests.swift` into
   `Tests/ProctorAgentTests/Support/FileWitness.swift`, extended with a sha256 and a
   directory-sweep reader. `PolicyStoreSeamTests`'s existing five cases keep working against it
   unchanged — same type, same `==`.
2. `Tests/ProctorAgentTests/OperatorFilesWitnessTests.swift` — REQ-055. Sweep the operator's real
   application-support root (policy, switches, audit trail) before and after a configure through
   an injected store. Claim: zero changed. Control arm: the same sweep over the injected root
   reports N ≥ 1 changed, and N is the case's witness count.
3. `PolicyStoreSeamTests` gains the REQ-063 witness: record the directory contents and each
   entry's mode before and after `save`, through a fresh `attributesOfItem` rather than from the
   write's options. Armed by restoring the pre-fix `Data.write(to:options:.atomic)` and watching
   red — the arming line PRO-0095 already recorded is the template.
4. Registry: `campaign.py add`/`set` for the new cases from **CASE-0270..0289** only, `witness`
   blocks with recorder/effect/count, and a provider on REQ-055. Rows are appended; nothing is
   reformatted or re-sorted.

**Anti-vacuity:** each new case is watched failing before it is recorded passing, and the arming
line says what was broken and what the failure read.

## Slice 5 — gates and records (A6)

`./scripts/test.sh` → `evidence/PRO-0098/gate-after.txt`. `campaign.py check` before and after,
with case counts computed by `len()` rather than read off the findings count.
`scripts/campaign/defect_gate.py`. DEF-110, DEF-111, DEF-132, DEF-136 flipped to `fixed` with
the evidence path on each. New defects, if any, from **DEF-140..149**; new requirements, if any,
from **REQ-076..078**.

## Out of scope

DEF-033, DEF-099, every ratchet, `docs/feature-specs/LEDGER.md`. `try!` sites in the suite are
the same hazard class and are **not** in this brief's `)!` denominator — they are named in the
census as a follow-on rather than swept here.
