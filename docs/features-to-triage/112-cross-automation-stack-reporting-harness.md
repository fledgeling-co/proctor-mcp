---
sources: [REQ-081, BLOCK-0003]
status: retired
validated-by: REQ-081 via CASE-0294, CASE-0295, CASE-0296, CASE-0297
validated-rungs: metamorphic, outcome
validated-provider: ContentionSample.userInputSince and ContentionWatch.conditions in Sources/ProctorCore/Contention.swift; ContentionMonitor.sample; the probe after the last step in Sources/ProctorAgent/Session/SessionAct.swift
---
# Cross-Automation Stack Yield and Takeover Reporting Harness

- origin: intake sweep over BLOCK-0003 and REQ-081 (yield reporting across external automation stacks) · 2026-08-24
- audience: operators supervising hybrid automation suites (XCTest, Cua, Playwright)
- platforms: mac
- proposed-by-ai: true

## What and why
BLOCK-0003 records that runs driven by external automation stacks (e.g. XCTest testmanagerd or third-party CUA agents) bypass Proctor's local session dispatcher, leaving yield and takeover disclosures uninstrumented for external runs. Providing a passive system event listener and audit recorder that detects external automation takeovers will unblock BLOCK-0003 and elevate REQ-081 to observed.

## Acceptance sketch
- A passive audit listener records yield events when external automation stacks drive the mouse/keyboard.
- Yield records capture the holding duration and external automation mode banner state.
- BLOCK-0003 is eliminated and REQ-081 transitions to observed.

## Assumptions made writing this
- Assuming passive detection uses standard Quartz Event Taps (`CGEventTapCreate`) without stealing focus.
