# PRO-0089 — Tests that touch the real machine, and tests that time themselves

**Status:** To Do → Ready for AI · **Brief:**
`docs/features-to-triage/82-tests-that-touch-the-real-machine-and-tests-that-time-themselves.md`
· **Lane:** headless `./scripts/test.sh` · **Branch:** `ai/pro-0089`
· **Wave 13 ranges:** CASE-0130..0139 · DEF-065..069 · REQ-055..056
· **Ledger id:** allocated upstream, not written here.

## What this closes

DEF-042, and DEF-029/DEF-051. Two defects that share one property: the suite makes a claim about
the machine it runs on rather than about the product.

| Defect | Where | What is wrong |
|---|---|---|
| DEF-042 | `Sources/ProctorAgent/Session/PolicyStore.swift:12-37` | `PolicyStore` is an `enum` of statics whose `directory` is computed from `homeDirectoryForCurrentUser`. There is no seam. A test that configures the policy writes the operator's real policy file. |
| DEF-029 / DEF-051 | `Tests/ProctorAgentTests/ScreenRecordingProbeWiringTests.swift:42` | `#expect(elapsed < 5.0)` against real elapsed time. Six recorded failures this wave at 5.6s, 6.1s, 6.58s, 8.13s, 10.25s and 14.73s; passes in 1.8s alone. |

## Measured before any change

`Wire.bundleIdentifier` is `app.fledgeling.procter` (not a typo — `SwitchStore.swift:19` records
why), so the operator's policy on this Mac is
`~/Library/Application Support/app.fledgeling.procter/policy/policy.json`. It exists: 52 bytes,
mtime 1787282863, sha256 `0c8dcc7f659233bb084de793108ababf973bfc5cb2cbbd6964209a60ed01524d`.
That is a real file this suite can damage today.

`PolicyStore.save` is reached from exactly one production path,
`Session.configurePolicy` (`SessionPolicy.swift:345`), which the `proctor_policy` action
`configure` dispatches (`Dispatch.swift:571`). **No test calls it today**, which is why the
damage has not been observed — the hazard is that the first test to configure a policy gets it,
and this item adds tests that configure a policy.

**The population of wall-clock assertions is two, not three.** A grep over `Tests/` for
`elapsed`, `timeIntervalSince`, `CFAbsoluteTimeGetCurrent`, `DispatchTime.now`,
`ContinuousClock`, `SuspendingClock` and `uptimeNanoseconds` returns 2 assertions of measured
elapsed time against a numeric literal, out of 20 sites that mention a clock at all:

| Site | Assertion |
|---|---|
| `ScreenRecordingProbeWiringTests.swift:42` | `#expect(elapsed < 5.0)` |
| `CuaLineReaderTests.swift:107` | `#expect(Date().timeIntervalSince(started) < 2)` |

Everything else that touches a clock injects one (`RunControl(now:)`, `RunScheduler(now:)`,
`Session.setClock`) or feeds a literal `elapsedMs` into a record it then formats. The brief's
"two other tests" is one more than the tree holds; the full enumeration is above and the count is
`len()` of the grep, not a sample.

## Behaviour

### A1 — `PolicyStore` takes its root, and a test process cannot reach the operator's

`PolicyStore` becomes a `struct` with `let directory: URL`, mirroring
`GuestProvider(executable:timeoutMs:run:)` and `SignatureVerdictCache(identify:verify:)`: an
instance told its dependency, beside a `static let live` binding the real one.

`Session` gains `var policyStore: PolicyStore = .live` and a `setPolicyStore(_:)` seam in the
same block as `setAuditSink` and `setClock`. `loadPolicyIfNeeded` and `configurePolicy` go
through it.

**And `live` carries the same interlock `AuditLog` carries in the file above it.** In a test
process `PolicyStore.live` resolves to a per-process temporary directory rather than to the
operator's. Injection is the mechanism; the interlock is the floor, and it earns its place for
the reason `AuditLog.isTestProcess` records: a suite that forgets to inject must not be one
forgotten line away from writing real state. `PolicyStore.operatorDirectory` stays available and
always names the real path, so a test can read what it must not touch.

**Not by write-then-restore.** A restore that does not run leaves the policy changed and says
nothing.

### A2 — the bounded-probe test asserts the bound fired, not how long it took

`ScreenRecordingProbe` gains a `timer` seam: `@Sendable (Double) async -> Void`, defaulting to
`Task.sleep`. It is the arm that resumes the continuation with `.unconfirmed`, so injecting it
makes "the bound fired" observable directly instead of inferred from a stopwatch.

The converted test injects a timer that records the duration it was asked to wait and returns,
against a platform call that never answers, and asserts two things: the answer is `.unconfirmed`,
and the timer was asked for `GrantProbe.bound` — the product's own constant, not a number the
test wrote. A second test parks the timer forever against a platform that answers, so the race is
pinned in both directions. Neither test reads a clock.

**The bound is not raised.** `GrantProbe.bound` stays 1.5.

### A3 — the second wall-clock assertion is converted with it

`CuaLineReader` gains `now: @Sendable () -> UInt64`, defaulting to
`DispatchTime.now().uptimeNanoseconds` — the monotonic source it already uses, made injectable.
The deadline test drives that clock instead of the machine's, and gets a two-way control it did
not have: with a stepping clock the reader gives up once the budget it was given is spent, and
with a frozen clock it does not give up at all, so a line arriving 300ms late is still returned.
On the real clock that second case is a timeout, which is what makes it discriminating rather
than decorative.

## Acceptance

| # | Clause | Oracle |
|---|---|---|
| A1 | With `Session.setPolicyStore` pointed at a temporary directory, `configurePolicy` writes that directory and the operator's real `policy.json` is unchanged — asserted by reading its mtime and its bytes before and after, not by trusting the seam | outcome |
| A2 | `PolicyStore.live` in a test process does not resolve under the operator's Application Support directory, so a session built with no injection cannot write it either | outcome |
| A3 | A never-answering platform call returns `unconfirmed` because the bound timer fired, proved by the timer being asked for `GrantProbe.bound`, with no clock read | outcome |
| A4 | A platform answer inside the bound wins even when the timer never fires | outcome |
| A5 | `CuaLineReader` gives up when the budget on its injected clock is spent, and does not give up while that clock is frozen | metamorphic |
| A6 | `grep` for a measured elapsed time compared against a numeric literal in `Tests/` returns zero, and the count is the whole population rather than a sample | static-analysis |
| A7 | `./scripts/test.sh` green, and green again under deliberate load, with the run count stated | outcome |

## Out of scope

`SignatureVerdictCache` and the cooperative-pool starvation (PRO-0087 owns both). Raising any
timeout or bound. `AuditLog`, whose seam already exists and works.
