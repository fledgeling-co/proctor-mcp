# Plan — PRO-0087: make the signature dedupe process-wide and single-flight

**Spec:** `docs/specs/spec-PRO-0087.md` · **Branch:** `ai/pro-0087` off `ai/wave-9`
**Tier:** Small. Two production files, one test file, four registry rows.

## Ordering, and why the baseline comes first

The defect is a wedge that only appears under concurrency, so the measurement is the artifact and it
cannot be taken after the fix. Phase 0 therefore runs the unmodified tree until it hangs and samples
the hang; nothing is edited until that is on disk. PRO-0083's `ExternalWitnessTests.swift` and
`ReflectorWitnessTests.swift` are copied in untracked for both measurements, because they are what
puts fifteen sessions on the socket at once and they belong to PRO-0083's branch rather than this
one.

| Phase | Work |
|---|---|
| 0 | Copy PRO-0083's witness suites in. Run the suite until a hang. `sample` the hung process twice. |
| 1 | The cache: shared default, single flight, identity-keyed map with a bound. |
| 2 | `ToolProbes` defaults to the shared store. |
| 3 | Four tests, each armed by re-introducing the defect it names. |
| 4 | Re-run the suite N times with the witness suites still present. Registry rows, spec, plan, changelog. |

## Phase 1 — the cache

1. `FileIdentity` gains `Hashable`, so it can key a map.
2. One slot becomes `[FileIdentity: ToolSignature]` with an insertion-order list and a 16-entry
   bound. A single slot was safe while each session had its own cache; shared, two paths in one
   store would evict each other and re-verify on every alternation, which is the wedge again.
3. `waiting: [FileIdentity: [CheckedContinuation<ToolSignature, Never>]]` records what is being
   verified and who is waiting on it. The key's presence is the in-flight flag.
4. `verdict(for:)` becomes `async`. A caller that has to wait registers a continuation and gives
   its thread back; the verification runs on a `Thread` of its own and resumes every waiter when it
   lands. `verify` still runs outside the lock, and no lock is held across a suspension.
5. `static let shared`.

Step 4 is where this plan changed after it was first written, and it changed because of a
measurement rather than a review. The first implementation kept `verdict(for:)` synchronous and had
waiters block on an `NSCondition`. That version passed its own tests, cut fifteen verifications to
one, and still hung a full-suite run — with all sixteen cooperative threads blocked, fifteen of them
in the cache's own wait. Blocking a pool that is capped at the core count and does not replace
blocked workers is what starves the verification, so the waiters have to suspend rather than block.
The referral lane (grok-4.6, xhigh) reached the same reading of the sample independently and warned
off two substitutions that look equivalent and are not: `Task.detached` for the verification, which
is still the cooperative pool, and `DispatchQueue.global()`, which can inherit it.

One call site moves: `SessionDoctor.swift:237` gains an `await`, in a function that was already
async.

The header comment is rewritten rather than amended. Its third rule currently argues against
single-flight, and leaving that in place beside the code that implements it would leave the next
reader to work out which one is true.

## Phase 3 — the tests, and what arms each one

Each test is watched failing with the defect re-introduced, because an assertion nobody has watched
fail is not known to bite.

| Test | Arming | Expected red |
|---|---|---|
| Fifteen callers on a cold entry | Remove the in-flight wait | `verificationCount → 15` |
| Eight sessions through `doctor` | Give each session its own cache | `arrivals → 8`, shared count `→ 0` |
| Probe sets share one store | Default back to `SignatureVerdictCache()` | two `ToolProbes` not identical |
| A verification in flight blocks nothing | Put the blocking single-flight back | 0 of 32 unrelated tasks ran in 20 s |
| Two files, two entries | (guards the map against a regression to one slot) | — |

The fifteen-caller test uses fifteen `Task`s, which is what the production path uses and what the
async design makes safe: nothing in the path blocks, so a caller cannot be starved by the defect it
is measuring. Its recorder is `verificationCount`, which the cache increments, so the assertion is
not on a value the test wrote.

The anti-wedge test is the one that decides whether this item is done. It puts one more caller than
the pool is wide on a cold entry, parks the verification, and requires 32 unrelated tasks to finish
while it is parked. Its watchdog runs on a thread of its own so that a regression comes back as a
red test rather than as a hung suite — the failure mode this whole item exists to remove should not
be the failure mode of the test guarding it.

The eight-session test drives `Session.doctor` and asserts on the shared counter and on the injected
`verify` having run once. It proves the production path reaches one store; the overlap claim belongs
to the fifteen-thread test, where overlap is deterministic.

## Open question

How many green runs is enough. The baseline is two green then a hang, and the fix removes the cause
of that hang, but the suite has at least one other load-sensitive test — a 0.2 s bound with 5 s of
headroom in `ScreenRecordingProbeWiringTests` — that can fail on this machine at load average 800
without touching the signature path. The run count is reported with what failed on each run rather
than as a bare fraction, so a reader can tell the two apart.

## Out of scope

The forged peer's 10 s timeout. `Server.dispatchBlocking`. The cost of `SecStaticCodeCheckValidity`.
`ScreenRecordingProbeWiringTests`'s bound, which is a separate flake and is named rather than fixed.
