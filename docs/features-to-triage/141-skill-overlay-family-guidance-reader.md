---
generated-by: tailings
tailings-sources: [T1]
reckon-sources: [REQ-096, REQ-091]
status: retired
triaged-as: PRO-0149
validated-by: REQ-091, REQ-096 via CASE-0370, CASE-0804
validated-rungs: metamorphic, outcome
validated-provider: none
---
# Skill Overlay Family Guidance Reader

- origin: tailings audit T1 (mac-design-digest overlay present and unread) · 2026-08-25
- audience: Agent runners executing skills that ship model-family-specific override guidance
- platforms: mac
- proposed-by-ai: false

## What and why
Some skills ship family-specific overlay guidance beside their main instructions, carrying overrides calibrated to a particular model family. When a skill is reached as a nested dependency rather than invoked directly, the overlay goes unread and its overrides never apply. An overlay reader detects the presence of family-specific guidance at skill load time and surfaces whether it was read.

## Acceptance sketch
- Skill loading detects the presence of family-specific overlay guidance files
- Overlay presence is announced when a skill is reached as a nested dependency
- Reading an overlay is recorded so audits can distinguish read from unread
- Overlays that do not apply to the running family are skipped with a recorded reason
- Nested skill invocations inherit the same overlay detection as direct invocations

## Assumptions made writing this
- Assuming overlay files follow a predictable naming convention beside the main skill instructions
- Assuming overlay reading is recorded rather than assumed from skill invocation alone
