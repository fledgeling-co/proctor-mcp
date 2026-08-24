# Headless Simulator Provisioning and Teardown Hook

- origin: docs/features-to-triage/.ideation/reckoning-intake-trawl.md · 2026-08-24
- audience: CI runners and automated test harnesses requiring ephemeral device environments
- platforms: mac
- proposed-by-ai: true

## What and why
Running device automation in non-interactive CI environments often leaves orphaned simulator processes and cached device state across test runs. Stale simulator state can cause flaky test execution and resource exhaustion on shared build machines. An automated provisioning and teardown hook manages ephemeral simulator instances that exist solely for the duration of a test session.

## Acceptance sketch
- Provisioning hook creates an isolated ephemeral simulator instance prior to test execution
- Simulator runs in headless mode without displaying GUI windows on the host desktop
- Environment variables and test credentials are automatically injected into the instance
- Teardown hook securely wipes simulator data and terminates all helper processes on completion
- Abnormal test terminations trigger automatic cleanup on subsequent runner invocations

## Assumptions made writing this
- Assuming ephemeral instances use temporary scratch directories rather than modifying persistent device profiles
- Assuming headless execution is enforced to minimize GPU and window server overhead on CI machines
