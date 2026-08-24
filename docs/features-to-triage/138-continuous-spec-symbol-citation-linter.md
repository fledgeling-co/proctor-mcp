---
generated-by: reckon
reckon-sources: [SURF-025, REQ-102]
status: to-triage
---
# Continuous Spec-Symbol Citation Linter

- origin: docs/.ideation/reckoning-intake-round5-trawl.md · 2026-08-25
- audience: Quality engineers maintaining specification citations and symbol mapping consistency
- platforms: mac
- proposed-by-ai: true

## What and why
Maintaining consistency between feature specifications and evolving codebases requires continuous validation of referenced symbol names and file paths. When code refactorings rename symbols without updating corresponding specification citations, traceability degrades. An automated continuous citation linter parses all active specification documents, validates symbol references against the live source tree, and generates line-anchored diagnostic reports.

## Acceptance sketch
- Citation linter scans all specification documents for referenced types, functions, and protocols
- Referenced symbols are resolved against the current production source tree
- Renamed, moved, or deleted symbols produce actionable warnings with suggested corrections
- Linter reports summarize overall citation resolution rates and identify ungrounded references
- Integration with pre-commit gates prevents the introduction of broken specification citations

## Assumptions made writing this
- Assuming symbol extraction handles standard language identifier formats accurately
- Assuming linting runs locally as a fast static analysis step during continuous integration
