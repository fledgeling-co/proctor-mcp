# Doctor knows the whole toolchain

**Read `00-WAVE-7-DIRECTION.md` first.** This item supersedes brief 32, which is
retired: its `doctor.sh` half survives here and its policy-block half is folded in.

## The problem

`proctor_doctor` is the first call the Proctor skill tells a model to make, and after
this wave it will be reporting on a machine whose ability to do anything depends on
software Proctor does not ship: `cua-driver`, `xcrun simctl` and Xcode, and `maestro`.
Today it reports its own grants and two browser tools.

Two gaps carried over from the retired brief: there is still no `policy` block, so the
gate that will refuse a model's next call is invisible to it, and `scripts/doctor.sh`
runs without the agent and knows about none of this.

## What it should do

Report the whole toolchain, per lane, with each tool's presence, version and usability,
and say which lanes are actually available on this machine.

## The hard parts, named

- **"Installed" is not "usable", and this wave makes the difference expensive.** A
  `cua-driver` that is present but unsupported by version, or present but whose daemon
  is not running, or whose own permissions are unhealthy, is a lane that will fail at
  the first call. Cua has its own `doctor`; using it is better than re-deriving its
  answers, and it is also a second process's opinion arriving as text.
- **Deciding what a `policy` block may say.** `doctor` is called before anything is
  established. Reporting the gate's rules there makes `doctor` a way to read the
  configuration without passing the gate. Report shape and posture rather than rules.
- **A launchd agent does not see a login shell's PATH.** That is why Obscura needed
  explicit search locations, and every tool added here inherits the problem. It is also
  why `scripts/doctor.sh`, which runs in a login shell, can honestly disagree with the
  agent about whether a tool exists. Report the disagreement rather than hiding it.
- **The shell doctor duplicates the search order in a second language.** Two
  implementations of one list drift. Generate it or state plainly that the shell copy
  is advisory.
