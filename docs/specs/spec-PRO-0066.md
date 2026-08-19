# PRO-0066: The status window becomes the mock

**ID:** PRO-0066 · **Status:** Ready for Plan · **Created:** 2026-08-20
**Brief:** `docs/features-to-triage/60-status-window-to-the-mock.md`
**Branch:** `ai/pro-0066` off `ai/wave-9` · **Depends on:** PRO-0064, PRO-0065
**Mock:** `#mac/status/ready`, `…/checking`, `…/partial`, `…/down`

## The problem

`MainWindow.swift` is 1,030 lines holding seven sections written across five waves, with its
own spacing, font sizes and roughly 40 inline colour and size literals. It has one state.
The mock has four, and two of them are the states a person meets when something is wrong.

The worst of them is the agent-down case: **the mock withholds the rest of the window rather
than dimming it**, where the shipped window keeps drawing permission rows it cannot read. A
stale Ready pill over a dead agent is a false statement about a security-relevant grant.

## Acceptance criteria

1. **A1** — four states resolve to their section lists from `StatusSurface` in Core; the
   `down` state's list is exactly the agent-down block, and the test fails if any other
   section is reachable while the agent is unreachable.
2. **A2** — every user-facing string comes from `StatusSurface`. A grep for a quoted string
   literal in `MainWindow.swift` outside an identifier returns nothing.
3. **A3** — identifiers are unique across the window and stable across states.
4. **A4** — switch rows render the value the *agent* reported. The test asserts the window has
   no path to `ProcessInfo` for a switch value: this window and the agent are different
   processes with different environments, and the window's own would be plausibly wrong.
5. **A5** — `unconfirmed` and `unavailable` map to different pills, asserted as not-equal.
   PRO-0041 closed a defect where a person was sent to fix a lane that was merely
   unestablished; drawing them alike reintroduces it at the surface.
6. **A6** — the skeleton row heights equal the permission row heights, read from one constant,
   so nothing jumps when the two-second poll returns.

## Decisions taken at triage

- **`ready` keeps its meaning.** Untouched by every optional lane and by the audit trail's
  writability. Settled by PRO-0050's non-goals and not reopened here.
- **The Lanes section is rendered.** `DoctorReport.lanes` has been on the wire and unrendered
  since PRO-0036 deliberately left it; this item closes that child.
- **The policy-posture block stays unrendered.** It answers a different question and belongs
  beside the audit surface. Recorded as child work rather than folded in.

## Out of scope

First run belongs to PRO-0067. The two must not both own the no-grants-yet state.
