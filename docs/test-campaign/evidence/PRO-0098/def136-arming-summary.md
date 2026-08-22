# DEF-136 — the conversion, proved rather than assumed

One converted site broken at what it unwraps, run twice: once with the force-unwrap put back, once
converted. Same sabotage, same tree, same command. Full output in `def136-arming.txt`.

**The sabotage is a real regression, not a stub.** `Toolchain.entry(for:)` at
`Sources/ProctorCore/Toolchain.swift:189` is made to miss on the literal id `"obscura"` — an entry
dropped from the production catalogue, which is precisely what these `ToolchainTests` cases exist
to catch.

**The site** is `Tests/ProctorCoreTests/ToolchainTests.swift:19`, the `entry(_:)` helper that eleven
cases in that suite go through.

## Run A — `Toolchain.entry(for: tool)!`

```
ProctorCoreTests/ToolchainTests.swift:19: Fatal error: Unexpectedly found nil while unwrapping an Optional value
error: Process '…/proctor-mcpPackageTests --testing-library swift-testing' exited with unexpected signal code 5
FAIL: no swift-testing verdict line in the output.
EXIT=1
```

**`Test run with …` appears zero times in the whole run.** No test count, no suite count, no
verdict. The runner is gone before swift-testing can say anything, and `scripts/test.sh` can only
report that nothing said anything. From outside, this is indistinguishable from a build that never
started — and the four honest failures below were all already there, unreported.

## Run B — `try #require(Toolchain.entry(for: tool), …)`

```
􀢄  Test run with 1992 tests in 244 suites failed after 36.027 seconds with 4 issues.
FAIL: swift test exited 1
EXIT=1
```

A verdict line, a denominator, and four named failures — each saying which lookup returned nil and
what it was asked for:

```
Test "a tool that is not there is unusable, and the evidence says absent"
  recorded an issue at ToolchainTests.swift:19:13:
  Expectation failed: Toolchain.entry(for: tool → "obscura") → nil
Test "presence settles the tools Proctor only ever calls as a one-shot"      — same
Test "a half install is unusable and names the missing companion"            — same
Test "checkedAt travels with the verdict"                                    — same
```

## What the two runs differ in

Both exit 1. That is not the difference and never was. The difference is that run A reports **0
tests in 0 suites**, and run B reports **1,992 in 244 with the four that broke named**. A suite that
cannot tell "the run died" from "the run found something" is one where every other measurement on
the machine is unreadable, which is why this defect was taken before the other three.

**Restored afterwards**, and checked: `git status` reports 0 modified files at the end of the script.
