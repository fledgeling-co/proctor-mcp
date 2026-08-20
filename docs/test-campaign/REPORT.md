# Campaign report — wave 9, run at test-campaign 0.8.0

**Scope: FULL.** Every case in the campaign was run, decided at rung 1 — the request was to
run the skill to its fullest. Recorded with `campaign.py scope --full`.

**The verdict line, with its denominators.** 42 cases over 17 surfaces: 41 pass, 41 armed,
0 fail, 1 inconclusive. Oracles: outcome 31 · metamorphic 3 · raster-visual 8. Strict check
41 of 42 checked, ratchet raised 36 → 41. Capture lineage: 5 published shots, 5 distinct
images, every one tying to its subject, 3 of 5 judged, ratchet pinned at 3. Suite: 1,657
tests in 197 suites.

**`campaign.py check` exits 1, and that is the honest state.** One case is inconclusive and
the gate refuses to clear over it. It is declared below with its resume point rather than
resolved to `n/a`, because it could have been reached and only an environment decision that
belongs to somebody else stands in the way.

## The stop, and how to resume it

**CASE-0042 — the status window drawing its fourth permission row.** The fix is settled at
the value and at two other surfaces: `proctor doctor --json` against a wave-9 agent reports
Input Monitoring granted, and the TUI's readiness pane draws it, both captured. The window
itself was not photographed drawing it, because that needs a UI process bound to the wave-9
agent's socket, and a GUI process launched from this harness with `PROCTOR_SOCKET` set exits
immediately: `open -n` does not pass the environment, and backgrounded from a shell AppKit
terminates it.

**Resume point.** Install the wave-9 build (`scripts/install.sh`), or launch the UI with
`PROCTOR_SOCKET=/tmp/proctor-wave9.sock` from a login session, then re-run the capture plan
against `proctor.status.section.switches`. Installing replaces the operator's own
`/Applications/Proctor.app`, which is why this run did not do it.

## What the new gate found on the first run

`capture-lineage.py` is new in 0.8.0 and it failed immediately: five published captures with
no manifest at all, so the only thing binding each picture to its surface was its filename.
That is the exact failure the plane exists to find, sitting in a campaign that had been
passing every other gate.

All five were re-taken with the manifest written at capture time, recording what the channel
was actually pointed at. Two facts made that non-trivial and both are in the manifest: three
Proctor processes were running from one bundle id with identically titled windows at identical
bounds, so every entry names the CG window the agent resolved rather than a title; and the
menu bar extra is not a window Proctor owns, so it was taken through `screencapture -R`
cropped to the `AXExtrasMenuBar` frame the process itself reported.

The seeded swap was run in both directions and caught both times, so the tie pass reads what
it claims to.

## Eight defects, six fixed

| id | what | state |
|---|---|---|
| DEF-006 | Three commands declared for the menu bar were never rendered in it | fixed |
| DEF-007 | The permissions list omitted the one permission whose absence is silent | fixed |
| DEF-008 | Three of the TUI's five panes had no data source | fixed (two of three) |
| DEF-009 | A halted caller was told which surface stopped it, and it was the wrong one | fixed |
| DEF-010 | The permissions pane clipped its fourth row off the bottom | fixed |
| DEF-011 | The fix reached the CLI and the TUI and was filtered out of the window | fixed |
| DEF-012 | The status window's chrome diverges from its design of record | open |
| DEF-013 | The walkthrough's first slide diverges from its design of record | open |

DEF-011 is the one worth reading twice. `StatusChecks` classifies every grant name the health
report can carry and an unrecognised name falls to `.tool`, deliberately, because tool names
are the half that grows. Input Monitoring was unrecognised, so the window's filter removed it
while the CLI and the TUI, which do not filter, both drew it. The drift test that exists for
exactly this scans `SessionDoctor.swift` for `.init(name: "` and asserts set equality against
the map — and the new grant was written as `.init(` then a newline then `name:`, so the scan
never saw it, both sets lacked it equally, and the assertion passed. Its only guard was
against finding nothing, and it found plenty. The scan is now a whitespace-tolerant expression
with a count floor.

DEF-012 and DEF-013 are left open on purpose. Both were already recorded as carried clauses
when their features merged — PRO-0066's A2 as partial, PRO-0067's A3 as needing a live app.
The campaign's job was to measure what those carries left open, and it has; rebuilding five
view sections is a gap-fix work order rather than a styling change to make in passing.

## Carried clauses now settled

Four acceptance clauses that merged carried, because they needed a live agent, were measured
against one. A wave-9 agent was run on its own socket so the operator's installed agent was
never replaced.

- **PRO-0073 A2** — `proctor --json` and the MCP `tools/call` result for `proctor_doctor`
  agree across 23 top-level keys and 51,195 characters. The fields that differ are the ones
  that must: a tool probe re-run seconds later stamps a new `checkedAt`.
- **PRO-0074 A4** — a real keystroke into a TUI under a pty halted a run an MCP client had
  started. The caller received `haltedByPerson` after five of ten steps.
- **PRO-0074 A5** — the run pane drew `Act ×8 · "TextEdit"` while that batch was in flight,
  from a pushed frame.
- **PRO-0074 A6** — the readiness and switches panes drew real grants, lanes and switch
  sources off a live health report.

Two things had to fail first for A4 to mean anything, and both are recorded on the case: a
batch of hover steps was refused for want of foreground and ran in 0.239s, so there was no run
to stop; and the first capture of a "running" TUI showed the empty state because nothing was
in flight. Either would have been a vacuous pass.

## What was not checked

- **The window drawing the fourth permission row** — CASE-0042, declared above.
- **History in the TUI** — the pane exists and stays empty. The trail is sealed and signed and
  `proctor_history` is deliberately absent from the tool catalogue, so no client can read it.
  Giving the TUI a history pane means giving some client a read path into the trail, which is a
  security-surface decision rather than a defect. Recorded as an open question.
- **Mutation survival** — `warrant:assay` still owes that number, and tier 2 needs it.
- **The walkthrough's later slides, the takeover overlay and the run HUD under the new build** —
  unchanged by this wave's work and carried from the previous full run.
