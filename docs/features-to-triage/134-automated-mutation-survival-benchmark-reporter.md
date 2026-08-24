---
generated-by: reckon
reckon-sources: [SURF-026, DEF-033]
status: retired
---
# Automated Mutation Survival Benchmark Reporter

- origin: docs/.ideation/reckoning-intake-round4-trawl.md · 2026-08-24
- audience: Quality assurance leads monitoring mutation coverage trends across package modules
- platforms: mac
- proposed-by-ai: true

## What and why
Tracking mutation testing effectiveness across large Swift packages requires aggregating survival statistics across multiple test runs. Without dedicated reporting tools, developers must manually inspect verbose compiler and mutation logs to identify surviving mutants. An automated mutation benchmark reporter computes mutant kill ratios, highlights untested code branches, and generates actionable improvement summaries.

## Acceptance sketch
- Benchmark reporter aggregates mutation results across all analyzed source modules
- Mutant kill rates are computed per module with clear numerator and denominator breakdowns
- Surviving mutants are mapped directly to corresponding source code lines and functions
- Summary reports highlight critical untested branches requiring additional test coverage
- Historical mutation score trends are formatted for continuous quality tracking

## Assumptions made writing this
- Assuming mutation analysis runs as a post-build quality evaluation step
- Assuming reports generate in standardized portable formats without external dependencies
