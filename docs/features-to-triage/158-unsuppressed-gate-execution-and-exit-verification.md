---
generated-by: tailings
tailings-sources: [T5]
reckon-sources: [REQ-046, REQ-130]
status: triaged
---
# Unsuppressed Gate Execution and Exit Verification

- origin: tailings audit probe T5 · 2026-08-25
- audience: Test automation operators and CI scripts that require reliable failure detection
- platforms: n/a
- proposed-by-ai: false

## What and why
Command pipelines that redirect stdout and stderr to `/dev/null` or pipe through filters can mask non-zero exit codes. When a gate command fails silently inside a suppressed pipe, the failure is hidden from the calling process and downstream steps continue under the false assumption that the gate passed. An unsuppressed gate execution and exit verification mechanism guarantees that gate exit codes are captured directly from the primary process rather than from downstream pipe stages.

## Acceptance sketch
- Gate runner scripts capture and check the exit code of the primary command directly
- Output suppression flags preserve exit code propagation on non-zero outcomes
- Pipelines avoid piping gate commands directly to tail or grep without reading PIPESTATUS
- Failing gate runs produce explicit diagnostic output on stderr even when quiet mode is enabled
- Automated checks verify that suppressed commands cannot mask real gate failures

## Assumptions made writing this
- Assuming shell invocations adhere to strict exit code tracking conventions
- Assuming gate runners support structured logging alongside quiet terminal output
