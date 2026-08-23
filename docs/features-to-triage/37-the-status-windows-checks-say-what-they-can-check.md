---
sources: [REQ-009, REQ-032]
---
> **REVISED for wave 7, 2026-08-15.** Still wanted, and now larger. The window will also be reporting on `cua-driver`, `xcrun simctl` and `maestro`, so the rule this brief is about (a check must say what it can actually establish) applies to more rows than it did. Sequence after brief 51, which decides what the health report knows.

# The status window's checks say what they can check

## The problem

Two pre-existing defects in the status window, both logged by features that
declined to widen their scope.

- **Three `Re-check` buttons carry the limitation PRO-0028 deleted a menu row
  for.** macOS caches the Screen Recording answer through `SCShareableContent`
  per process for that process's life, so none of these buttons can clear a stale
  denial. Nothing is broken, because a working `Restart Agent` now sits beside
  them, but the buttons still promise a check that cannot reach that grant.
- **The Shortcuts CLI row renders under "Optional — asked for per app"**, which
  is text belonging to the Automation grant and wrong for a CLI. PRO-0023 did not
  add to it, reporting Obscura as a tool rather than appending to `grants`, so
  the row is now the odd one out in its own section.

## What it should do

Make each check in the window say what it can actually establish, and put the
tool rows under a heading that describes tools.

## The hard parts, named

- **PRO-0028 is the precedent and its reasoning is the constraint.** It removed a
  control rather than relabelling one, on the grounds that a label naming an
  object the control cannot read is worse than no control. The same test applies
  to each of these three buttons individually: for each one, name what it reads,
  whether that read is cached, and whether a person pressing it can change the
  answer. Some of them may be fine.
- **`Restart Agent` beside them is the working path** and the window should make
  that legible rather than leaving a person to discover which of four buttons is
  the one that works.
- **Grants and tools are different kinds of thing.** A grant is a decision macOS
  holds about Proctor; a tool is a file on the machine. They currently share a
  section and a subtitle. Separating them is the smaller half of this item and
  probably the more valuable one.

## Not in scope

Adding new checks. This is about the ones already on screen telling the truth.
