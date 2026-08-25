---
sources: [REQ-020]
status: retired
validated-by: REQ-020 via CASE-0022, CASE-0060
validated-rungs: effect-witness, outcome
validated-provider: Process() in Sources/ProctorAgent/Session/SessionIOSProcess.swift — simctl and maestro
---
# Run Maestro flows as Proctor flows

**Read `00-WAVE-7-DIRECTION.md` first.**

## The problem

Deep links get an iOS app into a state. Exercising it from there needs a driver, and
the lane `acceptance-e2e` documents is Maestro: `.maestro` YAML flows run against the
iOS Simulator.

Proctor already has a flow concept with a recording, a replay and a determinism score.
A Maestro flow is a flow too, and a caller should not have to hold two mental models.

## What it should do

Run a `.maestro` flow against a targeted simulator, parse what it reports, and surface
it in Proctor's own flow shape so the same campaign can cover a Mac app and an iOS app.

## The hard parts, named

- **The unit of execution is different and the reporting must not pretend otherwise.**
  Proctor drives a step list call by call, settles between steps, and can say which
  step diverged. Maestro executes a file and reports at the end. A Proctor flow backed
  by Maestro therefore proves something coarser, and the spec should say what
  `firstDivergence` even means when Proctor did not run the steps.
- **Determinism scoring is the interesting question here, not the invocation.**
  Repeating a Maestro flow five times and scoring the variance is genuinely useful and
  is the thing nothing on this platform packages. But if the only observable is
  pass/fail, the score has two values. Decide what per-run signal is rich enough to
  score, and say honestly if it is thinner than the macOS lane's.
- **Maestro's own flakiness is now inside your measurement.** A flake in the driver is
  indistinguishable from a flake in the app unless something separates them. This is
  the same tri-observer problem in a different coat.
- **Do not proxy Maestro's individual commands through `proctor_act`.** That was
  settled for browser tools in PRO-0020 for a reason that holds here: a tool driving
  its own engine is not driving the window Proctor is attached to, so a routed step
  would report success against something Proctor never touched.

## Worth knowing

Maestro is a separate binary with its own install. Detect it, report it in
`proctor_doctor`, and follow PRO-0023's rule: Proctor detects and explains, it never
installs, and a tool result carries no command text.
