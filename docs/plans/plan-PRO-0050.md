# Plan — PRO-0050: Doctor knows the whole toolchain

**Spec:** `docs/specs/spec-PRO-0050.md`
**Branch:** `ai/pro-0050` · **Worktree:** `.worktrees/PRO-0050` (rebased onto `d65dc1e`, PRO-0044)
**Tier:** Standard — one new pure module, five touched files, one shell script, one generated file.

## Shape

The report shape is the deliverable. Everything that decides anything is **pure and lives in
`ProctorCore`**, so it tests without a window server, a permission, a subprocess or a
machine that has any of these tools: the toolchain definition, the evidence ladder, the lane
derivation, the policy redaction, the install-layout version reads, and the shell-fragment
renderer. `ProctorAgent` supplies the filesystem answers and the memoised lane report and
does no deciding.

**Nothing on the doctor path creates a process.** The only new I/O is `stat`, `readlink`, one
plist read, and a cached signature verification through `SecStaticCode` — which reads a file
and executes nothing. That is a source-level clause, tested the way PRO-0048 tests that no
`shutdown` argument is ever constructed.

## Steps

### 1. `Sources/ProctorCore/ToolPresence.swift` — the usability axis

Add two enums and five optional fields; change no existing meaning.

```swift
public enum ToolUsability: String, Codable, Sendable { case usable, unusable, unconfirmed }

/// What was consulted, weakest first. The floor for a located tool is `presence`:
/// a row saying nothing is known about a file we just found reads as a bug.
///
/// `laneReport` is deliberately not called `selfReport`: nothing here asks a tool
/// about itself. It is populated only from a preflight that already ran because
/// the lane was *used*, so it is Proctor's record of a completed act, never a
/// question doctor asked.
public enum ToolEvidence: String, Codable, Sendable {
    case absent, presence, signature, installPath, laneReport
}
```

`ToolPresence` gains `usability`, `evidence`, `version`, `detail`, `checkedAt`, all optional
so an older agent's report still decodes and this one decodes against the shipped shim. The
existing initialiser keeps its signature and defaults them to nil; a second initialiser takes
them. `available` keeps its documented meaning verbatim — add a line to its comment saying
usability is the axis beside it, not a redefinition.

### 2. `Sources/ProctorCore/Toolchain.swift` (new) — one definition of the toolchain

The single list this feature exists to stop duplicating. Per tool: the display name, the
binary, its companions, its search route (`commonDirectories` or `developerDirectory`), which
lane needs it, and whether presence alone settles usability.

```swift
public struct ToolchainEntry: Sendable { … }
public enum Toolchain {
    public static let entries: [ToolchainEntry]   // obscura, browser-use, simctl, cua-driver, maestro
    public static func shellFragment() -> String  // renders scripts/generated/toolchain-search.sh
}
```

`shellFragment()` renders the directory list and the per-tool binary/companion names as shell
arrays, with a generated-file header naming the regeneration command. It renders **no**
usability and **no** developer-directory route — the spec's two deliberate exclusions.

Also here, because they are pure and belong beside the entries:

- `versionFromInstallPath(symlinkTarget:)` — pulls `2.4.0` out of `../Cellar/maestro/2.4.0/bin/maestro`,
  and returns nil for a target with no version-shaped component. Injected string in, optional
  out; no filesystem.
- `xcodeVersionPlistPath(developerDirectory:)` — the sibling `version.plist` path.

### 3. `Sources/ProctorCore/Wire.swift` — lanes and posture on the report

```swift
public struct Lane: Codable, Sendable {
    public var lane: String        // mac | browser | ios | cua
    public var state: String       // ready | unavailable | unconfirmed
    public var ready: Bool         // derived, fail-closed: state == ready
    public var requires: [String]
    public var blockers: [String]
    public var note: String?
}
public struct PolicyPosture: Codable, Sendable {
    public var mode: String        // allowList | blockOnly | open
    public var allowCount, blockCount, sensitiveCount: Int
    public var approvalTokenLive: Bool
    public var fsJailDeclared: Bool
    public var fsRootCount: Int
    public var auditWritable, auditSealed, auditSigned, auditClean, auditKeyConfirmed: Bool
    public var auditEntries: Int
    public var auditDroppedThisRun: Int?
    public var note: String        // "Shape and posture only …"
}
```

`DoctorReport` gains `lanes: [Lane]` and `policy: PolicyPosture?`, both optional-safe for an
older shim. `PolicyPosture` has **no** initialiser taking an `AppPolicy` — it is built by the
pure derivation in step 4, so there is exactly one place a rule could leak from.

### 4. `Sources/ProctorCore/Toolchain.swift` — the two derivations

- `Lane.derive(tools:grants:secondLane:cuaLaneSelected:cuaHealth:)` → `[Lane]`, pure. The mac
  lane reads the grants: a required grant that is `unconfirmed` yields `unconfirmed`, one that
  is `denied` yields `unavailable`. `ready` is computed, never passed in.
- `PolicyPosture.derive(allow:block:sensitive:tokenLive:fsRoots:audit:)` → `PolicyPosture`,
  pure, taking counts and booleans **only**. Its parameters cannot carry a bundle id, a path
  or a token, so clause 12 is a property of the signature as much as of the test.
- `Toolchain.row(entry:facts:)` → `ToolPresence`, pure. **The probe gathers facts; this
  decides.** The review found usability and evidence being stamped at probe time in the impure
  half, which is the same defect this file exists to avoid. So `ToolProbe` returns only what
  it observed — the located path, the symlink target, the signature verdict, the memoised lane
  health — and every `usability`, `evidence` and `detail` value is chosen here, where it tests
  without a filesystem.

### 5. `Sources/ProctorAgent/Session/SignatureVerdictCache.swift` (new)

Wraps `CuaPreflight.verifySignature` behind a cache keyed on the file's **identity**, not on
its timestamp alone: `(path, device, inode, size, mtime, ctime)`. The review was right that a
`(path, size, mtime)` triple aliases two different binaries — a same-second write, a
`copyfile` or `utimes` that preserves mtime, and an unlink-and-recreate all defeat it. `ctime`
is the one field a user cannot set with `utimes`, and the inode catches replacement in place.

A reference type with an `NSLock`, held outside the actor the way `ToolProbe` and
`GrantProbeKeeper` are — `Session` is reentrant and the 2.0 s poll re-enters. Two rules the
review forced, and they are the same rule the grant keeper already follows:

- **No `await` inside the critical section**, so the lock is never held across a suspension
  and cannot deadlock against the poll.
- **The 0.32–0.39 s verification runs outside the lock.** Claim, verify, then store — holding
  the lock across the hash would serialise every doctor call behind one cache miss.

The cached verdict **never authorises anything**: `CuaPreflight` re-verifies immediately
before it executes. What it is, exactly, is a statement about the file as it stood at
`checkedAt`, and the report says so rather than implying the file is still that file.

### 6. `Sources/ProctorAgent/Session/ToolProbe.swift` — two more tools

Add `maestroOnDisk()` and `cuaDriverOnDisk()` using `ToolLocator` with `Toolchain`'s entries,
and add both to `ToolProbes` with the long TTLs the non-Obscura tools already use. Maestro's
row resolves its symlink and fills `version` + `evidence: .installPath`; the simctl row gains
Xcode's version from the plist. Both readers are injected.

### 7. `Sources/ProctorAgent/Actuation/ActuationBackend.swift` — one protocol member

```swift
/// What this backend has established about itself, for proctor_doctor. Nil when
/// nothing has been established yet — never a probe triggered by asking.
var laneHealth: ActuationLaneHealth? { get async }
```

Default `nil` in a protocol extension, so `NativeActuationBackend` is untouched.
`CuaActuationBackend` maps its memoised `CuaLaneReport` into `ActuationLaneHealth` — path,
parsed version, overrides, recognised vocabulary, driver-reported grant booleans, and the
failing stage when preflight refused. **The mapping drops every driver-supplied string**;
that is the injection clause, and it is enforced by the struct's fields rather than by care.

### 8. `Sources/ProctorAgent/Session/SessionDoctor.swift` — assembly only

Refresh the presences (as today), read the signature verdict for the driver from the cache,
read `actuator.laneHealth`, and hand all of it to the pure derivations. No new branch decides
anything here. `ready` and `blockers` are not touched.

### 9. `Sources/ProctorAgent/Session/SessionPolicy.swift` — `policyPosture()`

A sibling of `policyStatus()` that passes counts and booleans to the pure derivation.
`policyStatus()` is unchanged — narrowing it is child work, not this item.

### 10. `Sources/ProctorCore/ToolOutputSchemas.swift` and `ToolCatalogue.swift`

Describe `lanes`, `policy` and the tool-row fields, and say in the description that doctor
runs nothing: a model that reads "usability: unconfirmed" needs to know the remedy is to use
the lane, not to call doctor harder.

### 11. `scripts/generated/toolchain-search.sh` (new, committed) and `scripts/doctor.sh`

The fragment is rendered by `Toolchain.shellFragment()` and committed so the script works
from a fresh clone. `doctor.sh` sources it, and per tool prints presence plus the
**disagreement**: a login-`PATH` hit in a directory outside Proctor's list is a warning
naming both paths, because that is the "but it *is* installed" failure. It makes no claim
about usability and says so.

### 12. Tests

`Tests/ProctorCoreTests/ToolchainTests.swift` — the evidence ladder and its floor; the row
derivation across every fact combination; the lane derivation across grants × tools including
the unconfirmed-grant case; the posture derivation; **the redaction test that encodes a
posture built beside a policy holding known bundle ids, roots and a scoped token and asserts
none of those strings appear in the bytes**; the install-path version parse and its nil cases;
and the drift test.

**The drift test does two things, because one is escapable.** It compares the rendered
fragment to the committed file, *and* it asserts `scripts/doctor.sh` sources that exact path —
so pointing the shell doctor at a different file reddens the build rather than quietly
orphaning the generated one. The review was right that string-equality alone only ratchets;
this does not make it unbypassable, and the plan does not claim it does.

`Tests/ProctorAgentTests/ToolchainDoctorTests.swift` — every tool has a row in a fixed order;
browser-use still absent with the lane off; the driver's row across absent / present-unsigned
/ present-signed / preflight-established; the cache verifying once and re-verifying when the
file's identity changes; a lane report whose driver strings are instruction-shaped producing
none of that text in the encoded report; `ready` unchanged with every tool missing.

The no-subprocess clause is a **source-level tripwire, not a proof**, and is written that way:
it scans the doctor path for `Process(`, `Process.init`, `NSTask`, `posix_spawn` and `/bin/sh`.
A determined indirection defeats it; what it catches is the thing that actually happens, which
is somebody later adding a version probe to a health check without noticing the rule.

`scripts/doctor.sh` gets a shell-level check driven from the test suite via a temporary
directory: a fake tool on a fake `PATH` outside the list must produce the disagreement line.

## Verification

`swift build` and `swift test`, with the counts read back — a `--filter` matches the Swift
function name, not the `@Test` display string, so a filtered run reports `with N tests` and
that number is checked before any green is believed. Then a live `proctor_doctor` call
against the installed agent to see the new blocks on a real machine (cua-driver absent,
maestro present, Xcode present), which is the one thing a unit test cannot show.

## Plan review — grok-4.6, 2026-08-15

Out of family, per the fleet contract. The first attempt returned narration and no findings —
a lane failure, not a pass — and was retried with an explicit instruction not to read files.
Four findings, all four accepted, and each changed the plan above rather than being noted.

| # | Severity | Finding | What changed |
|---|---|---|---|
| 1 | High | A lock held across the 0.32–0.39 s verification serialises every doctor call behind one cache miss, and a lock held across an `await` could deadlock against the 2.0 s poll. | Claim, verify **outside** the lock, then store. No `await` inside the critical section — the rule `GrantProbeKeeper` already documents. The `@unchecked Sendable` + `NSLock` shape itself is kept: it is the pattern `ToolProbe` and `GrantProbeKeeper` already ship. |
| 2 | High | `(path, size, mtime)` aliases two different binaries — a same-second write, a `copyfile`/`utimes` that preserves mtime, an unlink-and-recreate. | The key becomes `(path, device, inode, size, mtime, ctime)`. `ctime` cannot be set with `utimes`; the inode catches replacement in place. The residual — a verdict is about the file as it stood at `checkedAt` — is stated rather than implied. |
| 3 | High | Usability and evidence are decided at probe time, in the impure half; and `selfReport` has no reachable implementation under a no-subprocess rule, so it reads as either a hidden exec or a dead field. Also, `available` means two different things on a tool row and a lane row. | The probe returns facts only; `Toolchain.row(entry:facts:)` decides. The rung is renamed `laneReport` and documented as a completed preflight rather than a question doctor asked. The lane's boolean becomes `ready`. |
| 4 | Medium | The drift test only ratchets, and the `Process(` scan misses `posix_spawn` and `/bin/sh`. | The drift test also asserts the shell doctor sources that exact path. The scan is widened, and both are described as tripwires rather than proofs. |
