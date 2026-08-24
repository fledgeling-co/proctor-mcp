# Legacy Brief Spec-Validation and Retirement

- origin: docs/reckoning/2026-08-24-final/reckoning.md · 2026-08-24
- audience: Project maintainers tracking historical feature completion against verified test outcomes
- platforms: mac
- proposed-by-ai: false

## What and why
Historical feature briefs with in-tree mock evidence remain classified as undecided in closed-world reconciliations. When early backlog items lack explicit requirement tracing to live test cases, reckoning cannot formally retire them without code-level verification. Running a structured specification validation pass confirms that every historical claim traces to production implementations and enables formal retirement.

## Acceptance sketch
- Validation pass checks historical brief claims against production symbol implementations
- Implemented features map directly to passing behavioral test cases
- Unimplemented claims are flagged for follow-up rather than assumed complete
- Verified historical briefs transition to retired status with permanent citations
- Closed-world reckoning reflects increased verified completion and reduced undecided counts

## Assumptions made writing this
- Assuming verification traces code symbols directly rather than accepting text descriptions as proof
- Assuming partially implemented historical items generate granular follow-up briefs
