# plan-PRO-0083 — ten effect witnesses

**Spec:** `docs/specs/spec-PRO-0083.md` · **Tier:** Large · **Branch:** `ai/pro-0083`
**Ranges:** CASE-0080..0099 · DEF-040..049 · REQ-050..052.

## Order, and why it is this order

1. **W1 (REQ-035)** first. It is the security claim, and it establishes the two apparatus pieces
   six of the ten reuse: a real `Server` on a temporary socket, and a real front-end child spawned
   against it with `PROCTOR_SOCKET`.
2. **W2, W3, W4, W5** — the four remaining agent-socket guarantees, each reusing W1's apparatus
   with a different driver on the near side.
3. **W6, W7** — guest link and guest pool.
4. **W8** — REQ-024's measurement and its `inconclusive`.
5. **W9** — the Reflector socket, which needs the `Package.swift` line.
6. **W10** — the glass lane, last, because it is the one that can fail for a reason that is not
   about the product.

## Files

| Path | Change |
|---|---|
| `Tests/ProctorAgentTests/ExternalWitnessTests.swift` | new; W1–W8 |
| `Tests/ProctorAgentTests/ReflectorWitnessTests.swift` | new; W9 |
| `Package.swift` | one line: `ProctorReflector` onto `ProctorAgentTests` dependencies |
| `scripts/campaign/overlay_witness.sh` | new; W10's glass harness |
| `docs/test-campaign/cases.json` | ten appended rows |
| `docs/test-campaign/inventory.json` | appended defect rows only |
| `docs/test-campaign/REPORT.md` | the `len()` denominator, and this item's section |
| `docs/test-campaign/evidence/PRO-0083/` | runs, sabotage runs, gate output |
| `CHANGELOG.md` | `[Unreleased]`, prose through `/create-luke-content` |

No production source is edited. `Package.swift` is a build-graph line, not behaviour: the
Reflector already compiles to nothing without `DEBUG` or `PROCTOR_REFLECTOR`, and
`scripts/build-app.sh` already fails a release artifact carrying it.

## Seams, named from source

**Finding the front-end binaries.** `swift build --build-tests` puts `proctor-cli`, `proctor-shim`
and the `.xctest` bundle in the same directory (measured: all three in `.build/debug` after a
27.5s build). The test locates that directory with `Bundle(for:)` on a local `NSObject` subclass,
which yields the `.xctest` bundle URL; its parent is the product directory. A missing binary is a
failed test, never a skipped one — an absent check is not a passing check.

**Pointing a front end at a private socket.** `Wire.socketPath` reads `PROCTOR_SOCKET` first
(`Wire.swift:18`), so a child spawned with that variable talks to the test's server and never to
the installed agent.

**Reading the peer.** `Server.acceptLoop` calls `SessionIdentity.fromPeer(of: client)` on the
accepted descriptor (`Server.swift:126`) and binds the result as a task-local for the request
(`Server.swift:270`). `frontEnd(for:)` maps `proc_pidpath`'s last component: `proctor-cli` → `cli`,
`proctor-shim` → `mcp`, anything else → nil.

**Stamping the trail.** `AuditLog.append` calls `stamping(record, frontEnd:
SessionIdentity.current.frontEnd)` (`PolicyStore.swift:232`), and `stamping` leaves an already-named
`via` alone (`:261`). The forgery arm therefore has to send a request that would *become* a record
with `via` set; it cannot, because nothing on the wire reaches that field on this path. That is the
claim, and the arm is what proves it rather than assumes it.

**Trail isolation.** `AuditLog.seams` is process-wide. Reuse PRO-0077's `withRedirectedTrail`
shape verbatim: acquire `TrailIsolation` on a dedicated `Thread` and run the async body under a
semaphore. An async holder of that lock wedged the whole suite for 40 minutes on 2026-08-21.

**Socket paths.** `sockaddr_un.sun_path` is 104 bytes, so `/tmp/pw-XXXXXXXX.sock`, as PRO-0077.

**The process-wide latch.** `Server.serve` routes `proctor.control` to
`SupervisionControl.perform(request)`, which defaults to `RunControl.shared` (`Server.swift:175`).
W3 therefore reads and restores that latch, and its suite is `.serialized`.

**The guest link.** `SocketGuestLink` holds a `SocketClient` at the forwarded path
(`GuestLink.swift:76`), and `GuestLink.shouldForward` decides what crosses. The guest side is a
second `Server` with its own `Session`, so what the guest answered is recorded by the guest's own
dispatcher.

**The guest pool.** `stopGuestThroughAuditedPath` (`SessionGuest.swift:610`) is the single audited
stop, reached by the release path, the failed-attach cleanup and the boot that never came up. The
never-evict rule sits above it. Sentinels carry argv so a stop is distinguishable from a list.

## Risks, and what each costs

| Risk | Mitigation |
|---|---|
| The front-end binaries are absent from the product directory | fail with the directory listing, never skip |
| A real `proctor-cli` child hangs | bounded wait then `SIGKILL`, and the bound is asserted |
| `RunControl.shared` leaks into another suite | read, restore, `.serialized`, and assert restoration |
| `ProctorReflector.start` needs a main-thread AppKit hop | drive from a dedicated thread with a run loop, as `Runtime.onMain` expects |
| The glass lane cannot be established | REQ-028 resolves `inconclusive` naming the instrument |
| `campaign.py add --kind defect` reindents `inventory.json` | check `git diff --stat`; revert and append in the file's own format |

## Definition of done

`./scripts/test.sh` green with the suite count before and after; ten appended case rows inside the
allocated range; `campaign.py check` re-run and its witnessed count quoted; `capture-lineage.py
--gate` exit 0 if any capture is published; `REPORT.md` carrying the `len()` denominator; every
count in every case note read off an arming run rather than chosen in advance.
