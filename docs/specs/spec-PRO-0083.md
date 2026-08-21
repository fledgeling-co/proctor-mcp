# PRO-0083 — The ten external effects a capped gate output hid

**Status:** To Do → Ready for AI · **Brief:** `docs/features-to-triage/76-the-ten-the-capped-gate-hid.md`
(Wave 11, brief 7 of 7) · **Branch:** `ai/pro-0083` off `ai/wave-9`
**Ledger id:** allocated upstream. This item does not write `docs/feature-specs/LEDGER.md`.
**Ranges:** cases CASE-0080..0099 · defects DEF-040..049 · requirements REQ-050..052.

## The denominator, stated first

```
$ python3 -c "import json; d=json.load(open('docs/test-campaign/inventory.json'));
  ext=[r for r in d['requirement'] if r.get('effect') not in (None,'none')]; print(len(ext))"
22
```

Twenty-two external requirements, counted with `len()` over the registry. `campaign.py check`
prints at most twelve of them, and briefs `70` and `71` read that printed list as the population.
PRO-0077 took four and PRO-0078 took eight; the ten this item takes — REQ-023, 024, 027, 028, 029,
033, 034, 035, 037, 039 — were named by no item in the wave.

The cause is not carelessness. It is that a number taken from a tool's display is not a
denominator, and this one was one `len()` away the whole time. `REPORT.md` records the census
denominator as that `len()` rather than as whatever the gate printed, so the same cap cannot
under-scope a wave again in silence.

## Scope

Ten `effect-witness` cases, one per requirement. No case covers two requirements: they are
different guarantees over shared providers, and a shared case would let one guarantee's silence
hide behind the other's noise.

Each case owes what `campaign.py set` refuses without — a recorder, an effect class and a non-zero
count — and the four-part causal shape from `references/effect-boundary.md` §5: driven from a
production entry point, recorded at the boundary, confirmed by something that is not the code
under test, and flipped by its own sabotage.

**Out of scope, stated so it stays out.** REQ-007, whose `inconclusive` PRO-0078 recorded against a
real ceiling — `PersonInput.isAPerson` demands `sourcePid == 0` (`Contention.swift:265`) and
`ContentionMonitor.considerInput:199` guards on it, both re-read here in source. A ceiling that was
measured stays measured. Also out: any product behaviour change. `sharingType = .none` on the HUD
and the takeover overlay is correct and is not touched — evidence must not change because somebody
was watching.

## The lanes, and why they split

Eight of the ten run headless under `./scripts/test.sh`, in one new test file beside PRO-0077's.
Two do not:

| Req | Lane | Why |
|---|---|---|
| REQ-023 | `headless` | needs `ProctorReflector` on the test target's dependency list |
| REQ-028 | `macos-glass` | the recorder is the window server, which needs a display server |

REQ-023's lane change is one line in `Package.swift` adding `ProctorReflector` to
`ProctorAgentTests`' dependencies. It changes no production source and no shipped artifact:
`ProctorReflector` already compiles to nothing without `DEBUG` or `PROCTOR_REFLECTOR`, and
`scripts/build-app.sh` already fails a release artifact carrying it.

## The eight headless witnesses

### W1 — REQ-035 · `ipc` · which front end called, read from the peer

**First, because its wrong answer is a security answer.** The claim is that the trail records the
front end from the peer *process* and never from the request, so a CLI call cannot enter the record
as something else.

**Drive.** A real `Server(dispatcher:path:)` on a temporary socket, with the session's audit sink
set to the production `AuditLog.append` and `AuditLog.seams.directory` redirected to a temporary
trail. Two genuinely different front ends are spawned as real child processes against that socket:
`.build/<config>/proctor-cli` and `.build/<config>/proctor-shim`, both built by the same
`swift build --build-tests` that builds this suite, both pointed at the socket with
`PROCTOR_SOCKET`. A third child is the forgery arm: a copy of one front end at a path whose last
component is neither shipped name, sending a request whose body claims `via: "cli"`.

**Recorder.** The trail's bytes on disk, read with a fresh `FileHandle` and opened with
`AuditSeal` and the injected private half — never `AuditLog.readTrail`, which is the reader under
test confirming itself. Every `via` in the trail came from `SessionIdentity.frontEnd(for:)`, which
reads `proc_pidpath` of the pid `getsockopt(SOL_LOCAL, LOCAL_PEERPID)` reported for the accepted
descriptor. Neither value was on the wire.

**Count.** Sealed records on disk whose `via` names a front end, matched against which child
process the call came from.
**The claim proved.** `cli` for the `proctor-cli` child, `mcp` for the `proctor-shim` child, and
**absent** for the forger, whose request asked for `cli`. Same wire bytes, different peers,
different rows.
**Sabotage.** Unlink the socket between `start()` and the children. Nothing connects, nothing is
accepted, no peer is read and the trail holds zero rows.

### W2 — REQ-034 · `ipc` · the operator CLI on the same socket

`proctor-cli` is a second front end on the agent's socket, and the claim is 21 verbs derived from
the tool catalogue, six exit codes, and completion generated from the same catalogue.

**Drive.** The real `proctor-cli` binary as a child process against a real `Server`, once per
outcome class.
**Recorder.** Two things neither of which is the CLI: the exit status the kernel reports through
`waitpid`, and the server's own record of the connection it answered. `CLISurface.Exit` is read as
the *specification* the child's status is checked against, never as the measurement.
**Count.** Distinct exit codes observed from real children, and connections the server answered.
**Sabotage.** With no socket bound, the same verb exits `agentUnreachable` (3) rather than `ok`,
and the answered-connection count is zero.

### W3 — REQ-029 · `ipc` · an operator over SSH watches and halts

**Drive.** A real `Server`, a real `SocketClient.watch()` held open on its own thread, frames
published through `SupervisionBroadcast.shared`, then a `proctor.control` `stop` sent over a second
real connection.
**Recorder.** The frames that arrived on the held connection, counted client-side, and the latch
read from `RunControl.shared` — which is neither the client nor the transport. The latch is
restored before the test returns, because it is process-wide and PRO-0053 recorded a suite that
reached another suite through it.
**Count.** Supervision frames delivered over the socket, and halts landed.
**Sabotage.** Unlink the socket first: the watch cannot connect, zero frames arrive, and the latch
does not move.

### W4 — REQ-033 · `ipc` · readiness, switches and history, not only run and queue

Its own case rather than a slice of W3: the guarantee is about *what a supervision client can
read*, and folding it into the watch would let an empty readiness projection hide behind a
non-zero frame count.

**Drive.** The TUI's own two calls over a real socket — `proctor_doctor` and `proctor_history` —
against a real `Server`, then `TUISurface.readiness(from:)`, `switches(from:)` and `history(from:)`
over the replies.
**Recorder.** The reply bytes off the socket, and the three projections' row counts.
**Count.** Non-empty rows across readiness, switches and history.
**Sabotage.** The same projections over a refusal reply return zero rows and set
`historyUnreadable`, which is the distinction the field exists for.

### W5 — REQ-027 · `ipc` · a held socket that never answers

The failure this names is not a killed agent — that fails `connect()` at once. It is an agent that
accepts and never replies, which is what used to latch `isChecking` and freeze the last good
report.

**Drive.** A listener the test owns — `Darwin.bind`/`listen`/`accept` with no reply written, which
is not the code under test — and a real `SocketClient` against it.
**Recorder.** The stalling listener's own accepted-descriptor count, and the wall-clock the client
spent before giving up, bounded by `SO_RCVTIMEO`.
**Count.** Connections accepted and deliberately never answered.
**Sabotage.** The same client against a real `Server` gets an answer inside the bound, so the
timeout is reading the peer's silence rather than a clock.

### W6 — REQ-037 · `ipc` · steps executed inside a guest

**Drive.** Two real servers. One plays the guest agent on its own temporary socket; the host
`Session` is attached to it through `SocketGuestLink`, and a forwardable tool is driven through the
host's entry point.
**Recorder.** The guest server's own dispatcher, which records what arrived over the forwarded
socket, plus the host's `FakeAX` actuation counter — because the second half of the claim is that
the host actuates *nothing* on the guest's behalf.
**Count.** Requests the guest server answered over the forwarded socket, with the host's local
actuation count at zero beside it.
**Sabotage.** Unlink the guest socket: the link refuses with `GuestLinkRefusal.unreachable` naming
the socket, and nothing is forwarded.

### W7 — REQ-039 · `subprocess` · the pool never evicts

**Drive.** `Session.guest(action:)` with providers built by the **convenience** initialiser, so
`run` binds to `Self.liveRun` and reaches a real `Process()` through `Session.runBounded`. The
executable is a `/bin/sh` script that writes a sentinel naming its own `$$` and the argv it was
given.

**Recorder.** The sentinel files, read back off the filesystem — the same recorder PRO-0077 used,
carrying argv this time so a stop is distinguishable from a list.
**Count.** Stop invocations that actually reached a child process, read out of the sentinels.
**The two-way, which is the whole guarantee.** An evictable guest driven through
`stopGuestThroughAuditedPath` leaves a stop sentinel and an audited row; a guest a person started
or another session holds, driven identically, leaves **no** stop sentinel and no stop row. Same
call, one field different, opposite outcome — so the never-evict rule is reading ownership rather
than a clock.
**Sabotage.** Point the executable at a path that does not exist: the count goes to zero while the
call still returns.

### W8 — REQ-024 · `subprocess`, as declared · and what was actually measured

REQ-024 declares `subprocess` and the census names `Process()` in `Actuation/CuaClients.swift` as
its provider. **Neither is reached by the browser-routing path**, and this item establishes that in
source rather than asserting it:

- `BrowserTarget` is pure, by its own header: "The agent supplies what it read from the
  accessibility tree as a `WebContentProbe`; this file decides."
- `Session.browserHandoff` returns a disclosure that `SessionAct` and five other call sites attach
  to a reply. Nothing executes.
- `ToolProbe`'s header reads "Whether Obscura is on this machine, cached, **and never executed**",
  and `ToolLocator.locate` decides availability with `isExecutable(path)` — a stat, not a spawn.
- No file under `Sources/` spawns `obscura` or `browser-use`. The `Process()` sites are the guest
  providers, simctl, the cua driver, `shortcuts run`, the dictionary, the installer and the UI.

So the only boundary this capability crosses is a **filesystem read**, and the campaign's closed
class list (`subprocess`, `outbound-socket`, `inbound-socket`, `packet-filter`, `multicast`,
`filesystem-write`, `device`, `ipc`, `none`) has no member for it.

**What this item does.** It measures the boundary that is actually crossed, resolves REQ-024
`inconclusive:` naming the instrument, and records the miscategorisation as a defect. It does not
rewrite REQ-024's registry row, does not mark it `n/a`, and does not change its effect class —
including not changing it to `none`, which would silence the gate rather than answer it.

**The measurement.** Two temporary directories on a real filesystem: one holding an executable
named `obscura` with no `obscura-worker` beside it, one holding both. The production
`ToolProbe.obscuraOnDisk` path is driven through `ToolLocator.locate` with those directories, and
the answer changes with what is on disk in a way no input can compute: the incomplete directory
yields `missingCompanions: ["obscura-worker"]`, the complete one yields none, and `chmod 0000`
takes availability to false. That is a real read of a real filesystem with a two-way sabotage; it
is recorded as evidence under an `inconclusive` case rather than as a witness of the class REQ-024
declares.

## The two off-lane witnesses

### W9 — REQ-023 · `ipc` · the Reflector's own socket

A second socket, not the agent's. `ProctorReflector/SocketServer.swift` binds, listens, `chmod
0600`s and accepts on its own concurrent queue, and answers `hierarchy`, `node`, `idle`, `revision`
and `ping` over the same 4-byte length-prefixed JSON.

**Drive.** `ProctorReflector.start(socketPath:)` on a temporary path inside the test process, whose
real `NSView` tree is what gets walked, and real clients connecting over the real socket.
**Recorder.** The replies read back off the socket, and the `hierarchy` payload's resolved values —
frames, colours and layer models that came from AppKit's own computation rather than from anything
the test set. Plus the socket file itself at mode `0600`, read with `stat`.
**Count.** Connections the reflector answered, and resolved nodes in the walk.
**Sabotage.** `ProctorReflector.stop()` unlinks the socket; `connect()` then fails and both counts
go to zero.

**The ceiling.** Server and client are the same process here, so what is witnessed is a real
`AF_UNIX` round trip through the kernel and a real AppKit walk — not a cross-process one. Recorded
as the lane's ceiling rather than left implied.

### W10 — REQ-028 · `device` · overlays excluded from capture

The brief's warning is the design constraint. PRO-0078 found `proctor_capture` reporting
`status: complete, trustworthy: true` over a fully transparent frame of a Proctor-owned window
(DEF-025, open). The exclusion working and the capture path not noticing that exclusion was all it
got are the same mechanism from two sides, so a blank frame proves nothing here.

**What the witness must show, both halves in one frame.** A non-Proctor window captured **with
content**, proved by strings a third process read out of that application's own accessibility
server — and a Proctor overlay that the window server says was on screen at that moment absent from
the same frame.

**Recorder.** `CGWindowListCopyWindowInfo` read by `witness_probe windows`, for what was on screen
and at what `sharingState`; `screencapture` run by the probe process, for the frame; and
`witness_probe axtext` for the subject's text. None of the three is Proctor's capture path.
**Count.** Proctor-owned on-screen windows at `sharingState` 0 that are absent from a frame proved
to contain another application's content.
**Sabotage.** The same region captured with the overlay down is compared against the same region
captured with it up. Identical pixels while the window server reports the overlay on screen is the
exclusion; a difference would be the overlay reaching the frame.

**If the lane cannot be established**, REQ-028 resolves `inconclusive:` with the instrument named.
It is never marked `n/a` and its class is never changed.

### A source finding this item carries whatever REQ-028's lane does

`RunHUDPanel.swift:374` and `TakeoverOverlay.swift:705` both set `panel.sharingType = .none`.
`CursorOverlay.build(for:)` sets `isOpaque`, `backgroundColor`, `hasShadow`, `isFloatingPanel`,
`hidesOnDeactivate`, `isReleasedWhenClosed`, `ignoresMouseEvents`, `level` and
`collectionBehavior` — and no `sharingType`. `grep -rn sharingType Sources/` returns four hits and
none of them is the drawn pointer.

DEF-005, "The drawn pointer was not excluded from screen capture", is recorded `fixed` against
REQ-028. The third of REQ-028's three surfaces is capturable in the tree as it stands, and DEF-028
records an agent window at `sharingState 1` as open. Recorded as its own defect rather than fixed
here: this item adds evidence, and a surgical fix to an overlay's sharing behaviour is a product
change that belongs with its own item.

## Acceptance

| # | Clause | Evidence |
|---|---|---|
| A1 | Two real front-end children over one socket produce trail rows reading `via: cli` and `via: mcp`, read off disk with a fresh descriptor | W1 witness run |
| A2 | A child that is neither shipped front end, sending a request claiming `via: cli`, produces a row with `via` absent | W1 forgery arm |
| A3 | Unlinking the socket takes W1's row count to zero | W1 sabotage |
| A4 | Real `proctor-cli` children produce distinct `CLISurface.Exit` codes read through `waitpid`, over connections the server counted | W2 witness run |
| A5 | With no socket bound the same verb exits 3 and the answered count is zero | W2 sabotage |
| A6 | Supervision frames arrive over a held connection and a `stop` over a second one moves `RunControl.shared`, restored before return | W3 witness run |
| A7 | Readiness, switches and history all project non-zero rows from replies read off the socket | W4 witness run |
| A8 | A listener that accepts and never answers is given up on inside its bound, and a real server answers inside the same bound | W5 both arms |
| A9 | A forwardable tool reaches a second real server over the forwarded socket while the host's local actuation count stays zero | W6 witness run |
| A10 | A held or person-started guest leaves no stop sentinel where an evictable one leaves one, from the same call | W7 two-way |
| A11 | REQ-024's measurement is recorded, its case resolves `inconclusive` with the instrument named, and its registry row is unchanged | W8 + `git diff` |
| A12 | The Reflector's own socket answers real connections and returns resolved AppKit values; `stop()` takes both counts to zero | W9 both arms |
| A13 | REQ-028 either witnesses content-and-absence in one frame or resolves `inconclusive` naming the instrument | W10 |
| A14 | Ten cases in `cases.json`, ids within CASE-0080..0099, appended only, each with a recorder, a valid effect class and — where passing — a non-zero count | `campaign.py check` |
| A15 | `REPORT.md` records the external denominator as `len()` over the registry | REPORT.md diff |
| A16 | `./scripts/test.sh` exits 0, with the suite count before and after | its verdict line |
| A17 | `inventory.json` and `cases.json` are appended to only; no row this item did not create is reformatted or re-sorted; `docs/feature-specs/LEDGER.md` untouched | `git diff` |

`./scripts/test.sh` owns the verdict. A bare `swift test` exits 1 while reporting every test
passing, because the pipe eats the exit code.

## Failure modes this spec is written against

**A witness whose recorder is the driver.** Every count above is read from a channel other than the
code under test, or the case says which half stays self-reported.

**A zero that is structural.** PRO-0078's probe counted survivors by a mark the tagged arm could not
carry, so it read 0 whatever happened. Every sabotage here is paired with the arm that makes the
same recorder read non-zero, so a zero is a measurement.

**A count that is a subtraction.** Every count is read out of a recorder's own output and quoted in
the case note with the field it came from.

**A denominator taken from a display.** The census's own number is computed with `len()`.

**Asserting a value the test itself wrote.** DEF-019's shape. W1's `via` is the sharpest instance:
the value asserted is one the kernel produced about a process the test spawned but never described
to the server.

## What was measured

| Case | Req | Effect | Count | Recorder |
|---|---|---|---:|---|
| CASE-0080 | REQ-035 | `ipc` | 3 | sealed trail rows on disk, fresh `FileHandle`, opened with `AuditSeal` |
| CASE-0081 | REQ-034 | `ipc` | 3 | `waitpid` exit status of real `proctor-cli` children, plus answered connections |
| CASE-0082 | REQ-029 | `ipc` | 3 | frames delivered on a held connection, and `RunControl.shared` |
| CASE-0083 | REQ-033 | `ipc` | 20 | reply bytes off the socket, projected by `TUISurface` |
| CASE-0084 | REQ-027 | `ipc` | 3 | a stalling listener's own accepted-descriptor count |
| CASE-0085 | REQ-037 | `ipc` | 3 | the guest server's dispatcher, host actuation count zero beside it |
| CASE-0086 | REQ-039 | `subprocess` | 7 | sentinels carrying each child's `$$` and its argv |
| CASE-0087 | REQ-024 | `subprocess` | 0 | `inconclusive` · DEF-040 |
| CASE-0088 | REQ-023 | `ipc` | 3 | replies off the Reflector's own socket, decoded by `JSONSerialization` |
| CASE-0089 | REQ-028 | `device` | 2 | window server list, `screencapture -l`, the target's AX server, `CGImageSource` |

Every count came off an arming run with the non-zero assertion inverted, so the run printed the
number the recorder actually saw. None was chosen in advance.

**A9 landed as W9's own finding.** CASE-0088's first run asked the Reflector for
`"constraints": true` and got no constraints key at all — `Runtime.decode(options:)` reads
`"includeConstraints"`. A constraints assertion on that request would have read zero for a
wire-protocol reason and been taken for a product one. The same shape as PRO-0078's survivor mark.

**The resolved values REQ-023 claims, none of them written by the test.** The label came back at
`(x 22.0, y 272.0, w 110.5, h 16.0)`. The width is AppKit's measurement of the string; `y + h` is
288, the relation the solver produced over a height nothing in the test named. The `x` is **not**
the constraint's constant of 24 — `NSTextField`'s alignment rect is inset from its frame, so the
solver satisfies the constraint on the alignment rect and the frame lands to its left. That gap is
the clearest evidence in the case that the number came back from AppKit rather than from the
request. `labelColor` resolved against the effective appearance to `#FFFFFF`, catalog `System`,
name `labelColor`. Two constraints, `leading` and `top`, both active.

**A11's outcome, and the shape of the answer.** REQ-024 resolves `inconclusive`. Its declared class
and provider name a boundary the browser-routing path never crosses; the only boundary it does
cross is a filesystem read, for which the campaign's closed class list has no member. The read was
measured and recorded under the `inconclusive` case; the registry row is unchanged. DEF-040 records
the miscategorisation, DEF-041 the capped gate output that caused this brief.

**A13's outcome.** REQ-028 passes with both halves in one second: two Proctor-owned windows on
screen at `sharingState` 0 that `screencapture -l` refused outright, and Activity Monitor's window
delivered with 3,159 distinct colours whose content an independent AX client corroborated by text.

**The gates.** `campaign.py check`: `examined=22 witnessed=20`, up from 11; still exits 1, and
correctly, over REQ-007 and REQ-024. `strict-check` 79 of 81, ratchet 70 → 79 in the same commit.
`capture-lineage --gate` exit 0 at ratchet 5, published 7 · distinct 7 — unmoved, because
CASE-0089's frame is a case-level artifact rather than a surface `shot`, and the counts were read
before and after rather than assumed.

**Production source unchanged.** `Package.swift` gains `ProctorReflector` on `ProctorAgentTests`'
dependency list, which is a build-graph edge: the Reflector compiles to nothing without `DEBUG` or
`PROCTOR_REFLECTOR`, and `scripts/build-app.sh` already fails a release artifact carrying it. No
`Sources/` file was edited by this item.

## What it cost to make the gate return a verdict

The nine headless witnesses passed in their own run from the first build and stopped
`./scripts/test.sh` returning a verdict at all. That is recorded here rather than in a runner's
report, because the cause is a property of this suite that the next person adding an integration
test will meet.

**The measurement.** `sample` on the wedged process, repeatedly, across samples seven minutes
apart with the same thread ids in the same frames and 3.4 seconds of CPU consumed in twelve minutes
of elapsed time: fourteen to fifteen of the sixteen cooperative-pool threads inside
`Session.doctor` → `SignatureVerdictCache.verdict` → `CuaPreflight.verifySignature` →
`SecStaticCodeCheckValidity`, across `BrowserLaneWiringTests`, `ObscuraPresenceWiringTests`,
`ScreenRecordingProbeWiringTests`, `GuestDoctorWiringTests`, `MachineDisclosureWiringTests`,
`DoctorReplyWiringTests` and `ToolchainOnThisMachineTests`. `codesign -v` on the same binary
answered instantly from a shell throughout, so the system was not the bottleneck. DEF-043.

**Attribution was measured at each step rather than assumed.** `--skip` over this item's two suites
passed at 1,818 tests in 12.5 seconds while the full run never returned; the same comparison was
then re-run at load average 500 so that machine load could be ruled out as the confound, and the
skip run still passed in 26 seconds. Three separate causes were found and each was narrowed the
same way — skip one test, run, sample.

**The three fixes, all in the tests and none in the product.**

1. **Blocking work moved onto threads the tests own.** `drive` waits on a child process for
   seconds; `askWithBound` waits two seconds on a socket that never answers by design; `W7` blocked
   on a semaphore while its own work ran on the same pool. All of it now runs through `offPool`,
   which is the shape `Server.dispatchBlocking` already uses and for the same reason. The two pipe
   drains moved off `DispatchQueue.global()` too, because that is the same libdispatch pool
   `SecStaticCodeCheckValidity` needs a worker from.
2. **`TrailIsolation` held only across code that never suspends.** Every trail suite here blocks in
   `acquire()` from a cooperative thread, so a holder that suspends is betting it can get a slot
   back while two of the sixteen are blocked waiting on it. `withRedirectedTrailBlocking` acquires,
   redirects, runs a synchronous body and releases, all on one owned thread; the async setup moved
   out above the call. The async variant was deleted rather than left available.
3. **The witness sessions given probes that answer from a table.** `ToolProbes(environment: [:])`
   locates the real `cua-driver` on this Mac, so every `proctor-cli doctor` child made the server
   run a real signature check too — one more concurrent `verifySignature` on an already-full pool.
   It is also simply the right probe: a witness that a CLI call crosses a socket has no business
   validating a third-party binary, and a test whose result depends on what is installed is not a
   measurement of the product.

**A test wrote the operator's real policy file.** Reaching exit code `refused` needs
`policy --action configure`, and `PolicyStore` has no `seams.directory` — `AuditLog` has one, and
an `isTestProcess` interlock besides. The witness created
`~/Library/Application Support/app.fledgeling.procter/policy/policy.json` with its own bundle id
blocked; PRO-0077's REQ-015 witness then failed with `policyDenied` in a later run where this
item's suites were skipped, because the block had outlived the process. The entry was removed from
the operator's file and the configure dropped. CASE-0081 records that `refused` is unreachable from
that lane and why. DEF-042.

**Everything was re-armed after the rewrite**, because the rewrite changed every body. Each count
was re-established on the code as it now stands, and each sabotage removed again and watched to
fail — and that second pass caught an arming that could not fire, W3's dead watch pointed at a
socket whose server had already been stopped. Evidence:
`evidence/PRO-0083/arming-counts-after-refactor.txt` and `arming-sabotage-after-refactor.txt`.

**The suite:** 1,818 tests in 215 suites → **1,827 in 217**, exit 0, three consecutive green runs
at load averages 485, 622 and 500. `evidence/PRO-0083/suite-before-after.txt` and `gate.txt`.

## What the resume corrected

The run recorded in the section above did not reproduce. On a clean tree the full suite failed
twice, identically, at 143 seconds with four issues, and wedged outright at higher load. The item
was not finished; it was finished-looking, and the difference was one gate run.

**The forging arm was the load, and its own claim was weaker than it read.** `driveBlocking`
terminated the imposter child at its 120-second bound — status 15 is SIGTERM — while the same test
passed alone in 0.416 seconds. The hard link was supposed to have removed the first launch, and it
does not: a hard link at a **fresh path** is a first launch for `syspolicyd` however the inode is
shared, and this suite runs beside seven wiring suites that hold fifteen of the sixteen cooperative
threads inside `SecStaticCodeCheckValidity` at once. Separately, `--via` is not a flag
`proctor-cli` parses — `grep -rn via Sources/ProctorCLI/` returns nothing — so the arm described as
"a request asking to be recorded as `cli`" never put that ask on the wire at all.

**Both were fixed by removing the launch.** The forging peer is now a raw AF_UNIX client that is
the test process itself: `proc_pidpath` reports `proctor-mcpPackageTests`, which
`SessionIdentity.frontEnd(named:)` maps to nil, so it is the same third peer at no launch cost. And
because it hand-frames its own request, the ask is real — the frame's JSON carries `"via":"cli"` at
the top level of the very object the server decodes, and `AgentRequest` has no such field. Re-armed
by inverting three assertions: the peer **was** answered, `ForgedCall(answered: true, ok: true)`,
and its row reads `[nil]` from those bytes. The run went 143s → 16.4s, four issues → one, then
green: **1,827 tests in 217 suites, exit 0, 21.376 seconds at load average 176.**

**The remaining risk is named rather than absorbed.** `ScreenRecordingProbeWiringTests`'s "a
platform call that never answers returns unconfirmed within the bound" asserts `elapsed < 5.0`. At
load ~200 with this item's two suites **skipped entirely** it takes 5.393 seconds; at load 22 it
takes 0.655. It is a tight bound on a loaded machine rather than anything this item introduced, and
attribution was measured both ways rather than argued. DEF-044 records the mechanism underneath it:
`SignatureVerdictCache.verdict` releases its lock before calling `verify`, so concurrent callers
with cold caches all verify at once. A per-instance single-flight would not close it, because the
fifteen verifications come from fifteen separate Session caches each missing legitimately once — the
dedupe would have to be process-wide, which is a design change and not this item's to make. No file
under `Sources/` was edited.
