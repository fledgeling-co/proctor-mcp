# PRO-0027: The menu bar shows the character when idle

**ID:** PRO-0027
**Status:** In Review
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Plan:** `docs/plans/plan-PRO-0027.md`
**Brief:** `docs/features-to-triage/28-menu-bar-character-when-idle.md`

## Feature description

PRO-0021 put the character in the menu bar and made readiness outrank it. That rule
is right and it is reportedly reaching further than intended: at rest, on a healthy
machine, the reader sees a status symbol where the idle character should be.

The brief names three possible causes and says the answer changes the work entirely,
so the first job was to find out which. It is none of them.

## The diagnosis — measured, 2026-08-15

**`proctor_doctor` on this Mac, at rest:**

```
ready: true          blockers: []          secureEventInputActive: false
Accessibility     granted: true   required: true
Screen Recording  granted: true   required: true
Automation        granted: false  required: false
hud: { available: true, canShow: true, enabled: true, onScreen: false }
```

So the ladder, given that report, returns
`.character(.idle)`. The brief's specific worry — that a non-required grant folds
into `ready` and leaves a healthy Mac reading as not-ready forever — is **not true of
`Automation`**: `SessionDoctor` builds `blockers` from `grant.required && !granted`,
and `Automation` is `required: false`. **Cause 1 is ruled out.**

**The menu bar itself, captured with `screencapture` and read.** Before anything was
touched, Proctor's item was `checkmark.seal`. That string appears in exactly one
place in the tree today — the `character.image == nil` fallback in `MenuBarLabel` —
which points at cause 2. It is also the *pre-PRO-0021* "ready" glyph, and that is
what it turned out to be:

| | |
|---|---|
| Running `Proctor` process started | 14 Aug **14:41** |
| PRO-0021 merged (`58b3ce4`) | 14 Aug **22:30** |
| `/Applications/Proctor.app` rebuilt | 15 Aug **07:50** |

The menu bar the reader was looking at had been running for eight hours before the
character existed. Killing it and relaunching the same installed bundle put the
compact-Mac sprite in the bar, in colour, in its idle state, first try. Verified by
capture at both ends.

The art also ships correctly: all 42 pictures (14 assets x 3 densities) are present
in `proctor-mcp_ProctorCore.bundle` inside the installed app, named exactly as
`RunHUDCharacter.assets` names them. **Cause 2 is ruled out.** And cause 3 could not
produce the symptom in any case — `AgentModel.hudPhase` starts at `.idle`, so a phase
that never arrives leaves the ladder on `.character(.idle)`, never on a symbol.
**Cause 3 is ruled out.**

**The report is therefore accurate about what was seen and wrong about what it
means.** The rule is not reaching too far. A stale process was.

## What this feature is, given that

Nothing about the ladder is reordered and no state is redecided. Four things follow
from the diagnosis, and they are the whole of the work.

### 1. The stale build is the actual defect, and it is invisible

An upgrade replaces `/Applications/Proctor.app` underneath a running menu bar app.
`scripts/install.sh` kickstarts the **agent**, so it comes back on the new binary
(measured: the install landed at 07:50:25 and the agent restarted at 07:50:36); the
**UI** keeps running the old one indefinitely, with no signal anywhere that the two
halves of one bundle are now different builds. That is what produced this bug report, it will produce the next
one, and today the only way to find out is to do what this triage did.

So: the UI records the identity of three files at launch — its own executable, the
agent's, and one of the character's pictures — and compares them against what is on
disk on the doctor tick it already runs. When they differ it says so, with a Relaunch
item. The comparison is a pure function in Core over stamps, so it is testable without
a window server; only the drawing is not.

This is deliberately not a version-string comparison. `AgentBuild.version` is a
hardcoded `0.1.0` and would not have differed across the eight hours above; the file
identity would have.

### 2. The readiness rung says "a grant is missing" about something that is not a grant

`SessionDoctor` puts **Secure Event Input** into `blockers`, and `ready` is
`blockers.isEmpty`. So the menu bar's second rung — documented in
`MenuBarIcon.decide` as "whether every required grant is in place" — raises
`exclamationmark.triangle`, the missing-permission glyph, on a Mac where every
permission is present.

Secure Event Input is on whenever a password field has focus, whenever Terminal has
Secure Keyboard Entry set, whenever a password manager is unlocking. It blocks the
synthetic plane only: the doctor's own blocker text says "The accessibility plane is
unaffected: press, setValue, focus, menu and type all still work", and PRO-0018
already models it as a **run-time yield** (`ContentionReason.secureInput`, "Paused —
secure keyboard entry is on") rather than as a permission failure.

The first draft of this spec proposed dropping it from the rung entirely so the
character stayed. The out-of-family review rejected that and was right: a Mac under
Secure Event Input is not at healthy rest — clicks and keys are dead, and somebody
about to start a run needs to know before they start it. Hiding it would be the same
falsehood pointed the other way.

So the rung keeps Secure Event Input and stops mis-naming it. It resolves to **its
own symbol** — `lock.laptopcomputer`, which appears nowhere else in this app — rather
than to the missing-permission triangle. Both outcomes are symbols, both outrank the
character, and the ladder's order is untouched: unreachable > readiness > foreground
> phase, exactly as `foregroundSitsBetweenReadinessAndThePhase` pins. Secure Event
Input therefore outranks the foreground notice and the phase, and a focused password
field hides the character deliberately.

The rung also fails closed. It is computed from the required grants and from Secure
Event Input, and anything *else* that makes `DoctorReport.ready` false — a blocker
added later, in a change nobody remembers to trace here — reads as the permission
symbol rather than as nothing. A rung whose job is to keep a calm face off a Proctor
that cannot work has to fail in that direction.

`DoctorReport.ready` and its blockers are unchanged; they are on the public MCP
surface and a model needs "can every plane work" from them.

### 3. A missing picture reports success

`MenuBarLabel`'s fallback, when the sprite set will not decode, is `checkmark.seal` —
a glyph that says everything is fine. That is a failure wearing a reassuring face,
and it is *also* the pre-PRO-0021 ready glyph, which is precisely what made this
report hard to read: the same picture meant three different things. The fallback
becomes `questionmark.circle`, which appears nowhere else and cannot be mistaken for
either a healthy state or a permission problem.

### 4. Nothing pins the rung the report was about

The three named causes are each ruled out by a fact no test asserts. `decide` is
tested against booleans; nothing tests what produces those booleans, which is where
all three causes lived. That gap is why "which of three is it" took a measurement
rather than a test run.

## Acceptance clauses

1. **A1 — a healthy Mac shows the character, decided from the doctor's own report.**
   The exact payload measured above (both required grants granted, `Automation` not
   granted, no blockers, Secure Event Input off, phase idle) resolves to
   `.character(.idle)`.
2. **A2 — a non-required grant never sinks readiness.** `Automation` ungranted, alone,
   leaves the menu bar on the character; only a **required** grant that is ungranted
   takes it to `exclamationmark.triangle`.
3. **A3 — Secure Event Input has its own symbol, not the permission one.** With every
   required grant granted and Secure Event Input active the menu bar shows
   `lock.laptopcomputer`; with a required grant missing it shows
   `exclamationmark.triangle`, and a missing grant outranks Secure Event Input when
   both are true. Secure Event Input sits at the readiness rung, so it outranks the
   foreground notice and the phase. `proctor_doctor` still reports
   `secureEventInputActive` and still carries its blocker, and `ready` still means
   what it meant.
4. **A4 — the rung fails closed, and the ladder's order is unchanged.** A `ready`
   that is false for a reason the rung does not recognise still blocks, as the
   permission symbol. Unreachable > readiness > foreground > phase, with
   `foregroundSitsBetweenReadinessAndThePhase` still pinning what it pinned.
5. **A5 — idle at rest is the character, and it is one frame.** Ready and idle gives
   `.character(.idle)`, and `.idle` in the menu bar is a single frame asking for no
   timer, with or without Reduce Motion.
6. **A6 — a phase that never arrives rests at idle.** The initial phase is `.idle`, so
   an agent that publishes nothing leaves the character resting rather than falling to
   a symbol.
7. **A7 — a replaced bundle is detected, art included.** Two paths are stamped: the
   executable and the idle picture in Core's resource bundle, because the glyph that
   went missing is an asset and a resource-only reinstall would leave a binary stamp
   untouched. A stamp pair reads as "a different build is on disk" when the inode or
   the size differs, and as current when they match. A modification time that moved
   on its own is **not** enough — a `touch` must not raise the banner. An unreadable
   path reads as current, because nagging about a path nobody can stat is worse than
   silence.
8. **A8 — the stale signal is a statement with a working action.** It appears only
   after a difference is observed, never on a first run, says the relaunch is the
   fix, and carries a Relaunch item that waits for this process to exit before
   opening the bundle — `open` on a running single-instance menu bar app activates it
   rather than replacing it. The relaunch does not stop the agent, though a quit
   still does.
9. **A9 — a missing picture never claims success.** The sprite-load fallback is
   `questionmark.circle`, and `checkmark.seal` is gone from the menu bar entirely.
10. **A10 — the sprite still ships at every density**, unchanged from PRO-0021's A10.

## Assumptions recorded in place of questions

- `[Experience]` Secure Event Input keeps the menu bar off the character and gets its
  own glyph rather than the permission triangle. *(It is not a missing grant, but it
  is not healthy rest either: clicks and keys are dead while it is on, and somebody
  about to start a run needs that before they start. The out-of-family review
  rejected the first draft's "leave the character up" and it was right.)*
- `[Experience]` `DoctorReport.ready` keeps its present meaning and its present
  blockers. *(It is on the public MCP surface and a model needs "can every plane
  work". The menu bar asks a narrower question with a different audience, and the fix
  is to ask it precisely rather than to redefine a shared field.)*
- `[Operations]` Staleness is detected by file identity — inode and size, on the
  executable *and* on the idle picture — and not by a modification time alone, and
  not by a version string. *(Measured: the version is a hardcoded `0.1.0` and would
  not have differed across the eight-hour window that produced this report. An
  in-place upgrade writes a new file, so the inode moves even when a copy preserves
  the modification time; requiring inode or size means a bare `touch` raises nothing;
  and stamping the art as well as the binary covers a resource-only reinstall, which
  is the shape of failure the brief's second cause described.)*
- `[Operations]` The check rides the existing 2-second doctor tick. *(No new timer,
  and one `stat` is cheap against a socket round trip already running at that
  cadence.)*
- `[Experience]` The stale signal appears in the menu and the main window and does not
  modify the Re-check row PRO-0028 owns. *(Two items edit this menu in one wave;
  keeping to different regions is what makes them merge.)*
- `[Data & scope]` No new tool, no new internal verb, no change to the frame table,
  the art, the sizes, the motion policy or the ladder's order. *(All settled.)*

## What a test cannot reach here

`swift test` has no window server, and there is no test target for `ProctorUI`. Not
machine-witnessable in this repo: the menu bar item drawing at all, the character
appearing in a real bar, the stale banner rendering, and the Relaunch item receiving
a click. Those are code-complete and reasoned about.

The diagnosis above is the exception and it is not a code reading: the menu bar was
captured with `screencapture` and read at both ends of a relaunch, and
`proctor_doctor` was called on the live agent. That is real evidence about a running
Mac, obtained outside `swift test`, and it is what rules the three causes out.

## Progress — 2026-08-15

**Status: In Review.** Branch `ai/PRO-0027`, worktree `.claude/worktrees/pro-0027`,
commit `f794e42`. `swift build` clean; the only warnings are the three that pre-exist
in `ProctorUI` (`ProctorUIApp.swift:69` twice, `Walkthrough.swift:303`). `swift test`:
**568 tests in 71 suites pass**, up from 544 in 66. The 24 new tests were run under a
filter that reported `24 tests in 5 suites`, so the count was read back rather than
assumed.

Files: `Sources/ProctorCore/RunHUDMenuBar.swift` (`MenuBarBlock`, `MenuBarIcon.block`,
`decide` re-signed), `Sources/ProctorCore/BuildStamp.swift` (new),
`Sources/ProctorCore/RelaunchCommand.swift` (new), `Sources/ProctorUI/AgentModel.swift`,
`MainWindow.swift`, `MenuBarCharacter.swift`, `ProctorUIApp.swift`,
`Tests/ProctorCoreTests/MenuBarReadinessTests.swift` (new), plus the migrated call
sites in `RunHUDMenuBarTests.swift` and `YieldWiringTests.swift`, and CHANGELOG.

### The out-of-family gates, and what they changed

All three ran on grok (`grok-4.6`, effort `xhigh`, read-only). Codex is off for this
repo. None of the three rubber-stamped.

- **Spec review** rejected the first draft's answer to Secure Event Input. That draft
  dropped it from the rung so the character stayed up; the review's objection was that
  a Mac under Secure Event Input is not at healthy rest, since clicks and keys are
  dead, and somebody about to start a run needs to know. It gets its own symbol
  instead. The review also flagged that the sprite fallback was `checkmark.seal`,
  which is how a failure came to wear a reassuring face.
- **Plan review** rejected keeping `decide(reachable:ready:…)` as a forwarding shim:
  it would have kept twenty existing assertions green by asserting the mapping this
  spec calls wrong. Deleted, call sites migrated. It also caught that the stamp on the
  Mach-O alone misses a resource-only reinstall (the picture is an *asset*), and that
  `open` on a running single-instance menu bar app activates it rather than replacing
  it, so the relaunch needed a real wait-then-open rather than a line in a table.
- **Completeness critic** caught that `isRelaunching` skipping `stopAgent` leaves a
  replaced *agent* binary running the old build. The agent's binary is now stamped
  separately and the relaunch kickstarts it only when its own stamp moved, so the
  usual case (the installer already restarted it) does not drop a run in flight to fix
  a problem that is not there. It also caught that `allSatisfy` over an empty required
  -grant list is `true`, so a report naming no grants would have put a calm character
  over something that said nothing about permissions; guarded and tested.

### Accepted rather than fixed

- A same-inode, same-size in-place overwrite is invisible to `BuildStamp`. macOS
  installs replace files, so the inode moves; adding modification time back would
  reintroduce the `touch` false positive that the rule exists to avoid.
- An unstattable path reads as current in both directions. A banner nobody can clear,
  raised by a path nobody can read, is worse than silence.
- A `ready` that is false for an unrecognised reason shows the permission symbol,
  which could send somebody to System Settings over something else. That is the
  fail-closed direction and the menu's own status line still carries the words.

### Code-complete but not machine-witnessable here

`swift test` has no window server and there is no test target for `ProctorUI`. Not
witnessed: the Secure Event Input symbol drawing, the stale-build line and Relaunch
item drawing or receiving a click, the relaunch actually completing, the agent
surviving it, and the `questionmark.circle` fallback rendering. Those are reasoned
about and their pure parts are tested — the rung, the stamp comparison, the shell
command and its quoting.

**What was witnessed, outside `swift test`:** the diagnosis. `proctor_doctor` was
called on the live agent, the menu bar was captured with `screencapture` and read
before and after a relaunch of the installed bundle, and the process and file
timestamps were read from `ps` and `stat`. That is real evidence about a running Mac
and it is what rules the brief's three causes out.
