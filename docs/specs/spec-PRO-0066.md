# PRO-0066: The status window becomes the mock

**ID:** PRO-0066 · **Status:** Merged · **Created:** 2026-08-20
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

## Verification

`StatusSurfaceTests` is 9 tests; suite 1,547 in 179 suites, green on four consecutive runs.

- **A1** — `sections(for: .down)` returns exactly `[.agentDown]`, and the test names all eight
  other sections and asserts none is reachable. The state mapping is pure and tested at five
  combinations, so the decision the surface turns on is not a view-body branch.
- **A3** — identifiers unique and namespaced; every switch in `SwitchCatalogue` has a row, so a
  ninth switch cannot be added without this surface gaining one.
- **A5** — the three lane states carry different pills, asserted not-equal, and `unconfirmed`
  is fail-closed on `isUsable` exactly as `unavailable` is.
- **A6** — skeleton height equals row height from one constant.

**A2 was partly done and was honestly recorded as such.** The window's body, the new agent-down
block and the new Lanes section read every string from `StatusSurface.Copy`. The five older
sections still carried their own literals; converting them was mechanical and did not fit this
change without risking a working window. The grep clause in A2 therefore did not pass, and was
carried as remaining work on this item rather than reported green.

### A2 is closed. PRO-0081, 2026-08-21

The carry was made because there was no instrument to prove the window still worked after the
conversion. `SurfaceFidelity` and the embedded `ProctorReflector` shipped in PRO-0067 and supplied
one, and the clause is now green with its grep run rather than described.

The clause's own grep is `scripts/campaign/status_literals.py`. A plain `grep` cannot decide the
"outside an identifier" half and a person deciding it per literal is the judgement this clause
asks to keep mechanical, so it decides by **syntactic position and never by reading the string**:
`symbol` for an SF Symbol argument, `system` for a path, argv word, URL or window id, `key` for a
case label or comparison, `punctuation` for a literal that is nothing but separators once escapes
and interpolation are stripped, and `display` for **everything else**. Default-deny, so the only
way to green is to move the string rather than to widen a list.

**176 literals, 132 of them user-facing, to 45 literals and 0.** The identifier count went 44 to
45, so the copy moved out of the view and the machinery did not move out of the file — and that
is gated rather than printed, against a committed snapshot of the identifier set
(`docs/test-campaign/evidence/PRO-0081/a2-identifier-baseline.json`), because an out-of-family
review pointed out that a count collides where a set does not.

No wording changed. Every string moved character for character into `StatusSurface.Copy`, or into
Core beside the value it describes where it was an identifier a computed property returned:
`StatusChecks.settingsPane`, `Wire.shimPath`, `Wire.launchdDomain`, `StatusChecks.ToolRow.Tone.symbol`.

Three things this item found while doing it, none of them fixed in passing: `Copy` already held
three sentences the window has never rendered while the window rendered three different ones
(DEF-035); the `.unreachable` branch of `ReadinessSection` has been unreachable since this item
added `AgentDownSection` (DEF-037); and `StatusChecksTests.theRightRecheckWasDeleted` read from
the footer to the end of the file and counted two Re-check buttons over a population of three
(DEF-038, fixed, because the conversion is what made the third visible).

Cases CASE-0102..0105. A2 is file-scoped and the five sibling views still hold 258 user-facing
literals between them; that is measured and recorded as DEF-039 rather than left implied.

### The defect this item found, which it did not cause

The suite began failing intermittently and once wedged for ten minutes. Adding a nine-test
suite changed the parallel schedule and surfaced a pre-existing fault in E2E Journey 7.

The journey asserts the *absence* path for the iOS lane — "when simctl is absent, ios commands
report actionable guidance" — with a 1,000ms bound on a real subprocess. On a machine that has
Xcode, and this one does, it therefore ran `xcrun simctl list -j devices` for real; under load
the process was killed mid-write, and the truncated JSON threw a `DecodingError` that the
journey's `catch let error as AgentError` did not catch.

The root cause is in production code rather than in the test. `IOSDeviceList.parse` threw the
decoder's error straight out to the caller, which is neither of the two answers its own doc
comment promises ("a parse failure and 'there is no device here' are different things to
report"). It now refuses with an `AgentError` naming how many bytes arrived and what to check,
and three tests cover truncated, empty and well-formed input. The journey asserts the
invariant that holds whether or not the machine has Xcode, and a non-`AgentError` is now a
named failure rather than an uncaught throw.

## Measured later, by the 0.8.0 campaign

The clause this spec carried has a measurement now rather than a carry. `be-my-witness` judged
a capture of the built surface against its design pane, both dark, both at the pane's own size,
and refuted it. The divergences are enumerated in `docs/test-campaign/witness-verdicts.json`
and recorded as defects in the campaign inventory; they are styling rather than content, and
they are left open as a gap-fix work order rather than changed in passing.

One content divergence found alongside them was fixed: the permissions list named a third
grant the design did not, and omitted the one the design draws. See PRO-0075.
