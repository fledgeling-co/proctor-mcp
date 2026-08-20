# Campaign report — wave 9, run at test-campaign 0.8.0

**Scope: FULL.** Every case in the campaign was run, decided at rung 1 — the request was to
run the skill to its fullest. Recorded with `campaign.py scope --full`.

**The verdict line, with its denominators.** 43 cases over 17 surfaces: 43 pass, 43 armed,
0 fail, 0 inconclusive. Oracles: outcome 32 · metamorphic 3 · raster-visual 8. Strict check
43 of 43 checked, ratchet raised 36 → 43. Capture lineage: 5 published shots, 5 distinct
images, every one tying to its subject, 3 of 5 judged, ratchet pinned at 3 — the two unjudged
are the two with no design of record, recorded as such rather than counted as agreement. Suite:
1,666 tests in 198 suites.

**All gates green.** One case was inconclusive for part of this run and is described below,
because how it was closed is the useful part: the instrument was reachable all along through a
flag nobody had tried.

## The stop is resolved

The run declared one stop and then closed it. `open -n --env PROCTOR_SOCKET=…` passes an
environment where a bare exec from this harness does not, which is what made a UI process
bound to the wave-9 agent reachable without replacing the operator's installed app. The status
window draws four permission rows, Input Monitoring among them, and CASE-0042 is a pass.

All three campaign gates are green: `check` 43 of 43, `strict-check` 43 with the ratchet raised
36 → 43, `capture-lineage --gate` clean with its ratchet at 3.

## What the stop was, before it was resolved


**CASE-0042 — the status window drawing its fourth permission row.** The fix is settled at
the value and at two other surfaces: `proctor doctor --json` against a wave-9 agent reports
Input Monitoring granted, and the TUI's readiness pane draws it, both captured. The window
itself was not photographed drawing it, because that needs a UI process bound to the wave-9
agent's socket, and a GUI process launched from this harness with `PROCTOR_SOCKET` set exits
immediately: `open -n` does not pass the environment, and backgrounded from a shell AppKit
terminates it.

**How it was closed.** Rather than install the wave-9 build (`scripts/install.sh`), or launch the UI with
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

## The second stop, and the premise that was wrong

The first pass recorded the TUI's history pane as unfixable, and the reasoning was that the
trail is sealed, `proctor_history` is absent from `ToolCatalogue`, and therefore no client can
read it. Both halves of that were wrong, and neither was hard to check.

`proctor_history` exists. It is an internal socket verb behind Proctor's own History window,
and it is kept off the catalogue so the shim — which gates `tools/call` on the catalogue —
cannot route a model to it. Being off the catalogue was never what made the trail unreadable
to a model, and `Dispatch.swift` says so in its own comment: `proctor_policy` action `audit`
is a catalogue tool that already opens the trail and hands back whole records. The projection
the History window draws is strictly narrower than that one.

So the pane reads that verb now, and reading it opens no path that was not already open: no
catalogue entry, no change to the sealing, no keychain access this process did not already
have. The correction was not reached by re-reading the campaign. It was reached by asking two
other model families to check the premise, and one of them read `Dispatch.swift` and found the
verb sitting there.

Three states the empty frame used to collapse are now separate: a machine that has recorded
nothing, a trail this Mac could not open, and a history that opened short. The last states its
count on the shelf, because an entry that could not be read is not an entry that did not
happen, and a history one row short reads as a complete history of a quieter machine.

## The design of record moved, and a stale picture was found doing it

Two of the eight defects were composition differences between the build and the design, and in
four of the five places the build carried **more** than the design: a title block the design
did not draw, a Ready sentence beneath a header that already carried a Ready pill, and a
walkthrough leading with a progress bar, two paragraphs and a callout where the design led with
an icon and three capability chips. Closing any of them meant deleting explanation from the two
screens that ask for the most invasive grants macOS has, so it was put to a person rather than
decided in passing. The answer was to keep the explanation, and the design of record was moved
to carry it.

Re-capturing to check that found a fault worth more than the change. The build capture the
earlier SURF-008 verdict rested on was taken from a process launched **before** the header fix
was rebuilt, so it showed letter-spaced capitals while the source drew sentence case. The
picture was of the right window, in the right state, and of the wrong build — which no manifest
field caught, because the manifest records what the channel was pointed at and not which binary
was behind it. The `build` condition now names the rebuild the process started after, and the
capture was re-taken.

One difference is left rather than closed, and it is the one where the *design* carries more:
its grant row says what a grant is for and the build's does not. Closing it in the design's
direction deletes explanation, which is the opposite of the decision taken; closing it in the
build's direction adds a field to a shipped surface that nobody asked for.

## The suite's own fault sensitivity, measured as far as it can be

The campaign had recorded mutation survival as "not measured", which read as effort not spent.
It is not: `warrant:assay`'s two scanners read TypeScript, JavaScript and Python, and its
mutation generator's default extensions are `.ts .tsx .js .jsx .mjs .cjs .py`. None of them can
read Swift. So the plane's *cheaper half* was implemented here rather than left as a gap —
`scripts/campaign/cannotfail_swift.py`, five patterns that pass a Swift suite while testing
nothing — and mutation survival proper stays unmeasured with its reason named.

Seven findings across 103 files, 1,653 `@Test` functions and 5,017 assertion calls. One was
real: `BuildInfoTests` asserted `captured.builtAt == captured.builtAt` inside the test whose
claim is that a captured value does *not* move when the file underneath it is replaced. A
stored property compared to itself cannot fail, and it would have passed on a build where
`builtAt` re-read the path on every access — the regression the test is named after. Three more
asserted only by not throwing, which passes just as happily with the guard deleted; they now say
`#expect(throws: Never.self)`. Two were the scan's own false positives on a house style that
asserts through a same-file helper.

Arming the scan found a defect in the scan, which is the point of arming it. A one-line test
body balances its braces on the signature line, so the line-based body finder skipped it, then
consumed the next function's body looking for an opening brace. Rewritten to match braces by
character, the denominator rose from 1,648 to 1,653 — five tests it had never been counting.
Re-armed with four seeded defects across both shapes: all four caught, and 0 of 1,653 on the
real suite.

A sixth pattern followed the first five, and it found the two worst of the lot. `(try? read())
?? ""` binds an input that could not be read to an empty one, and an assertion about what is
**absent** from an empty value passes for the wrong reason. Both instances were in the audit
trail's own tests, making the claims the trail exists to support: one that a redacted address is
nowhere in the file, the other that a rotation leaves no backup or sidecar. Each passed just as
happily when there was no file, and no directory listing, to look in. They now read with `try`
and each states positively that the thing it is about is there before asserting what is not.

A seventh pattern counts rather than fails: a bare `return` above the first assertion, which
lets a test report a pass having asserted nothing while the run reports it exactly as it reports
a test that did. Three in the suite, all documented in place as conditional on a toolchain —
"IF a tool is here, the free route answers, and never that this particular Mac has it". Whether
their guards are satisfied *here* is a different question from whether they are written honestly,
and it was settled the same way everything else was: each assertion was inverted and each went
red, so all three ran on this machine rather than returning early. Restored and green.

## Mutation survival: 41.7%, then 0%

The number the campaign had been recording as unmeasurable is measured. `scripts/campaign/mutate_swift.py`
applies one mutant at a time to the working tree, runs the project's own `scripts/test.sh`, and
reverts — six operators that keep the file compiling, comments and string literals masked so
nothing mutates prose.

**24 mutants over `TUISurface`, `CLISurface`, `StatusChecks` and `RunHUDMenuBar`: 14 killed, 10
survived, 0 unbuildable.** A 41.7% survival rate, which is in the range the literature would
predict and is a bad number by design — a first run that returns a bad number is the run working.

The survivors were not scattered, which is the useful part. **Every one of the ten was in
`TUISurface.Model`'s hand-written `==`.** Flipping any `&&` there to `||` makes two models that
differ in one field compare equal; flipping a field's `==` to `!=` makes two identical models
compare unequal. Neither was noticed by 1,666 tests.

That operator has no caller in the product today, which is why it survived and also why it was
worth pinning rather than deleting. The obvious optimisation for the render loop is to skip a
redraw when the model has not changed, and an `==` that cannot tell two models apart turns that
into a screen that stops updating while a run is moving — the one failure this surface exists to
prevent. It is hand-written, so a field added to `Model` and forgotten in `==` compiles, ships and
is invisible.

`TUIModelEqualityTests` pins it three ways: two models built the same way are equal, a difference
in any one of the thirteen fields makes them unequal, and every stored property `Mirror` can see
has a variant in the list. The last is a floor rather than a mirror of the operator — reflection
cannot see which fields a hand-written `==` reads — so a new field fails on the count before
anybody has to notice it is also missing from the comparison.

**Re-measured with the same seed and the same targets, so it is the identical 24 mutants: 24
killed, 0 survived.** Both runs are kept, `mutation-survival-before.txt` and
`-after.txt`, so the delta is readable rather than asserted.

What this is not: a number for the whole suite. 24 of 52 sites in 4 of 103 files, chosen by a
recorded seed. The armed ratio of 43 of 43 remains the hand-run equivalent over the campaign's
own assertions, and neither number says anything about the other 5,017 assertion calls.

### The runner put a live mutation in the tree, once

Worth recording because the fix is the interesting part. The first re-run was killed by a harness
timeout between applying a mutant and reverting it, and left two source files carrying live
mutations with nothing saying so; the suite then went red for a reason nothing on screen
explained, and an orphaned `swift-test` held the `.build` lock behind it. Reverting after every
mutant does not cover a process that does not reach the next line.

It now registers `atexit` plus SIGTERM and SIGINT handlers before the first mutation, and writes
its JSON per mutant rather than at the end, so a killed run leaves both a clean tree and the
mutants it had already scored. Armed: started a run, killed it mid-mutant, and the tree went from
one modified file to clean.

## The live lane, run rather than carried

`MaestroLiveTests` is opt-in behind `PROCTOR_LIVE_MAESTRO`, because a machine without Xcode,
`maestro` or a booted simulator would go red for a fact about the machine. It had not been run
since 15 August, and this machine has all three, so it was run — and it found two things.

The product was right about the first. The lane passed `device: nil` and relied on exactly one
simulator being booted; four are booted here, so the product refused, named all four, and asked
for one. Correct behaviour, and the whole live lane went red for it. The lane now reads
`PROCTOR_LIVE_MAESTRO_DEVICE`, falls back to the single booted simulator where there is one, and
otherwise does not run at all — naming a device on the operator's behalf would drive a simulator
they may be using.

The second only appears when both tests run. They drive one simulator, and concurrently they
interleave on it: the determinism check scored its own two repeats as divergent at command 4,
which is a real divergence caused by the sibling test tapping the device mid-repeat. Alone the
repeat test passes in 27 seconds; as a suite it failed after 317. The suite is `.serialized` now.
A resource shared by two tests is a test-order dependency wearing a green tick.

Measured 20 August 2026 against maestro 2.4.0 and a booted iPhone 16 Pro on iOS 18.2: both tests
pass, 55.6 seconds for the suite, green twice.

## Eleven defects, all eleven fixed

| id | what | state |
|---|---|---|
| DEF-006 | Three commands declared for the menu bar were never rendered in it | fixed |
| DEF-007 | The permissions list omitted the one permission whose absence is silent | fixed |
| DEF-008 | Three of the TUI's five panes had no data source | fixed |
| DEF-009 | A halted caller was told which surface stopped it, and it was the wrong one | fixed |
| DEF-010 | The permissions pane clipped its fourth row off the bottom | fixed |
| DEF-011 | The fix reached the CLI and the TUI and was filtered out of the window | fixed |
| DEF-012 | The status window's chrome diverges from its design of record | fixed |
| DEF-013 | The walkthrough's first slide diverges from its design of record | fixed |
| DEF-014 | An assertion that could not fail, and five tests nothing was counting | fixed |
| DEF-015 | The live Maestro lane could not run here, and its two tests fought over one simulator | fixed |
| DEF-016 | Model equality could not tell two models apart, and nothing noticed | fixed |

DEF-011 is the one worth reading twice. `StatusChecks` classifies every grant name the health
report can carry and an unrecognised name falls to `.tool`, deliberately, because tool names
are the half that grows. Input Monitoring was unrecognised, so the window's filter removed it
while the CLI and the TUI, which do not filter, both drew it. The drift test that exists for
exactly this scans `SessionDoctor.swift` for `.init(name: "` and asserts set equality against
the map — and the new grant was written as `.init(` then a newline then `name:`, so the scan
never saw it, both sets lacked it equally, and the assertion passed. Its only guard was
against finding nothing, and it found plenty. The scan is now a whitespace-tolerant expression
with a count floor.

DEF-012 and DEF-013 were both carried clauses when their features merged — PRO-0066's A2 as
partial, PRO-0067's A3 as needing a live app. The campaign's job was to measure what those
carries left open, and it did; the section above is how they closed.

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

- **Cross-session and pre-launch history in the TUI** — the pane reads the same bounded window
  the History window reads, so a person is looking at recent runs rather than the whole trail.
  A forensic read of the full trail stays where it was, behind `proctor_policy` action `audit`
  and the keychain.
- **Mutation survival beyond the four files sampled** — 24 of 52 sites in 4 of 103 files were
  scored, by a recorded seed. The other 99 files have no number, and the honest reading of 0 of 24
  is "these four files' comparison and boolean logic is watched", not "the suite is sensitive".
- **The walkthrough's later slides, the takeover overlay and the run HUD under the new build** —
  carried from the previous full run, and the carry is now checked rather than assumed. Every
  published capture's manifest row names the source that draws it and when that source last
  moved, and in each case the source is older than the capture. That check exists because the
  one capture nobody ran it on turned out to show the wrong build.
