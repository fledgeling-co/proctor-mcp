# Trawl — tailings audit findings intake, 2026-08-25

Sources: `tailings/signals.json`, `tailings/crossref.json`, and the latest `tailings/worklist.json`.

## Kept Ideas

- **idea-01: Non-zero class partition breakdown reporter** → brief 157, `proposed-by-ai: false`.
  From probe T11 (`a printed non-zero class is absent from the report that follows`). When a gate prints sub-class counts (e.g. 41 source-analysis, 16 unarmed, 3 n/a), downstream reports must enumerate all non-zero sub-classes rather than reporting only the aggregate.
- **idea-02: Unsuppressed gate execution and exit verification** → brief 158, `proposed-by-ai: false`.
  From probe T5 (`gate output suppressed and never re-run unsuppressed`). Tool invocations must capture structured exit codes and avoid hiding stderr/stdout failures under pipes or quiet flags.
- **idea-03: Repository-relative path citation resolver** → brief 159, `proposed-by-ai: false`.
  From probe R2 (`a cited path exists nowhere in repo: bare campaign.json`). Path citations in notes and markdown must be anchored to the repository root so external tools can resolve them unambiguously.
- **idea-04: Release stub and no-op verification attestation** → brief 160, `proposed-by-ai: false`.
  From probe R9 (`function body is empty in NullContentionMonitor and ProctorReflector`). Empty stubs for non-debug/null implementations must carry explicit semantic annotations and behavioral tests proving they are intentional no-ops.
- **idea-05: Polling loop suppression and notification monitor** → brief 161, `proposed-by-ai: false`.
  From probe T13 (`polling is 1% of Bash calls`). Replace repeated terminal poll loops with event-driven until-loops or harness notifications that avoid wasting turn budget on identical outputs.
- **idea-06: Autonomous audit worklist continuous verifier** → brief 162, `proposed-by-ai: true`.
  A continuous background check that audits session transcript claims against current repo facts to flag claim drift before session close.

## Dropped Ideas

- **Automated git commit formatting linter**: Formatting styles in conversational responses and commit messages are non-signals per tailings rules.
- **Dynamic shell timeout adjuster**: Standard command timeouts are managed by the harness; a parallel timer in shell would conflict.
