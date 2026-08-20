# Plan — PRO-0077: effect witnesses off glass

**Spec:** `docs/specs/spec-PRO-0077.md` · **Brief:** `docs/features-to-triage/70-effect-witnesses-off-glass.md`
**Tier:** Small. One new test file, no production source changed, four campaign rows.

## Shape

One new `Tests/ProctorAgentTests/EffectWitnessTests.swift`, one `@Suite`, four witnesses. The
suite is `.serialized` because W3 redirects `AuditLog`'s process-wide seams and W4 binds a socket
and starts threads; W3 additionally takes `TrailIsolation`, which is the interlock every
trail-touching suite in this target already takes.

Each witness is one `@Test` that runs the effect and then its own sabotage in the same body, so
the arming evidence and the passing evidence are the same measurement taken twice. Recording them
separately would let the two drift onto different builds.

## Seams used, all of them already in the tree

| Witness | Production entry point | Seam that redirects it | Reaches |
|---|---|---|---|
| W1 | `Session.guest(action:)` | `setGuestProviders` + `LumeProvider(executable:timeoutMs:)` | `Session.runBounded` → `Process()` |
| W2 | `Session.ios(action:)` | `ToolProbes(simctl:)` with an injected probe | `Session.runSimctl` → `runBounded` → `Process()` |
| W3 | `Session.act` etc., sink set to `AuditLog.append` | `AuditLog.seams.directory`/`.signer`/`.anchors`/`.keys` | `Darwin.open`/`write`/`fsync` in `PolicyStore.swift` |
| W4 | `Server.start()` + `SocketClient.connect()/send()` | `Server(path:)` on a temp path | `Darwin.bind`/`listen`/`accept`/`connect` |

W1 takes the **convenience** initialiser deliberately. The three-argument
`init(executable:timeoutMs:run:)` is the fake seam and would prove nothing about spawning.

## Steps

1. **Shared helpers.** A `witnessScript(at:sentinelDir:stdout:)` writing an executable `/bin/sh`
   script that appends `sentinel-$$` holding its own `$$`, then prints a fixed payload; and a
   `sentinels(in:) -> [pid]` reading the directory back with `FileManager` and `Data(contentsOf:)`.
   Both are test-local.
2. **W1.** Script prints a lume listing `[{"name":"witness-guest","os":"macOS","state":"stopped"}]`.
   Drive `list` then `status`. Read sentinels, assert non-zero, assert every pid distinct and none
   equal to `ProcessInfo.processInfo.processIdentifier`. Then a second sentinel directory, a
   provider pointed at `<dir>/absent`, the same two calls, assert zero sentinels and that the
   `list` call still returned a result carrying `providerErrors`.
3. **W2.** Script prints a `{"devices":{…}}` payload `IOSDeviceList.parse` accepts. `Session`
   built with `ToolProbes(simctl: ToolProbe(probe: { ToolPresence(tool:"simctl", available:true,
   path: script) }))`. Drive `ios(action:"list")` twice. Same assertions. Sabotage points the
   probe at `<dir>/absent`; `readDevices` throws, caught, sentinels zero.
4. **W3.** Follow `AuditChainWiringTests.withTrail` exactly — temp directory, `TrailIsolation`,
   an in-suite `TestSigner`, `audit.pub` written before the first seal — plus
   `AuditLog.seams.keys = TestSealKeys()` so the lines can be opened. Set the session's sink to
   `{ _ = AuditLog.append($0) }`, drive an audited action, then: `FileManager` attributes for size
   and mtime before and after, `FileHandle(forReadingFrom:)` for the bytes, `AuditSeal.open` per
   line with the injected private half. Sabotage `chmod 0500` on the directory, restore in
   `defer`, assert no file and count zero.
5. **W4.** `FakeAX` subclass (or a recording wrapper) capturing `SessionIdentity.current` on
   `listApps`. `Server(dispatcher: Dispatcher(session:), path: <temp>.sock)`, `start()`, three
   `SocketClient`s each `connect()` + `send(proctor_apps)`. Assert three `ok` replies, three
   recordings, each naming this process's pid and cwd. `stop()` in `defer`. Sabotage: `start()`,
   `unlink(path)`, one `connect()` — expect a throw, zero recordings.
6. **Run `./scripts/test.sh`** and read its verdict line, not XCTest's summary.
7. **Record four campaign rows** with `campaign.py add --kind case` then `campaign.py set …
   --oracle effect-witness --recorder … --effect-class … --effect-count … --armed`, using the
   counts the passing runs actually produced. Append only; never reformat or re-sort
   `campaign.json` or `inventory.json`, which two other Wave 11 items also write.
8. **Evidence bundle** under `docs/test-campaign/evidence/PRO-0077/`: the gate output, the two
   runs per witness, and a `README.md` naming what each file is.

## Test strategy

**Prove each check can fail before trusting it passing.** That is what the sabotage half is, and
it is inside the same test rather than beside it. Uniform zeros are the signature of a dead
predicate, so each witness asserts a non-zero count on the live run and an exactly-zero count on
the sabotaged one; a witness that reported zero on both would be a check measuring nothing.

**Never assert a value the test itself wrote** (DEF-019). Each recorder is checked against this:
W1 and W2 read a pid the shell child wrote with `$$`; W3 reads bytes `Darwin.write` put on disk
and opens them with a different module from the reader under test; W4's identity comes from
`getsockopt(LOCAL_PEERPID)` and `proc_pidinfo`, which the client never sends.

**Characterise, do not assert-correct.** Nothing in `Sources/` is edited. A product bug these
witnesses surface gets its own defect record rather than a fix folded in here.

**Denominators.** The lane is the portable floor and it is recorded as such: no kernel tracer, no
`eslogger`, no privileged census. That is the lane's ceiling, not a gap left silently.

## Risks

- **Process-wide state.** `AuditLog.seams`, `AuditLog.state` and `TrailIsolation` are shared
  across suites. Mitigated by `.serialized` plus the existing lock, and by restoring every seam in
  `defer`.
- **Socket path length.** `sockaddr_un.sun_path` is 104 bytes. The temp path must stay short —
  `/tmp/pw-<8 hex>.sock` rather than a nested `NSTemporaryDirectory()` UUID path.
- **A stray server thread.** `Server.stop()` in `defer`, and the sabotage run's server stopped
  too.
- **Counts asserted before they are measured.** The spec deliberately does not name the numbers.
  They are read off the passing run and only then written into the campaign.

## What this plan does not do

The other eight requirements, the 78 blind-pass findings, and `--seed-strengthen` all belong to
PRO-0078, PRO-0079 and PRO-0080. No requirement's effect class is changed. No gate is edited.
