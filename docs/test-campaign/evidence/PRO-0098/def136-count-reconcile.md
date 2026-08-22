# DEF-136's issue count, reconciled to what a run actually produces

A verifier reproducing the DEF-136 arming measured **6 issues** where the item recorded **4**. The
sabotage was re-applied and the whole suite run twice more, on 2026-08-22. Full output in
`def136-arming-rerun.txt` (the clean run) and `def136-rerun-crash.txt` (the other one).

## The number is 4, and it is structural rather than incidental

```
􀢄  Test run with 1992 tests in 244 suites failed after 17.778 seconds with 4 issues.
FAIL: swift test exited 1
EXIT=1
```

Same denominator as the recorded arming — 1,992 tests in 244 suites — and the same four issues,
each naming the lookup that returned nil:

```
Test "a tool that is not there is unusable, and the evidence says absent"    ToolchainTests.swift:19:13
Test "checkedAt travels with the verdict"                                    ToolchainTests.swift:19:13
Test "a half install is unusable and names the missing companion"            ToolchainTests.swift:19:13
Test "presence settles the tools Proctor only ever calls as a one-shot"      ToolchainTests.swift:19:13
Expectation failed: Toolchain.entry(for: tool -> "obscura") -> nil
```

Four because the sabotage names one literal id and exactly four call sites pass it:

```
$ grep -n 'entry("obscura")' Tests/ProctorCoreTests/ToolchainTests.swift
31:        let row = try Toolchain.row(entry: entry("obscura"),
56:        let row = try Toolchain.row(entry: entry("obscura"),
67:        let row = try Toolchain.row(entry: entry("obscura"),
158:       let row = try Toolchain.row(entry: entry("obscura"),
```

`#require` throws, so a test stops at its first hit and contributes one issue: 4 sites, 4 tests, 4
issues. No product code force-unwraps `Toolchain.entry(for:)` — the only other caller,
`GuestInventoryTests.swift:236`, already goes through `#require` and asks for a different tool — so
there is no path by which this sabotage reaches six. The count is recorded as 4 and stays 4.

## What the other run did, because it is not nothing

The first of the two re-runs never reported at all:

```
error: Process '...proctor-mcpPackageTests --testing-library swift-testing' exited with unexpected signal code 5
FAIL: no swift-testing verdict line in the output.
EXIT=1
```

SIGTRAP, roughly 1,850 tests in, with 195 tests started and unfinished. It did not reproduce on the
next run of the identical tree and identical command, and nothing in the sabotage explains it. It is
recorded rather than discarded because it is DEF-136's own failure mode arriving from somewhere
else: a run that dies before the verdict line, which `scripts/test.sh` correctly refuses to call a
pass. DEF-140 already holds the two force-unwrap shapes `grep -rn ')!' Tests` cannot match, and a
`try!` taking the runner down is one of them; whether that is what fired here is unproven, so it is
named as a candidate and not as a cause.

## What cannot be reconstructed

Why the verifier's run reported 6 is not knowable from here — its output is not in the tree. Two
possibilities fit: a run that carried two failures from somewhere other than the sabotage (this
suite drives a live agent and a guest VM, and the crash above shows the full run is not perfectly
reliable under contention), or a count taken from a different sabotage. What is settled is what a
run of *this* sabotage on *this* tree produces, twice measured: 4.
