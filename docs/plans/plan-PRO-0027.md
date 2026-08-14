# Plan — PRO-0027: The menu bar shows the character when idle

**Spec:** `docs/specs/spec-PRO-0027.md`
**Branch:** `ai/PRO-0027` · **Worktree:** `.claude/worktrees/pro-0027`
**Tier:** Small. Five changes, three of them in Core where they are testable.

The diagnosis is done and is in the spec: none of the brief's three causes is live,
and the reported symbol was a menu bar app that had been running for eight hours
before the character existed. What follows is the work that finding implies.

The out-of-family plan review landed four changes and they are folded in below —
the shim is gone rather than kept, the rung fails closed on a blocker it does not
recognise, the stamp covers the art as well as the binary, and the relaunch is a
real relaunch rather than a line in a table.

## 1. The rung is computed, total, and fails closed — `ProctorCore/RunHUDMenuBar.swift`

```swift
/// Why the menu bar cannot show the character yet.
public enum MenuBarBlock: Sendable, Equatable {
    case missingGrant      // exclamationmark.triangle
    case secureInput       // lock.laptopcomputer
}

public extension MenuBarIcon {
    /// Ordered, and total. A missing permission outranks a locked keyboard: one is
    /// a Mac that will never work, the other is a Mac that is busy. And a `ready`
    /// that is false for a reason this function does not recognise reads as a
    /// missing grant rather than as nothing — a rung whose job is to keep a calm
    /// face off a Proctor that cannot work must fail closed, or the next blocker
    /// added to the doctor silently puts the character back up.
    static func block(requiredGrantsGranted: Bool, secureEventInputActive: Bool,
                      ready: Bool) -> MenuBarBlock?
}

public static func decide(reachable: Bool, block: MenuBarBlock?, phase: RunHUDPhase,
                          takingForeground: Bool = false) -> MenuBarIcon
```

The old `decide(reachable:ready:…)` is **deleted**, not kept as a forwarding shim.
Keeping it would have preserved the ~20 existing assertions by asserting the very
mapping this spec calls wrong, which the review named and was right about. Every
existing call site moves to `block:`; `foregroundSitsBetweenReadinessAndThePhase`
keeps its name and its assertion — the order it pins is unchanged — and is expressed
with `.missingGrant`.

Where the block sits in the ladder is now written down: it is rung two, so Secure
Event Input outranks both the foreground notice and the phase. A focused password
field hides the character on purpose, because clicks and keys are dead while it is
on and somebody about to start a run needs that before they start it.

## 2. The UI asks the new question — `ProctorUI/AgentModel.swift`

`requiredGrantsGranted` is `report.grants.filter(\.required).allSatisfy(\.granted)`,
and `menuBarIcon` passes it, `report.secureEventInputActive` and `report.ready` to
`MenuBarIcon.block`. `model.ready` and every other consumer of it are untouched: the
status line, the walkthrough and the main window still ask "can every plane work",
which is the right question there.

## 3. Staleness — `ProctorCore/BuildStamp.swift` (new)

```swift
public struct BuildStamp: Sendable, Equatable {
    public let inode: UInt64
    public let size: UInt64
    public static func of(path: String) -> BuildStamp?              // nil when unreadable
    public static func replaced(running: [BuildStamp?], onDisk: [BuildStamp?]) -> Bool
}
```

Two paths are stamped, not one: the executable **and** `idle-0.png` in Core's
resource bundle. The review's point stands — the glyph that went missing is an
asset, and a resource-only reinstall would leave a Mach-O stamp untouched.

Inode or size, never modification time — so a bare `touch` raises nothing while a
replaced file always does, because an in-place upgrade writes a new file and the
running process keeps the unlinked one. `modified` is not stored at all; a field
nobody reads is weight.

`AgentModel` stamps both paths in `init`, re-stats on the 2-second doctor tick it
already runs, and exposes `buildReplaced`.

## 4. The relaunch is a real relaunch — `ProctorCore/RelaunchCommand.swift` (new)

`open -n` on a running single-instance menu-bar app activates it rather than
replacing it, and terminating first races the launch. So: a detached
`/bin/sh` that waits for this process to exit and then opens the bundle.

```swift
public enum RelaunchCommand {
    /// `["-c", "while kill -0 <pid> 2>/dev/null; do sleep 0.2; done; open '<path>'"]`
    public static func arguments(pid: Int32, bundlePath: String) -> [String]
}
```

Pure, so the one part of the relaunch that can be got wrong is tested. A single
quote in the bundle path is escaped rather than ending the quoted string.

`applicationWillTerminate` calls `Actions.stopAgent()` — "quit means everything
off". A relaunch is not a quit, so `Actions.relaunch()` sets a flag that
`applicationWillTerminate` reads and skips the bootout: the agent is the long-lived
party and the UI is a bystander, which is the whole premise of this bug.

`MenuBarContent` gains one line and one item above the existing status block —
"Proctor was updated" plus **Relaunch Proctor** — and `MainWindow` gains the same
sentence in its status area. Neither touches the Re-check row PRO-0028 owns.

## 5. The fallback stops claiming success — `ProctorUI/MenuBarCharacter.swift`

`checkmark.seal` becomes `questionmark.circle`, with the comment saying why: a
missing picture is an unknown, not an all-clear, and the old glyph collided with the
pre-PRO-0021 ready symbol, which is what made this report hard to read.

## Tests

New `Tests/ProctorCoreTests/MenuBarReadinessTests.swift` and
`Tests/ProctorCoreTests/BuildStampTests.swift`; additions to
`Tests/ProctorAgentTests/RunHUDMenuBarWiringTests.swift` where a real `DoctorReport`
is needed.

| Clause | Test |
|---|---|
| A1 | the measured payload — both required grants granted, `Automation` ungranted, no blockers, SEI off, idle — decides `.character(.idle)` |
| A2 | a non-required grant ungranted, alone, never blocks; each required grant ungranted does |
| A3 | SEI alone → `lock.laptopcomputer`; a missing grant alone → `exclamationmark.triangle`; both → the grant wins; SEI outranks foreground and phase |
| A3b | an unrecognised `ready == false` still blocks — the fail-closed case |
| A4 | `foregroundSitsBetweenReadinessAndThePhase`, unchanged in what it pins |
| A5 | ready + idle → character, and `.idle` is one frame with no tick, both motion settings |
| A6 | `RunHUDModel()`'s initial `menuBarPhase` is `.idle` and decides to the character |
| A7 | `replaced` on inode change, on size change, on a `touch` (false), on equal stamps (false), on an unreadable path (false); real files in a temp directory, so it is the syscall being tested |
| A8 | `RelaunchCommand.arguments` waits on the pid before opening, and quotes a path containing a quote |
| A9 | `checkmark.seal` appears nowhere in `Sources/ProctorUI` |
| A10 | PRO-0021's asset tests, unchanged |

A9 is a source-text assertion rather than a render check, and the spec says so.

## Order

Core first (1, 3, 4), then its tests, then the UI edits (2, 5). `swift build` +
`swift test` after each. The UI has no test target, so every clause lands in
`ProctorCoreTests` or `ProctorAgentTests`.
