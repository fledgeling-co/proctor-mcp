---
generated-by: tailings
tailings-sources: [R2]
reckon-sources: [REQ-134, REQ-151]
status: retired
validated-by: REQ-134, REQ-151 via CASE-0550, CASE-0560, CASE-0563, CASE-0564, CASE-0545, CASE-0601
validated-rungs: metamorphic, outcome
validated-provider: none
---
# Repository-Relative Path Citation Resolver

- origin: tailings audit probe R2 · 2026-08-25
- audience: Documentation authors and citation linters checking file path references across the repository
- platforms: n/a
- proposed-by-ai: false

## What and why
Specifications, test cases, and evidence notes frequently cite file paths. When citations use bare filenames or ambiguous relative paths instead of repository-relative paths, external audit tools and linters cannot resolve the files and flag them as missing. A repository-relative path citation resolver normalizes path citations across documentation and registries, ensuring every referenced path resolves unambiguously from the repository root.

## Acceptance sketch
- Citation linter identifies and validates all path references in markdown and JSON registries
- Unqualified relative paths are identified and reported with suggested repository-relative fixes
- Verified paths resolve to active files on disk or to recorded historical entries
- Automated pre-commit checks prevent the introduction of unresolvable path citations
- Cross-reference tools successfully resolve all validated path citations without heuristics

## Assumptions made writing this
- Assuming all canonical path citations are anchored to the git repository root
- Assuming historical citations to retired files are tracked in a dedicated index
