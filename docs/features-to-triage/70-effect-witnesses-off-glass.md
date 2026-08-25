---
sources: [REQ-009, REQ-015, REQ-017, REQ-020]
status: retired
validated-by: REQ-009, REQ-015, REQ-017, REQ-020 via CASE-0011, CASE-0017, CASE-0019, CASE-0022, CASE-0028, CASE-0059
validated-rungs: effect-witness, outcome
validated-provider: Darwin.bind/listen/accept in Sources/ProctorAgent/Server.swift; Darwin.connect in Sources/ProctorCore/Transport.swift
---
# Effect witnesses for the four effects that need no window server

**Wave 11, brief 1 of 4.** Build this first. `71` is the same job on the glass lane and can
run beside it; `72` and `73` both read the instrument this brief exercises.

## The measurement

The 0.9.2 campaign added an effect-boundary census, and Proctor's first run of it reads:

```
vacuity: requirements=44 external=22 findings=78
campaign.py check: External-effect claims with no witness (0 of 22 witnessed)
```

Forty-four requirements, twenty-two of which claim an effect outside the process, and not one
case anywhere in the campaign stands at the `effect-witness` rung. The oracle mix is
`outcome 44 · metamorphic 5 · raster-visual 8 · interactive-glass 1`.

This is not the failure the census exists to catch. In the reference case a product claimed
network isolation with no HTTP client in its dependency tree, so the guarantee was true because
nothing crossed the boundary. Proctor has a real provider for every class it claims, all twelve
grep-verified into production source. What is missing is the asking: every one of those twelve
guarantees currently rests on a test that called a function and read the value the function
returned.

Twelve requirements are named by the gate. Eight of them need a display server and belong to
`71`. These four do not:

| Req | Effect | Provider in production source |
|---|---|---|
| REQ-017 | `subprocess` | `Process()` in `Sources/ProctorAgent/Guest/GuestProvider.swift` — lume/prlctl/tart argv built and executed |
| REQ-020 | `subprocess` | `Process()` in `Sources/ProctorAgent/Session/SessionIOSProcess.swift` — simctl and maestro |
| REQ-015 | `filesystem-write` | `data.write(to:options:.atomic)` in `Sources/ProctorAgent/Session/PolicyStore.swift`; key material in `Session/AuditKeyStore.swift` |
| REQ-009 | `ipc` | `Darwin.bind/listen/accept` in `Sources/ProctorAgent/Server.swift`; `Darwin.connect` in `Sources/ProctorCore/Transport.swift` |

## What a witness owes

A case at this rung carries three things `campaign.py set` will refuse without: a **recorder**,
an **effect class**, and a **non-zero count**. A witness that saw nothing is the condition being
tested, not the proof of it.

The four-part causal shape, and each part is separately checkable:

1. The effect is driven from a **production entry point**, not by calling the adapter directly.
2. The attempt is recorded at the boundary.
3. Completion is confirmed by **something other than the code under test**.
4. Sabotage flips it — break the thing that performs the effect and the witness goes to zero.

The kernel bar is `dtrace`/`eslogger`, which needs privilege this suite does not have. Work to
the portable floor instead: a real spawned process that writes a sentinel the test reads back,
a real file read with a fresh handle rather than through the writer's own API, a real loopback
listener logging its accepts. No kernel, no privilege, and none of them can pass when nothing runs.

## The four witnesses

**REQ-017, guest routing.** `GuestProvider.swift` already has the seam. Each of the three
adapters carries `init(executable:timeoutMs:run:)` beside a `convenience init(executable:timeoutMs:)`
that binds `run` to `Self.liveRun`, and `liveRun` goes through `Session.runBounded` to a real
`Process()`. Take the convenience initialiser — the production path — and point `executable` at
a script that writes a sentinel file containing its own pid. Drive it through `Session.guest(action:)`
rather than by calling `invoke` directly, so part 1 holds. The recorder is the sentinel plus the
pid it names; the count is the number of sentinels. Sabotage: point `executable` at a path that
does not exist, and the count goes to zero while the call still returns a `GuestProcessResult`.

**REQ-020, iOS simulator driving.** `SessionIOSProcess.swift` has the same shape at the simctl
and maestro call sites. Same witness, same sabotage. Keep it separate from REQ-017's rather than
sharing one case: they are different providers and a single case covering both would let one
provider's silence hide behind the other's noise.

**REQ-015, the audit trail.** Drive an audited action through the production sink, then read the
trail off disk with a fresh `FileHandle` — never through `PolicyStore`'s own read path, because
that is the code under test confirming itself. The recorder is the file's size and mtime before
and after plus its decrypted chain; the count is the number of appended records. Sabotage: point
the store at a read-only directory and the count stays at zero.

**REQ-009, the agent socket.** Bind a real `AF_UNIX` socket through `Server.swift`, connect to it
through `Transport.swift`, and let the server's accept path log what it accepted. The recorder is
the accept log, which is the server rather than the client; the count is accepts. Sabotage: unlink
the socket path between bind and connect.

## The conversion contract

- One new `Tests/ProctorAgentTests/EffectWitnessTests.swift`, four witnesses, each with its
  sabotage run recorded in the campaign as the arming evidence.
- Each case recorded with `campaign.py set --oracle effect-witness --recorder … --effect-class …
  --effect-count …`, the count being the number the recorder actually saw on the passing run.
- Nothing in the four touches a display server, so they run under `./scripts/test.sh` on any
  machine, including CI.
- `scripts/test.sh` owns the verdict. A bare `swift test` exits 1 while reporting every test
  passing, because the pipe eats the exit code.
- Run `vacuity-check.py docs/test-campaign --seed-strengthen REQ-017` before trusting the census
  gate's passing state. That control belongs to `73` and is named here because this brief is what
  it would be checking.

## What this brief does not do

It does not close the other eight requirements, and it does not touch the 78 blind-pass findings.
Recording a requirement as `none` to keep `campaign.py check` green is off the table: the twelve
demands are the gate doing its job, and a class changed to silence a gate is a finish line that moved.
