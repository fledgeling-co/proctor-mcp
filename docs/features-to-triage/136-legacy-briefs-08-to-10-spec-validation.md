---
generated-by: reckon
reckon-sources: [SURF-018, SURF-015, SURF-004, REQ-001]
status: to-triage
---
# Legacy Briefs 08 to 10 Specification Validation

- origin: docs/reckoning/2026-08-25-final/reckoning.md · 2026-08-25
- audience: Project maintainers verifying MCP surface modernization, process management, and pointer overlays
- platforms: mac
- proposed-by-ai: false

## What and why
Historical feature briefs covering MCP surface modernization, process termination with filesystem jail enforcement, and pointer target overlays in captures remain classified as undecided in closed-world reconciliations. When early backlog items lack explicit requirement tracing to live test cases, reckoning cannot formally retire them without code-level verification. Running a structured specification validation pass confirms that every historical claim traces to production implementations and enables formal retirement.

## Acceptance sketch
- Validation pass verifies production symbol implementations for MCP tool definitions, process termination, filesystem isolation, and pointer overlays
- Implemented features map directly to passing behavioral test cases
- Unimplemented claims are flagged for follow-up rather than assumed complete
- Verified historical briefs transition to retired status with permanent citations
- Closed-world reckoning reflects increased verified completion and reduced undecided counts

## Assumptions made writing this
- Assuming verification traces code symbols directly rather than accepting text descriptions as proof
- Assuming partially implemented historical items generate granular follow-up briefs
