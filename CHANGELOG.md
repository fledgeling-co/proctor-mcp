# Changelog

All notable changes to Proctor are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-08-14

First public release.

### Added

- **Computer use over MCP.** Any MCP-speaking model can drive this Mac: read the screen, find controls, click, type, scroll, and check that what it did actually landed. Nineteen tools in all, from `attach` and `snapshot` through `find`, `act`, `capture`, `zoom`, `wait` and `assert` to `flow`, `stability`, `inspect` and `doctor`.
- **A real UI-testing harness, not just a driver.** `assert`, `wait`, `stability` and `flow` turn the same tools into acceptance checks: wait for a window to settle, assert an element is there, replay a sequence, and get told when the screen is still moving.
- **Windows in the background stay in the background.** Proctor drives occluded windows, minimised windows, and windows on another Space without pulling focus or stealing your pointer, working across the accessibility and Apple Events planes rather than faking clicks at the front.
- **Screenshots that tell you how old they are.** Captures come back through ScreenCaptureKit with freshness metadata, so a model acting on a frame knows whether it is looking at now or at a moment ago.
- **Grants that survive an upgrade.** Accessibility and Screen Recording are granted once to a stable launchd-agent identity keyed to the Developer ID signature, not to a path or a build, so a reinstall or a version bump does not send you back to System Settings.
- **The tools every model already knows.** Stock Anthropic and OpenAI computer-use schema façades sit over the native tools, so a model trained on either can attach with no custom wiring.
- **Menus, dictionary, a policy gate, and a redacting audit log.** Read menu bars, look words up, gate actions behind a policy, and keep an audit trail that redacts what it should not record. Plus process kill and screen unlock for the moments automation gets stuck.
- **Signed, notarised, and installed properly.** The first public build ships as a notarised Developer ID release into `/Applications`, run as a per-user launchd agent.

[Unreleased]: https://github.com/fledgeling-co/proctor-mcp/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/fledgeling-co/proctor-mcp/releases/tag/v0.1.0
