# PRO-0120: Cross-Automation Stack Yield and Takeover Reporting Harness

**ID:** PRO-0120
**Status:** Ready for Plan
**Created:** 2026-08-24
**Last updated:** 2026-08-24
**Brief:** `docs/features-to-triage/112-cross-automation-stack-reporting-harness.md`

## Feature description

Provide a passive system event listener and audit recorder that detects external automation takeovers (XCTest, Cua, Playwright) and records yield events, unblocking BLOCK-0003 and elevating REQ-081.

## Acceptance sketch

- Passive audit listener records yield events when external automation stacks drive mouse/keyboard.
- Yield records capture holding duration and automation mode banner state.
- BLOCK-0003 is eliminated and REQ-081 transitions to observed.

## Assumptions made writing this

- Assuming passive detection uses standard Quartz Event Taps (`CGEventTapCreate`).
