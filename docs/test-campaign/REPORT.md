# Campaign report — wave 10, run at test-campaign 0.8.0

**Scope: FULL.** Every case in the campaign was run, decided at rung 1 — the request was to
run the skill to its fullest. Recorded with `campaign.py scope --full`.

**The verdict line, with its denominators.** 58 cases over 21 surfaces against 44 requirements:
58 pass, 0 blocked, 0 fail, 0 inconclusive, 58 of 58 passing cases armed. Oracles: outcome 44 ·
metamorphic 5 · raster-visual 8 · interactive-glass 1. Strict check 58 of 58 checked (100%),
ratchet raised 43 → 57 → 58. Capture lineage: 5 published shots, 5 distinct images, every one
tying to its subject, 3 of 3 judgeable pairs judged `pass`, ratchet held at 3 — the other two are
structurally unjudgeable, being capture engines with no design of record, and are named as such
rather than counted as agreement. The seeded swap was run and caught. Suite: 1,814 tests in 214
suites, green.

**`campaign.py check` exits 0.** It exited 1 for most of this run, deliberately, over one blocked
case: the guest lane's central claim, that a session attached to a macOS guest executes inside it,
had been measured nowhere. It has now been measured on a live guest, and the section below carries
what it took. `guest-glass` is recorded as attached with its artifact, its build command and what
witnessed the guest agent reaching the guest's own window server.

## What the previous run's clean exit was hiding

The last run reported 43 of 43 cases checked, every requirement covered, every surface covered,
and exit 0. Every number in it was true. Three things were wrong with the denominator it counted
over, and all three are the same failure: covering a subset and reporting it as the whole.

**The `cli` lane had no denominator at all.** `campaign.json` has declared `cli` as a lane since
the campaign was created. There was no requirement naming the CLI, no surface for it, and no case
mentioning it — `grep -ci "proctor-cli|CLISurface|exit code" cases.json` returned 0. PRO-0073
shipped 21 verbs, six exit codes and generated completion, and the campaign counted none of it
while reporting 100%. The 100% was true of a denominator that excluded the whole surface.

**PRO-0076's surface was absent.** Guest attach, in-guest execution, the counted lane, the queue,
the never-evict rule, the audited lifecycle, the pool on the doctor wire and `tart` as a third
provider — none of it was in the requirement inventory, so none of it was missing from coverage
either.

**The stored evidence described a build four features old.** Every evidence note in `cases.json`
names "1526 tests in 176 suites". The suite is 1,798 in 211. Fourteen commits touching `Sources/`
landed between the two.

Eleven requirements (REQ-034..REQ-044) and four surfaces (SURF-018..SURF-021) were added, and
the gate immediately refused with `11 requirement(s) no case traces to` and `4 surface(s) with no
case at all`. That refusal is the finding.

## DEF-019 — the operator CLI exited 0 when a check failed

Found by writing the first case the `cli` lane has ever had, and running the built binary against
the live agent rather than reasoning about it.

`CLISurface.exit(forReply:lane:)` decides the process exit code. Its assertion branch read
`$0["ok"]?.boolValue == false` on each element of `assertions`. No reply has ever carried that
key: `SessionAssert.swift:45` writes `"status"` per assertion, one of pass/fail/skipped, and puts
the summary at the top level. `nil == false` is false, so the predicate matched nothing and the
function returned `.ok`. Neither the top-level `"ok"` at `SessionAssert.swift:81` nor the
top-level `"failed"` count at `:77` was consulted at all.

Measured twice against the live agent before the fix:

| command | reply | exit | expected |
|---|---|---|---|
| `proctor assert` with a failing check | `{"ok":false,"passed":0,"failed":1}` | 0 | 1 |
| `proctor wait` on a condition that never held | `{"ok":false,"timedOut":true}` | 0 | 1 |

A third instance was present by inspection and is now covered: `proctor_kill` carries its
failures as a top-level `"failed"` count that nothing read.

This defeated the surface's reason for existing. `spec-PRO-0073.md` says "1 means the call worked
and your check failed" and "1 and 3 must never be confused: one is a failed check, the other is
nothing measured". A CI job reading the exit code would have concluded the assertion passed while
the JSON on its own stdout said it failed.

**Why nothing caught it.** `CLISurfaceTests.swift:175`, "a failed assertion exits 1 — the call
worked and the check did not", built its own reply: `.object(["assertions": .array([.object(["ok":
.bool(true)]), .object(["ok": .bool(false)])])])`. That is a shape the product does not emit. The
test asserted a value the test itself wrote, so it passed against a fiction while the real path
exited 0. It is the same shape the PRO-0076 verifier caught in A7 a few hours earlier: an
assertion standing on a value the test constructed rather than one the code produced.

The fix reads the top level first, because that is where every verdict-bearing tool puts its
answer. The replacement tests are built from the shape the product actually emits, and one of
them is a control: a passing assertion must still exit 0, which is what stops a fix that answers
`verdictFailed` to everything from satisfying the same suite. Armed by restoring the original
predicate: five issues across the failed assertion, the skipped assertion, the timed-out wait and
the failed kill, with the control correctly staying green.

## The sweep that reported zero over a predicate that could not fail

The first refusal-honesty sweep invoked all 21 verbs with no arguments and printed
`examined=21 failures=0` on both predicates. The number was worthless. Sixteen verbs returned a
usage error, which the remedy predicate exempted, and the other five succeeded — so the predicate
examined 21 rows and could not have failed on any of them. Uniform zeros are the signature of a
dead predicate, and this one was dead.

Rewritten to point every verb at a socket nothing is listening on, which is a refusal every verb
must produce and the one CI is most likely to hit:

```
A · agent-unreachable did not exit 3:  examined=21 failures=0
B · refusal carried no remedy:         examined=21 failures=0
C · refusal did not name the socket:   examined=21 failures=0
```

Armed by removing the refusal condition: all three predicates fail on all 21 rows. Both versions
are kept in the evidence, because the reason the first was worthless is the more useful half.

## Mutation survival, measured for the new code and partial by denominator

The previous report named this as unmeasured. It is now measured over the seven files wave 10
added or changed, and the number is partial on purpose.

188 sites, 40 selected by seed 20260820, **11 ran**: 3 survived, 8 scored killed. One of those
kills is not trustworthy and is recorded as such. Timings ran 7s, 7s, 6s, 7s, 7s, 6s, 11s, 16s,
47s, 40s and then mutant 11 sat for the full 900s timeout, because another project on this machine
was building concurrently. The runner scores a timeout as killed, which is right for a mutant that
hangs the suite and wrong for one whose test run was starved. At up to 900s each the remaining 29
would have produced kills nobody could tell from contention, so the run was stopped rather than
continued into an unreliable number. **The honest kill count is 7 of 10 scored.**

The survivors are trustworthy in both directions, which is why the partial is still worth having:
starvation can turn a survivor into a false kill, but it cannot turn a kill into a false survivor.

All three were in the same untested corner of `TakeoverReport`, and all three are now closed:

| Mutant | What it did | Why nothing caught it |
|---|---|---|
| `swallowed > 0` → `>= 0` | The report gains "Somebody used the machine 0 times while it was held" on a run nobody touched | Every existing test passed a non-zero count, so the clause was never watched for its absence |
| `/ 1000` → `/ 1001` | The held duration is wrong | The only value under test was 2400ms, and 2.400 and 2.397 both format to "2.4" |
| `1 << 1` → `2 << 1` | `option` becomes 4, which is `control` | Nothing asserted the modifier flags were distinct bits |

The first is the one worth reading twice: a report claiming interference that never happened, on
the surface whose entire job is telling a person what Proctor did to their machine.

Armed by re-applying all three together after the tests were written: 6 issues across the three
tests, including `Set(all.map(\.rawValue)).count -> 3 == all.count -> 4` and the note containing
"Somebody used the machine" on a `swallowed: 0` report. Restored, 1,802 tests in 211 suites green.

What this does not say: 11 of 188 sites is 6% of the surface under one seed. Three survivors closed
means those three behaviours are watched. It says nothing about the other 177 sites and nothing at
all about `ProctorAgent`, which was not a target.

## What is still open

**Mutation survival is measured but thin.** 11 of 188 sites under one seed, with 29 selected
mutants unrun because contention made their kills unreadable. `warrant:assay` still owes its own
number and tier 2 needs it; the export correctly reports `mutation_measured: false`, because a
value copied from this run into a generated file would be a second source that drifts.

**The warrant chain stops at `charter absent`.** `rollup_classes.py` refuses without
`.warrant/warrant.toml`. That file declares defect classes and a risk limit, which is a decision
rather than a mechanical step, so it is left for a person rather than invented here.

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
killed, 0 survived.** Both runs are kept, `mutation-survival-before.txt` and `-after.txt`, so the
delta is readable rather than asserted.

Then measured a third time, because the tests that produced the second number were changed after
it: the cannot-fail scan flagged their reflexivity assertions, `x == x`, which is exactly the
shape it exists to report. It was right about the shape and the assertion was doing real work, so
each value is now built twice and the pair compared — the same claim, no longer leaning on
identity, and no standing exception in a rule that would stop being trusted the moment it had
one. Changing the tests after measuring invalidates the measurement, so it was taken again on the
identical 24: 24 killed, 0 survived.

One thing a reader will trip over: `.warrant/suite-health.json` still carries
`mutation_measured: false`. That is correct and is not stale. The field means *warrant's own
assay* has not run, and it has not, because it cannot read Swift — which is the whole reason this
section exists. The number lives in `evidence/mutation-survival.json` and here, and deliberately
not in a third place: a value copied into a generated file is a second source, and this repo's
whole thesis is that a second source drifts.

### Widened: 50% across ProctorCore

The four-file number said nothing about the other 99, so the assay was widened to all 77 files of
`ProctorCore` — 1,991 sites — with the operator table filled out to eleven along the way, because
the docstring had been claiming an integer-literal increment the table did not have.

60 were selected by a recorded seed and 49 ran before the run was killed. **48 scored: 24 killed,
24 survived, 1 unbuildable. 50% survival**, which is in the range the literature would predict and
is the first honest number this suite has had for anything wider than four files.

Thirteen of the twenty-four survivors are integer literals, many of them geometry and layout
constants in pure values. Eleven are logic, and three were read closely:

- **`RunHUDSurface.Chip.==`** compared field counts, and nothing had ever compared two chips with
  different counts. That is the *second* hand-written `Equatable` this wave has found unwatched,
  and the same shape both times, because Swift cannot synthesise `==` over an array of tuples.
  Pinned, and armed against the exact mutant that survived.
- **`RunHUDGate.onSegment`'s `<=` boundary** is an equivalent mutant. `onSegment` is reached only
  from `crosses`, `crosses` only when no point is `contains`, and `contains` uses `>=`/`<=` on both
  axes — so every point that could exercise the boundary was caught one step earlier. No test can
  kill it.
- **`RunHistory`'s `a.offset < b.offset`** sort tiebreak differs from `<=` only for equal offsets,
  and offsets are unique enumeration indices. Equivalent as well.

Both equivalents are recorded rather than chased. A survivor no test could kill is not a gap, and
a suite contorted to kill one is worse than the survivor.

What this is not: a number for the whole suite. 24 of 52 sites in 4 of 103 files for the first
run, 48 of 1,991 in 77 for the second, both by a recorded seed. The armed ratio of 43 of 43 remains the hand-run equivalent over the campaign's
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

## Eighteen defects, all eighteen fixed

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
| DEF-017 | Eight of the CLI's twenty-one verbs could not be given their main argument | fixed |
| DEF-018 | Half of ProctorCore's sampled mutants survived, chip equality among them | fixed |
| DEF-019 | The operator CLI exited 0 when a check failed, on a branch no reply can satisfy | fixed |
| DEF-020 | The `lume` adapter asked for `--json`, which lume 0.5.3 rejects by name | fixed |
| DEF-021 | A second copy of the guest-action list in the dispatcher refused `attach` and `detach` | fixed |
| DEF-022 | `Bundle.module` traps in a shipped `.app` instead of returning nil, and crash-looped the guest agent | fixed |
| DEF-023 | A relayed guest reply carried the host's `machine`, so a guest result could read as a host one | fixed |

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

## The guest lane, settled live rather than blocked

CASE-0056 was the campaign's only blocked case and the only thing holding `check` at exit 1. It is
now a pass, armed, with three evidence files, and `guest-glass` is recorded as attached.

What changed was the guest, not the product's claim. The lane had been staged on
`proctor-mac-node`, a `tart` clone, and stopped at *"Domain does not support specified action"*
from `launchctl bootstrap gui/501`. That was read as structural to macOS guests, and it is not:
`stat -f %Su /dev/console` reads `root` on that clone and `lume` on a guest created with
`lume create --unattended`, which configures autologin and so boots into a session `gui/501`
resolves to. A guest built that way took the wave-9 build, bootstrapped its agent, and accepted
both TCC grants through its own System Settings over VNC.

The proof runs from one persistent MCP session: attach to `proctor-guest`, activate Calculator
inside it, actuate five steps, read the display back through the guest's accessibility tree, detach,
and confirm no Calculator ever ran on this Mac. It returned `4×7` and `28`, twice, and the VNC
capture of the guest's virtual display shows the same two strings. Two witnesses matter here
because a value read back through the socket that wrote it would prove routing rather than
execution.

VNC reports no per-frame status, so the manifest row records `frameStatus: "unreported"` and names
the accessibility corroboration, rather than claiming a completeness the channel does not offer.
`--frame-status complete` was passed once and withdrawn: it would have been a claim the instrument
never made.

### The spec's own manual-gate recipe was wrong, and failed quietly

Its final step said to run `proctor guest --action attach` and then a separate actuating call. That
launched Calculator **on this Mac**. An attachment is keyed by the peer process on the socket,
`"\(pid):\(startTime)"`, so a one-shot CLI attaches, exits, and the next invocation is a different
peer with no attachment — and a call with no attachment is a host call, answered as one. The
product is behaving as designed; the recipe asked one process to hold state across two. The spec
now names a persistent MCP session as the instrument and says why a CLI is the wrong one.

This is the shape the campaign exists to catch. A green result from the documented procedure would
have been a guest verdict about the host.

### Four product defects, found only by running it

`lume` 0.5.3 rejects `--json` by name, so every listing failed and the provider looked absent
(DEF-020). A second copy of the guest-action list in `Dispatch.swift` had drifted and refused
`attach` and `detach`, which is the whole lane (DEF-021); the fix deletes the list rather than
extending it, because `Session.guest` already switches on the action. `Bundle.module` traps rather
than returning nil when its bundle is not at the `.app` root, which crash-looped the guest agent
with *"could not load resource bundle"* (DEF-022). And a relayed guest reply carried the host's
`machine` field, so a guest result could be read as a host one (DEF-023).

All four were armed by reverting the fix and watching the suite go red. A fifth finding was a suite
flake rather than a product defect: `SessionHUD.hudStatus()` read a process-wide singleton another
test could move under it, which showed up as roughly one failure in five. It is an injectable probe
now, and nine consecutive full runs have been clean.

## The blind pass is 96% noise, and the noise is not the vocabulary

**PRO-0079.** `vacuity-check.py`'s third pass reported `examined=1857 mutating=516
re-read-after=438 blind=78` — 78 tests that call a mutating verb and never read the state back,
across 30 files. Nobody had read one. Seventy-eight genuine gaps would be the largest test defect
this repo has recorded, so the number was worth measuring before it was worth acting on.

**The rate, with its denominator.** 57 of the 78 findings were read and classed: five per bucket
from `act` (13), `unlock` (12), `release` (9), `set` (6) and `claim` (6), drawn at seed 20260821,
plus a **census** of the 32-finding tail — every finding under the thirteen verbs with four or
fewer. That is 73.1% of the population.

**Fifty-seven of fifty-seven were false positives. Zero were genuine.** The tail is exact at 0 of
32. In the large strata, 0 genuine in 25 drawn from 46 refutes four or more at 95%
(P(observe 0 | K=4) = 0.037) and does not refute three (P = 0.088). So the honest claim is **at
most 3 genuine among all 78, a false-positive rate of at least 96.2%** — not "zero", which the
sample cannot support, and not "78 defects", which is what the raw count invites.

**A zero from a pass that cannot fire is worth nothing, so the pass was armed.** On a copy of the
tree, one read-back line was deleted from `AuditRotationTests.clearingEmptyIsANoOp`, a test
currently in the re-read set. The count went 78 → 79 and named that test. The worktree's own
`Tests/` was never the copy that was cut.

**Six shapes, and only one of them is the reader list.**

| Shape | Count | What in the check produces it |
|---|---:|---|
| false-mutator | 17 | The mutator matches `verb\w*\s*(`, a prefix. It fires on the test's own name in the `func` line (`stopEverywhere(`, `actNotIdempotent(`), on a pure query (`pauseLimit(`, `raisesSheet(`, `attachIdleLimit(`), and on an enum case inside the assertion (`.stopRun(`, `.yielded(`, `.rotate(.size)`) |
| vocabulary | 15 | A genuine read-back follows in an idiom the reader list lacks — `post.begin(pid:)` then `#expect(post.recognisedPids == [9001])` |
| return-value | 10 | The mutator is the subject under test and the assertion reads what it returned |
| teardown | 9 | The test reads its observable, then calls `release()`/`cancel()` to clean up. The check looks at the *last* mutator, not at whether any read followed any mutation |
| not-a-test | 4 | A test double's method counted as a test, because the helper filter only excludes a name called more than once in the same file |
| body-bleed | 2 | The body regex does not match `private func`, `static func` or a computed property's `set`, so a test's extracted body runs on into the next declaration and picks up its mutator |

**Fifteen of fifty-seven. That is the finding.** Four of the six shapes cannot be reached by any
reader list at all, and they are 42 of the 57. Every reader candidate was measured two ways —
files using it, and its effect on the count — and none moved the number: `.contains` reaches 93 of
the test files and removes 8; nothing else removes more than 3. `.calls` and `.recorded` were
added, being one idiom in two spellings (the spy double's ledger, 8 files, 45 uses) proved by two
sampled findings, and the count is now **76**. Everything else was refused with its numbers in
`campaign.json`'s `why` field, including an out-of-family reviewer's dissent arguing these two
should have been refused as well.

**Nothing was fixed, because nothing was broken.** The conversion contract says a genuine finding
gets its read added and never gets deleted. The sample produced no genuine finding, so no test was
edited and no production source was touched. The remaining 76 stay in the tool's output: a blind
pass that reports zero because its vocabulary was tuned until it did is worth nothing.

**What this means for a gate.** At a false-positive rate of at least 96.2%, dominated by causes a
vocabulary cannot reach, the blind pass is a reading instrument and not a gate. It earns a gate
when its matcher is looking at tests — when a body ends at the next declaration of any visibility,
a mutator does not match the `func` line that opens the body, and "read after mutation" means any
read after any mutation rather than after the last one.

Evidence: `evidence/PRO-0079/` — `blind-findings-before.txt` (all 78), `classification.tsv` (57
verdicts with the read that acquitted each), `rate.txt` (the arithmetic and the bound),
`arming-control.txt`, `reader-sensitivity.txt`, `out-of-family-review-grok.md`,
`blind-findings-after.txt` (76). Spec `docs/specs/spec-PRO-0079.md`, plan
`docs/plans/plan-PRO-0079.md`.

## The external denominator is 22, and it is a `len()` rather than a printed list

**PRO-0083.** Wave 11 scoped twelve external requirements because `campaign.py check` printed
twelve. The gate caps that list at twelve and says nothing about the cap. The population is:

```
$ python3 -c "import json; d=json.load(open('docs/test-campaign/inventory.json'));
  print(len([r for r in d['requirement'] if r.get('effect') not in (None, 'none')]))"
22
```

PRO-0077 took four and PRO-0078 took eight, so **ten were named by no item in the wave** —
REQ-023, 024, 027, 028, 029, 033, 034, 035, 037, 039. That is the campaign's own first failure
mode, covering a subset and reporting it as the whole, arriving through the gate rather than
through a surface map. The number was one `len()` away throughout, and PRO-0077's runner found the
gap from arithmetic rather than from the gate. Recorded as DEF-041 so the cause sits in the
registry rather than in a runner's report, and written into this section so the denominator is a
count of the registry from here on.

**Ten cases, one per requirement, because they are different guarantees over shared providers.**
Six of the ten rest on the agent's single `AF_UNIX` socket. A case covering two of them would let
one guarantee's silence hide behind the other's noise.

| Case | Req | Effect | Count | What the recorder is |
|---|---|---|---:|---|
| CASE-0080 | REQ-035 | `ipc` | 3 | the trail's sealed bytes on disk, read with a fresh `FileHandle` |
| CASE-0081 | REQ-034 | `ipc` | 3 | exit status through `waitpid`, plus the server's answered connections |
| CASE-0082 | REQ-029 | `ipc` | 3 | frames delivered on a held connection, and the `RunControl` latch |
| CASE-0083 | REQ-033 | `ipc` | 20 | reply bytes off the socket, projected into readiness, switches, history |
| CASE-0084 | REQ-027 | `ipc` | 3 | a stalling listener's own accepted-descriptor count |
| CASE-0085 | REQ-037 | `ipc` | 3 | the guest server's own dispatcher, with the host's actuation count beside it |
| CASE-0086 | REQ-039 | `subprocess` | 7 | sentinel files carrying each child's `$$` and the argv it was given |
| CASE-0087 | REQ-024 | `subprocess` | 0 | `inconclusive` — see below |
| CASE-0088 | REQ-023 | `ipc` | 3 | replies off the Reflector's own socket, decoded by `JSONSerialization` |
| CASE-0089 | REQ-028 | `device` | 2 | the window server's list, `screencapture -l`, and the target's AX server |

Every count was read off an arming run with the non-zero assertion inverted, so each one is the
number the recorder actually saw rather than a number chosen in advance. Every case carries its
own sabotage in the same test body, so the arming run and the passing run are one measurement
taken twice on one build.

**REQ-035 is the one where a wrong answer would have been a security answer.** The claim is that
the audit trail records which front end called, read from the peer process rather than from the
request. Two genuinely different front-end children — the real `proctor-cli` and the real
`proctor-shim`, both built by the same `swift build --build-tests` — were driven against one real
`Server` on a private socket, and the trail was read back off disk and opened with `AuditSeal`. The
rows read `via: cli` and `via: mcp`. A third child, neither shipped name, sent a request whose body
asked to be recorded as `cli`; its row carries `via` **absent**. Same wire bytes, different peers,
different rows — the field is not reachable from a request.

**REQ-028 shows content and absence in the same second, which is the only way it proves anything.**
PRO-0078 found `proctor_capture` reporting `status: complete, trustworthy: true` over 2,942,720
pixels of `RGBA(0,0,0,0)` of a Proctor-owned window (DEF-025, open). The exclusion working and the
capture path not noticing that exclusion was all it got are one mechanism seen from two sides, so a
blank frame here would prove nothing. THE ABSENCE: `CGWindowListCopyWindowInfo` reported two
Proctor Agent windows on screen, CG windows 130709 and 130710, pid 76491, layer 1000, alpha 1,
`sharingState` 0 — and `screencapture -l`, run by a third process, refused both outright with
"could not create image from window", which is a stronger negative than an empty frame because the
channel could not produce an image at all. THE CONTENT, same utility, same second: CG window
130785, Activity Monitor, pid 28274, a 2536×1640 frame carrying 3,159 distinct colours at 0.054%
transparent, luminance standard deviation 14.25. The subject is proved by text rather than by
filename — an independent AX client walked pid 28274 and read 270 strings over 361 nodes, among
them "Activity Monitor — All Processes" and "coreaudiod", both of which are painted in the
delivered frame. The blank-frame detector was armed against a hand-built transparent PNG, which
reads 1 distinct colour and standard deviation 0.0.

`sharingType = .none` on the run HUD and the takeover overlay is correct and was not touched.
Evidence must not change because somebody was watching.

**REQ-024 resolves `inconclusive`, and the reason is a registry error rather than a missing
instrument.** The census records REQ-024 with effect `subprocess` and names `Process()` in
`Actuation/CuaClients.swift` as its provider. The browser-routing path reaches neither, established
in source: `BrowserTarget` is pure by its own header, `Session.browserHandoff` returns a disclosure
six call sites attach to a reply, `ToolProbe`'s header reads "cached, and never executed", and
`ToolLocator.locate` decides availability with a stat. The two `Process()` sites in that file are
real and spawn `cua-driver`, but they belong to the CUA delegation lane rather than to browser
routing. The only boundary this capability crosses is a filesystem **read**, and the campaign's
closed class list has no member for it. The read was measured anyway — the production locator over
two real directories answers `missingCompanions: ["obscura-worker"]` for one and none for the
other, and `chmod 0600` takes availability to false — and recorded under an `inconclusive` case
rather than dressed up as a witness of a class it is not. REQ-024's row is unchanged: not marked
`n/a`, not reclassed to `none`, which would silence the gate rather than answer it. DEF-040.

**REQ-007 was not revisited.** PRO-0078 recorded it `inconclusive` against a real ceiling, and the
ceiling was re-read in source here rather than re-argued: `PersonInput.isAPerson`
(`Contention.swift:265`) returns true only for `sourcePid == 0`, and
`ContentionMonitor.considerInput:199` guards on it. Zero is what hardware carries and no process
can forge it. A ceiling that was measured stays measured.

**The suite, before and after.** 1,818 tests in 215 suites → **1,827 in 217**, exit 0, 21.376
seconds at load average 176. `./scripts/test.sh` owns that verdict, and it refused every one of the
deadlocked runs correctly: an absent verdict line is a failure, and it reported one rather than
reading the silence as green.

That verdict took a second pass to earn. The first recorded green run did not reproduce: on a clean
tree the full suite failed twice, identically, at 143 seconds with four issues, and wedged outright
at higher load — 3 seconds of CPU in 9 minutes 24 of elapsed time. The cause was this item's own
forging arm, which launched a hard-linked copy of `proctor-cli` at a fresh path. A fresh path is a
first launch for `syspolicyd` however the inode is shared, and it was being assessed while fifteen
of the sixteen cooperative threads sat inside `SecStaticCodeCheckValidity`; `driveBlocking`
terminated it at its 120-second bound while the same test passed alone in 0.416 seconds. The arm
now launches nothing — it is a raw AF_UNIX peer that is the test process itself, which the kernel
names `proctor-mcpPackageTests` and which maps to no front end — and the run went 143s → 16.4s and
four issues → one. The claim got stronger in the same change: `--via` is not a flag `proctor-cli`
parses, so the old arm never put its forgery on the wire, where the hand-framed request now carries
`"via":"cli"` in the object the server decodes and the trail row still reads nothing.

**What the gates read after this item.** `campaign.py check`: external effects
`examined=22 witnessed=20`, up from 11 — and it still exits 1, correctly, over the two
`inconclusive` cases. `strict-check` 79 of 81 checked, ratchet raised 70 → 79 in the same commit.
`capture-lineage --gate` exit 0 at ratchet 5, published 7 and distinct 7 — **unmoved, and checked
rather than assumed**: CASE-0089's frame is a case-level artifact under
`evidence/PRO-0083/glass/`, not a surface's `shot`, so the lineage population it is measured
against genuinely does not include it. Wave 11a's lesson was that a gate reading an empty
population exits 0 while examining nothing, so the count was read before and after rather than
inferred.

**The gate did not return a verdict at first, and what that cost is the second finding.** Adding
nine integration tests beside the suite stopped `./scripts/test.sh` completing at all. `sample` on
the wedged process, repeatedly and across samples seven minutes apart, put fourteen to fifteen of
the sixteen cooperative-pool threads inside one call: `Session.doctor` →
`SignatureVerdictCache.verdict` → `CuaPreflight.verifySignature` → `SecStaticCodeCheckValidity`,
in seven unrelated wiring suites. It is a synchronous blocking call made from inside the session
actor, and Swift's cooperative pool has exactly `activeProcessorCount` threads and never grows.
`codesign -v` on the same binary returned instantly from a shell throughout, so the system was not
the bottleneck — the process was. Recorded as DEF-043.

That leaves two free slots, and anything needing a third while holding a lock other tests block on
deadlocks the run. This item hit it three ways, each fixed in the test rather than in the product:
blocking waits on child processes and sockets moved onto threads the tests own; `TrailIsolation`
held only across code that never suspends, so the lock never waits on a pool slot two other trail
suites are already blocked for; and the witness sessions given tool probes that answer from a
table instead of locating the real `cua-driver` on this machine. Attribution was measured rather
than assumed at each step — `--skip` over this item's two suites passed at 1,818 tests in 12.5
seconds while the full run never returned, and the same comparison was re-run at load average 500
so that load could be ruled out as the confound.

**A test wrote the operator's real policy file, and a neighbouring witness failed because of it.**
Driving `proctor-cli policy --action configure --block` to reach exit code `refused` created
`~/Library/Application Support/app.fledgeling.procter/policy/policy.json` on this machine with the
test's bundle id blocked. `AuditLog` carries `seams.directory` and an `isTestProcess` interlock for
exactly this reason; `PolicyStore` carries neither. PRO-0077's REQ-015 witness then failed with
`policyDenied` **in a later run where this item's suites were skipped entirely**, because the block
had outlived the process that wrote it. The entry was removed from the operator's file, the
configure was dropped, and CASE-0081 now records that the policy gate is unreachable from that lane
rather than dropping it silently. DEF-042.

**The ceilings, named rather than left as silence.** The nine passing cases stand on the portable
floor from `references/effect-boundary.md`: real child processes, real sockets answering real
connections, real files read back with fresh descriptors, and a third process holding the recorder
wherever one could. There is no kernel bar anywhere in this item — no `dtrace`, no `eslogger`, no
`execve` census — because SIP is on and this suite has no privilege for one. CASE-0088's server and
client are the same process, so what it witnesses is a real `AF_UNIX` round trip through the kernel
and a real AppKit walk rather than a cross-process one; the agent ships `NullReflectorBridge`, so
there is no in-repo production client to drive it from a second process, and writing one would be
building the subject rather than witnessing it.

**One instrument fault caught before it could read zero for a structural reason.** CASE-0088's
first run asked the Reflector for `"constraints": true` and got no constraints key at all, because
`Runtime.decode(options:)` reads `"includeConstraints"`. A constraints assertion on that request
would have failed for a wire-protocol reason and been read as a product one — the same shape as
PRO-0078's probe counting survivors by a mark the tagged arm could not carry. Before believing a
zero, check the instrument could have reported non-zero.

## What was not checked

- **Twenty-one of the seventy-eight blind findings** — the `act`, `unlock`, `release`, `set` and
  `claim` buckets were sampled at five each rather than censused, so 21 of their 46 findings were
  never read. The bound stands in for them: 0 genuine in 25 drawn refutes four or more at 95%, so
  at most 3 of the 78 are genuine. That is a bound and not a reading, and if the pass is ever
  gated on, those 21 are the first thing to read.
- **Cross-session and pre-launch history in the TUI** — the pane reads the same bounded window
  the History window reads, so a person is looking at recent runs rather than the whole trail.
  A forensic read of the full trail stays where it was, behind `proctor_policy` action `audit`
  and the keychain.
- **The 21 survivors not yet read** — the widened run scored 48 sites across ProctorCore and 24
  survived. Three were read and settled (one fixed, two equivalent); the other 21 are a named
  backlog with a number against them rather than an absence: 13 integer literals and 8 logic sites.
  Nothing outside ProctorCore has been sampled at all — the agent and UI targets have no number.
- **The walkthrough's later slides, the takeover overlay and the run HUD under the new build** —
  carried from the previous full run, and the carry is now checked rather than assumed. Every
  published capture's manifest row names the source that draws it and when that source last
  moved, and in each case the source is older than the capture. That check exists because the
  one capture nobody ran it on turned out to show the wrong build.
