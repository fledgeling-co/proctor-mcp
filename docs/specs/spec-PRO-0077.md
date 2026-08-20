# PRO-0077: effect witnesses for the four effects that need no window server

**ID:** PRO-0077 · **Status:** Ready to verify · **Created:** 2026-08-21
**Brief:** `docs/features-to-triage/70-effect-witnesses-off-glass.md` (Wave 11, brief 1 of 4)
**Branch:** `ai/pro-0077` off `ai/wave-9` · **Lane:** headless, `./scripts/test.sh`
**Requirements:** REQ-017, REQ-020 (`subprocess`), REQ-015 (`filesystem-write`), REQ-009 (`ipc`)
**Ledger id:** already allocated by the orchestrator. This item does not write `docs/feature-specs/LEDGER.md`.

## The problem

The 0.9.2 campaign added an effect-boundary census. Proctor's first run of it reads:

```
vacuity: requirements=44 external=22 findings=78
campaign.py check: External-effect claims with no witness (0 of 22 witnessed)
```

Forty-four requirements, twenty-two claiming an effect outside the process, and no case anywhere
in the campaign at the `effect-witness` rung. The oracle mix is `outcome 44 · metamorphic 5 ·
raster-visual 8 · interactive-glass 1`.

This is not the vacuity the census exists to catch. In the reference case a product claimed
network isolation with no HTTP client in its dependency tree, so the guarantee held because
nothing crossed the boundary. Proctor has a real provider for every class it claims, all twelve
grep-verified into production source. What is missing is the asking: each of those twelve
guarantees currently rests on a test that called a function and read the value the function
returned.

Twelve requirements are named by the gate. Eight need a display server and belong to PRO-0078.
These four do not.

## Scope

Four `effect-witness` cases, one per requirement, in one new test file, each recorded in the
campaign with a recorder, an effect class and a non-zero count, and each with its own sabotage
run as arming evidence. Deliver that and nothing wider.

**Out of scope, stated so it stays out.** The other eight requirements (PRO-0078). The 78
blind-pass findings (PRO-0079). The `--seed-strengthen` control (PRO-0080). Recording any
requirement's effect class as `none` to make `campaign.py check` green — the twelve demands are
the gate working, and a class changed to silence a gate is a finish line that moved.

## What a witness owes

A case at this rung carries three things `campaign.py set` refuses without: a **recorder**, an
**effect class**, and a **non-zero count**. A witness that saw nothing is the condition under
test, not the proof of it.

The four-part causal shape, each part separately checkable:

1. the effect is driven from a **production entry point**, not by calling the adapter directly;
2. the attempt is recorded at the boundary;
3. completion is confirmed by **something other than the code under test**;
4. sabotage flips it — break the thing that performs the effect and the count goes to zero.

**The lane's ceiling is the portable floor, and it is recorded as such.** `dtrace` and `eslogger`
need privilege this suite does not have and SIP does not grant. So: a real spawned process that
writes a sentinel the test reads back, a real file read with a fresh descriptor rather than
through the writer's own API, and a real loopback listener answering real connections. No kernel,
no privilege, and none of the four can pass when nothing runs.

## The four witnesses

### W1 — REQ-017, `subprocess`, guest routing

**Seam.** Each of the three adapters in `Sources/ProctorAgent/Guest/GuestProvider.swift` carries
`init(executable:timeoutMs:run:)` beside `convenience init(executable:timeoutMs:)`, which binds
`run` to `Self.liveRun`. `liveRun` goes through `Session.runBounded` to a real `Process()`. The
witness takes the **convenience** initialiser, because that is the production path; the
three-argument one is the fake seam and proves nothing about spawning.

**Drive.** `session.setGuestProviders([LumeProvider(executable: script)])`, then
`session.guest(action: "list", …)` and `session.guest(action: "status", …)` — the tool's own
entry point, never `invoke` directly. `executable` is a `/bin/sh` script that writes
`sentinel-$$` containing its own `$$` and prints a lume listing on stdout.

**Recorder.** The sentinel files, and the pid each one names. A pid written by `$$` inside a
`/bin/sh` child is a value no Swift in this process produced.
**Count.** The number of sentinels the directory holds after the run.
**Confirmed by.** Not the code under test: the test reads the directory and each file's bytes,
and checks every pid differs from this process's own and from every other sentinel's.
**Sabotage.** Point `executable` at a path that does not exist. `Session.runBounded` catches the
spawn failure and returns `exitCode: -1`, so the call still yields a `GuestProcessResult` and
`guest(action:"list")` still returns — with the sentinel count at zero.

### W2 — REQ-020, `subprocess`, iOS simulator driving

`Sources/ProctorAgent/Session/SessionIOSProcess.swift` reaches `Process()` through the same
`runBounded`, at the simctl and maestro call sites. Kept as its own case rather than folded into
W1: they are different providers, and one case covering both would let one provider's silence
hide behind the other's noise.

**Drive.** A `Session` built with `ToolProbes(simctl:)` reporting the witness script as present,
then `session.ios(action: "list", …)` — the `proctor_ios` entry point. The script writes the same
kind of sentinel and prints a `simctl list -j devices` payload.

**Recorder, count, confirmation, sabotage.** As W1, with the sabotage pointing `simctl` at a path
that does not exist; `readDevices` then raises the tool's own "simctl could not list devices"
refusal and the count stays zero.

### W3 — REQ-015, `filesystem-write`, the audit trail

**Drive.** An audited action through `Session`, with the sink set to the production
`AuditLog.append` and `AuditLog.seams.directory` pointed at a temporary trail. The seam is the
test-process interlock in `Session.auditSink`, not the write path: `AuditLog.append` seals, signs,
chains, and lands the bytes with `Darwin.open(O_WRONLY|O_APPEND|O_CREAT)`, `Darwin.write` and
`fsync` in `PolicyStore.swift`. That is the production write, unchanged.

**Recorder.** The trail file's existence, byte size and mtime before and after, plus its contents
read with a **fresh `FileHandle`** — never `AuditLog.readTrail` or `openedTail`, which are the
code under test confirming itself. Each line is opened with `AuditSeal.open` in ProctorCore using
the injected private half, which is a different module from the reader under test.
**Count.** The number of appended records, counted as newline-terminated lines in the file.
**Confirmed by.** The bytes on disk and CryptoKit, neither of which is `PolicyStore`'s read path.
**Sabotage.** `chmod 0500` on the trail directory. `withAuditFileLock` cannot create `audit.lock`
and `appendRawLocked` cannot `O_CREAT` the trail, so the append returns false, no file appears,
and the count stays zero.

### W4 — REQ-009, `ipc`, the agent socket

**Drive.** A real `Server(dispatcher:path:)` on a temporary path — `Darwin.bind`, `listen`,
`chmod 0600` and an accept loop, all in `Sources/ProctorAgent/Server.swift` — with three separate
`SocketClient` instances from `Sources/ProctorCore/Transport.swift` each calling `connect()`
(`Darwin.connect`) and `send()`.

**Recorder.** Two halves, both server-side. The **count** is the number of distinct client
connections the server answered: a reply cannot arrive on a descriptor the accept loop never
took, so an answered connection is an accept. The **identity** half is what the server read off
each accepted descriptor — `SessionIdentity.fromPeer` calls
`getsockopt(SOL_LOCAL, LOCAL_PEERPID)` and `proc_pidinfo`, and the resulting
`RunSessionIdentity` is bound as a task-local for the whole request, so the session's injected
engine records it inside the server process. That value names this test process's real pid and
working directory, and the client never puts either on the wire.

**Count.** Three answered connections, and three recorded peer identities.
**Sabotage.** `unlink` the socket path between `start()` and the first `connect()`.
`Darwin.connect` fails with `agentUnavailable`, nothing is accepted, and both counts stay zero.

**Why the count is answered connections and not recorded identities.** `Server.serve` reads many
frames from one accepted descriptor, so a per-request record counts requests rather than accepts,
and one client sending three frames would report three. The two are asserted together and only
the connection count is the accept count. Settled by an out-of-family referral to `grok-4.6` at
`xhigh` on 2026-08-21, which also ruled out adding an `onAccept` seam to `Server`: a hook the
product fires is the product logging its own accept, and the answered connection needs no
production change at all.

## What the witnesses do not claim

- **A witness proves the effect, not its correctness.** A recorded spawn says a process ran.
  Whether the argv was right is a different case at a different rung.
- **A count is not a distribution.** One non-zero count on one run is one draw.
- **The lane cannot reach the kernel.** No `execve` census, no `bpf`, no `eslogger`. Recorded as
  the lane's structural ceiling rather than left as silence about which bar was used.
- **Nothing here changes production source.** All four drive existing seams.

## Acceptance

| # | Clause | Evidence |
|---|---|---|
| A1 | `guest(action:)` spawns real children through the convenience initialiser; sentinel count non-zero and every pid distinct from this process's | W1 passing run |
| A2 | Pointing `executable` at a missing path drives W1's count to zero while the call still returns | W1 sabotage run |
| A3 | `ios(action:"list")` spawns a real child through `runSimctl`; sentinel count non-zero | W2 passing run |
| A4 | A missing `simctl` drives W2's count to zero | W2 sabotage run |
| A5 | An audited action lands sealed records the test reads back with a fresh descriptor and opens with `AuditSeal`; size and mtime move | W3 passing run |
| A6 | A read-only trail directory drives W3's count to zero and creates no file | W3 sabotage run |
| A7 | Three client connections are answered over a real `AF_UNIX` socket, and the server records a kernel-read peer identity naming this process | W4 passing run |
| A8 | Unlinking the socket between bind and connect drives both W4 counts to zero | W4 sabotage run |
| A9 | Four `effect-witness` rows in `campaign.json`, each with a recorder, an effect class and a non-zero count | `campaign.py check` |
| A10 | `./scripts/test.sh` green | its verdict line |

`./scripts/test.sh` owns the verdict. A bare `swift test` exits 1 while reporting every test
passing, because the pipe eats the exit code.


## What was measured

| Case | Req | Effect class | Count | Recorder |
|---|---|---|---|---|
| CASE-0059 | REQ-017 | `subprocess` | 2 | sentinel files, each holding the child's own `$$` |
| CASE-0060 | REQ-020 | `subprocess` | 2 | the same, at the simctl call site |
| CASE-0061 | REQ-015 | `filesystem-write` | 3 | the trail's bytes via a fresh `FileHandle`, opened with `AuditSeal` |
| CASE-0062 | REQ-009 | `ipc` | 3 | connections the server answered, plus the peer identity read off each accepted fd |

Every count came off the arming run, where the non-zero assertion was inverted so the run prints
the number the recorder actually saw. None was chosen in advance.

`campaign.py check --json`, same inventory, `cases.json` swapped: `effect-witness` 0 → 4,
witnessed 0 of 22 → 4 of 22, requirements claiming an effect with no witness 16 → 12. The gate
still refuses over the twelve that remain, which is the gate working and is out of this item's
scope.

`./scripts/test.sh`: **1818 tests in 215 suites passed**, 0 issues.

## Two findings flagged rather than fixed

**Wave 11 leaves four requirements uncovered.** The brief reads "twelve requirements are named by
the gate"; the gate's printed list is capped at twelve and the real count was sixteen. PRO-0078
names eight of the twelve that remain, so REQ-023, REQ-024, REQ-027 and REQ-028 belong to no item
in this wave.

**`Session.runBounded` can answer exit 0 with empty stdout under load.** Its drain is bounded at
five seconds after the child exits, on the global concurrent queue, so a starved drain turns a
successful child into a silent empty read. Observed here on 2026-08-21; the same class is already
recorded in the comment on `IOSDeviceList.parse`, dated 2026-08-20. Pre-existing, and the reason
both subprocess witnesses stand on the child's filesystem effect rather than its stdout.

**No production source was changed by this item.**
