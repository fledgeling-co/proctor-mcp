> **RETIRED 2026-08-15 (PRO-0031), not built.** Superseded by brief 51, which covers the whole toolchain rather than two browser tools. Both halves survive there: the missing `policy` block and `scripts/doctor.sh` knowing what the agent knows.
>
> Kept for the reasoning, not as a plan. See `00-WAVE-7-DIRECTION.md`.

# The health report is complete

## The problem

Two gaps in the same surface, logged by two different features.

**`proctor_doctor` has no `policy` block.** PRO-0005's plan called for one and it
is not in the tree, so the audit and policy state of a live agent is visible only
through `proctor_policy status`. A model checking whether Proctor is ready to work
gets the grants, the observers, Secure Event Input, the shortcuts CLI and both
browser tools, and nothing at all about the gate that will refuse its next call.

**`scripts/doctor.sh` knows about neither browser tool.** It runs without the
agent, which is its whole point, and PRO-0023 and PRO-0024 both logged that it is
now behind what the agent reports. A person running the shell doctor to work out
why a handoff failed learns nothing about the tool the handoff names.

## What it should do

Report policy state in `proctor_doctor` alongside the grants, and teach
`scripts/doctor.sh` about Obscura and browser-use.

## The hard parts, named

- **Deciding what a `policy` block may say.** `proctor_policy status` exists and
  is presumably gated. `doctor` is the one call a model makes before it has
  established anything. If the policy block reports the rules, `doctor` becomes a
  way to read the gate's configuration without passing the gate. Say what is safe
  to expose at that point: probably shape and posture (is a gate armed, is the
  audit trail sealed, how many rules) rather than the rules themselves.
- **The shell probe duplicates the agent's search order in a second language.**
  PRO-0023 already said this is why it is a separate item. Two implementations of
  one search order drift. Either share the list through a generated file, or state
  plainly that the shell copy is advisory and say so in its output.
- **A launchd agent does not see a login shell's PATH**, which is why the agent
  checks explicit locations. `doctor.sh` runs in a login shell and does see it, so
  the two can honestly disagree about whether a tool is present. That disagreement
  is itself worth reporting rather than hiding.

## Worth knowing

`shortcutsCLIAvailable` is the existing shape for a tool in the health report,
and PRO-0023 added `obscura` as a tool object with `searched` paths. Match those.
