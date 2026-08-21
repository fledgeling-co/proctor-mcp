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

## Thirty-two defects, twenty-four fixed and eight open

Corrected in PRO-0080. This table held DEF-006..023 and nothing else, while `inventory.json`
held twenty-eight — and **all five open defects were among the ten missing**, so a reader of the
report saw no open defect at all, under a heading that said all of them were fixed. The eighteen
rows that were here agree with the inventory on every status; the drift was omission, in the
opposite direction from the one brief `73` predicted. DEF-031.

**There is no DEF-024, and that is deliberate.** Wave 11a's merge backfilled wave 10's four
defects as DEF-020..023 and renumbered PRO-0078's five to DEF-025..029, so the sequence skips one.
Twenty-three plus five is twenty-eight, and PRO-0080 adds four more for thirty-two. A reader counting sequentially would otherwise report a
record that was never lost.

| id | what | state |
|---|---|---|
| DEF-001 | Reopen from Dock or open -a does not restore the Status window | fixed |
| DEF-002 | Status window kept claiming Ready while the agent was wedged | fixed |
| DEF-003 | Installed Proctor.app is Developer ID signed but not notarised or stapled | fixed |
| DEF-004 | Campaign recorded a refusal the product does not perform (profile filtering) | fixed |
| DEF-005 | The drawn pointer was not excluded from screen capture | fixed |
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
| DEF-025 | proctor_capture reports a fully transparent frame as status complete and trustworthy true | open |
| DEF-026 | A run whose MCP peer dies keeps the agent queue past the 900-second pause backstop | open |
| DEF-027 | Forty events swallowed by the takeover block produced no yield and no held reason | open |
| DEF-028 | An agent window reports sharingState 1 where CASE-0032 records all three overlays at 0 | open |
| DEF-029 | A bounded-probe test asserts wall-clock elapsed and fails on a loaded machine | open |
| DEF-030 | The census control exercises one of the gate's two passes, so unclassed stayed an unwatched zero after it ran green | open |
| DEF-031 | REPORT.md's defect table held 18 of the inventory's 28 records, and every open defect was among the missing | fixed |
| DEF-032 | The mutation runner's integer-literal operator mutates closure shorthand $0, spending a sampled slot on an edit the compiler must reject | open |
| DEF-033 | Nineteen of twenty-two trustworthy-scored ProctorAgent mutants survived, against half in ProctorCore | open |

PRO-0080 adds four: DEF-030 (the census control reaching one of the gate's two passes),
DEF-031 (this table itself), DEF-032 and DEF-033 (the mutation runner, and what it measured).
DEF-031 is fixed by the correction above; the other three are open against the campaign's own
instruments. Of the eight now open, five predate this item and are the ones to read first: DEF-025 (`proctor_capture` reporting a fully
transparent frame as complete and trustworthy), DEF-026, DEF-027, DEF-028 and DEF-029 (a
wall-clock assertion that fails on a loaded machine). None was fixed by the item that found it,
each deliberately, and each says why in `inventory.json`.

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

## The census gate, watched failing

`vacuity-check.py` ships `--seed-strengthen` as the skill's own arming rule turned on its own gate:
strengthen a requirement's declared constraint to one the registry cannot satisfy, and require the
census to go red. **It had never been run against this campaign.** Until it had, the census's
`unclassed examined=45 findings=0` and `uncensused examined=22 findings=0` were indistinguishable
from predicates that cannot fire — which is exactly what the `blind` pass was before its vocabulary
was replaced, at `examined=1857 mutating=1 blind=1`.

**The precondition is checked rather than assumed.** `_census_clear` is
`not (unclassed or uncensused)`. If the census were already red, `after` would be red for a reason
the mutation did not cause and the tool would still print *the gate bites*. So the census is read
immediately before, and `before=clear` in both transcripts is load-bearing rather than decorative.

Verbatim, both directions — REQ-017 (`subprocess`, the requirement whose witness PRO-0077 built and
merged) and REQ-001 (classed `none`). Full transcript at `evidence/census-control.txt`.

```
$ shasum -a 256 docs/test-campaign/inventory.json
9215d5be401c61b55d3a85ef697279dc4f99dd389e6ce0226b232a7bdb225885  docs/test-campaign/inventory.json

$ python3 vacuity-check.py docs/test-campaign --gate
unclassed:  examined=45 findings=0
uncensused: examined=22 findings=0
blind:      NOT RUN — pass --tests <root> to scan the test tree. This is the cheapest of the three and needs no privilege.

vacuity: requirements=45 external=22 findings=0
exit 0

$ python3 vacuity-check.py docs/test-campaign --seed-strengthen REQ-017
seed-strengthen REQ-017: before=clear after=red
The gate bites: strengthening the constraint turned it red, and the registry was restored byte-for-byte.
exit 0

$ python3 vacuity-check.py docs/test-campaign --seed-strengthen REQ-001
seed-strengthen REQ-001: before=clear after=red
The gate bites: strengthening the constraint turned it red, and the registry was restored byte-for-byte.
exit 0

$ shasum -a 256 docs/test-campaign/inventory.json
9215d5be401c61b55d3a85ef697279dc4f99dd389e6ce0226b232a7bdb225885  docs/test-campaign/inventory.json
```

*Restored byte-for-byte* is a measurement here, not the tool's claim about itself: the SHA-256 is
identical before the first run and after the last, and `git diff` is empty.

### The control passed and left half the gate exactly where it found it

The census has **two** exact passes at requirement level. `--seed-strengthen` sets
`effect: "packet-filter"` and pops `provider` — which *is* the `uncensused` predicate. So it fires
`uncensused` and only `uncensused`, whatever the requirement's starting class. Decomposed per pass
on this registry:

| seeded mutation | `unclassed` findings | `uncensused` findings |
|---|---|---|
| REQ-017 → `packet-filter`, provider dropped | 0 | 1 |
| REQ-001 → `packet-filter`, provider dropped | 0 | 1 |

Running it "in both directions" covers one predicate twice. After it printed *the gate bites*
twice, `unclassed` was still a pass reporting `examined=45 findings=0` with nothing having watched
it go red — **the position the control exists to end, surviving the control.** Recorded as DEF-030,
against the campaign's instrument rather than against Proctor. It is the third instrument in three
waves to read zero for a structural reason, after the blind vocabulary and after
`capture_with_manifest.py` writing rows `capture-lineage.py` could not parse.

`scripts/campaign/seed_unclass.py` is the missing direction. It strengthens the *specification*
rather than the census record — removes a requirement's `effect` field and requires `unclassed` to
flag it — and it refuses two ways, because a control that cannot refuse is the thing being guarded
against:

```
$ python3 scripts/campaign/seed_unclass.py docs/test-campaign REQ-017
seed-unclass REQ-017: before=clear after=red (unclassed examined=45 findings=1)
  REQ-017 names subprocess and declares no `effect` — run the census, or record "effect": "none"
registry restored byte-for-byte: True (sha256 9215d5be401c61b5…)
The pass bites: removing the effect class turned unclassed red.
exit 0

$ python3 scripts/campaign/seed_unclass.py docs/test-campaign REQ-011
REFUSING: REQ-011's text names no effect the vocabulary matches, so removing its `effect` field correctly produces no finding. Scoring that as a red would pass this control on a tautology. Pick a requirement whose text names an external effect.
exit 2
```

It sits in this repo rather than as a patch to `vacuity-check.py`, which lives in a plugin cache
this repo does not own — a fix there is reverted by the next plugin update with nothing saying so.
DEF-030 stays `open` so it reaches whoever owns the skill.

## ProctorAgent, sampled

Every mutation site ever scored in this repo was in `ProctorCore`. `ProctorAgent` holds the
session, the queue, the overlay, the actuation backend and every guest adapter, and no mutant had
ever been generated in it.

**24 mutants over a pool of 3,189 sites across all 84 files, seed 20260821. 3,165 sites unrun.**
That is 0.75% of the package, and every number below is stated against that denominator.

| | count |
|---|---|
| sites in pool | 3,189 |
| selected and run | 24 |
| **SURVIVED** | **19** |
| scored killed | 5 |
| unbuildable | 0 |
| trustworthy kills | **3** |

**Two of the five kills are not trustworthy, and the runner cannot tell.** `SessionActivate.swift:166`
and `UnlockBroker.swift:110` both scored at exactly 600.0s, which is the timeout, and `run_suite`
scores a timeout as killed. Load average was 22.9 when the run started and 271.4 when it finished.
So the honest figure is **3 kills of 22 scored — a survival rate of 86.4%**, against `ProctorCore`'s
50%. That is DEF-033, and it is DEF-018's shape one package over.

Two things keep this readable rather than merely alarming. **Survivors are trustworthy in both
directions**: starvation can turn a survivor into a false kill, but it cannot turn a kill into a
false survivor, so all 19 stand whatever the load did. And **no kill below 600s is timeout-scored**:
the three trustworthy kills ran 23.6s, 37.8s and 32.4s against a 600s bound, so they are real test
failures rather than starved runs. Per-mutant seconds are in `evidence/mutation-agent.json`.

One of the two untrustworthy kills should not have been a mutant at all. `mutate_swift.py`'s
integer-literal operator matched the `0` in a closure shorthand parameter and rewrote
`bind(fd, $0, size)` to `bind(fd, $1, size)`, which cannot compile. It should have scored
`unbuildable`; under load the build did not finish inside the timeout, so it scored a kill instead,
and the summary's `unbuildable: 0` is wrong for a reason the tool cannot see. DEF-032.

### The nineteen survivors, and what happened to each

Five are killed by new tests in `Tests/ProctorAgentTests/MutationSurvivorTests.swift`. One is
equivalent. Thirteen are recorded uncovered. **`equivalent` and `uncovered-by-lane` are different
claims and are kept apart**, because recording a coverage hole as a mathematical impossibility is
how a suite stops looking for the test.

| # | site | mutation | disposition |
|---|---|---|---|
| 21 | `AX/KeyCodes.swift:18` | `"n": 45` → `46` | **killed** — CASE-0075 |
| 2 | `RunIdentity.swift:30` | `prefix(12)` → `13` | **killed** — CASE-0076 |
| 18 | `Session/PixelCompare.swift:38` | `by: 4` → `by: 5` | **killed** — CASE-0077 |
| 17 | `Unlock/UnlockBroker.swift:51` | `+= 1` → `+= 2` | **killed** — CASE-0078 |
| 14 | `Overlay/RunHUDContentView.swift:830` | `ms < 1000` → `<=` | **killed** — CASE-0079 |
| 13 | `Session/SessionMaestro.swift:242` | `$0.key < $1.key` → `<=` | **equivalent** |
| 1 | `AX/AXEngineImpl.swift:33` | `\|\|` → `&&` | uncovered-by-lane |
| 4 | `Overlay/TakeoverOverlay.swift:771` | `+ 44` → `+ 45` | uncovered-by-lane |
| 9 | `Capture/MarkRenderer.swift:141` | `scale * 2` → `* 3` | uncovered-by-lane |
| 12 | `Overlay/RunHUDPanel.swift:653` | `canBecomeMain false` → `true` | uncovered-by-lane |
| 16 | `AX/CGWindowCorrelation.swift:59` | `matches[0]` → `matches[1]` | uncovered-by-lane |
| 20 | `Overlay/TakeoverOverlay.swift:363` | `==` → `!=` | uncovered-by-lane |
| 3 | `Dispatch.swift:381` | `includeTiles` default `false` → `true` | no seam |
| 11 | `Dispatch.swift:394` | `presentation` default `true` → `false` | no seam |
| 5 | `Session/Session.swift:92` | `flowsLoaded false` → `true` | no seam |
| 8 | `Session/SessionFlow.swift:493` | `timeoutMs: 3000` → `3001` | no seam |
| 10 | `Session/SessionKill.swift:26` | `==` → `!=` | no seam |
| 19 | `Overlay/RunHUDContentView.swift:97` | `hex(17, …)` → `hex(18, …)` | no seam |
| 22 | `Session/AuditKeyStore.swift:47` | `isDirectory: false` → `true` | no seam |

**The one equivalent mutant is argued, not asserted.** `SessionMaestro.swift:242` sorts
`score.undersampled` by key. That value is `[Int: Int]` (`StabilityCaptures.swift:200`), so its keys
are unique by construction, no two elements ever compare equal, and `<` and `<=` produce the same
total order. No test can distinguish them. It joins `RunHUDGate.onSegment`'s `<=` boundary on the
record rather than being chased.

**`uncovered-by-lane` means the site needs a window server, a live event tap or a real workspace**
that this headless lane does not have — AppKit view geometry, `NSPanel` focus behaviour,
`CGWindowListCopyWindowInfo` records, `NSWorkspace.shared.runningApplications`, a `CGEvent` tap
being disabled by the system. **`no seam` is the weaker and more honest label**: the behaviour is
headless-testable in principle, but reaching it needs a fake the suite does not have today — a
dispatcher drive that observes argument defaults, a `Session` over a populated on-disk flow store, a
capture engine that records the `timeoutMs` it was handed, a design-token drift test binding the HUD
palette to the generated tokens, and a `publicKeyURL` that is `private` with no accessor. Six of the
thirteen are that, and they are a backlog rather than a limit.

### The five that are now watched

Each was armed by re-applying its mutant after the test was written and watching the named test go
red — all five together, 8 issues, exit 1, then reverted. `evidence/mutation-arming.txt`.

The oracle is deliberately never the constant in the source. `KeyCodes` is checked against Carbon's
own `kVK_ANSI_*`; the RGBA stride against the identity that two uniform images differing by `delta`
per channel have a mean absolute channel difference of exactly `delta / 255` whatever the pixel
count; the run id's alphabet against the UUID it is drawn from. Asserting a value the test itself
supplied is how DEF-019 shipped, and it is not repeated here.

Two are worth reading twice. `KeyCodes` had **nothing checking the table against anything**, so with
`"n": 46` the letters `n` and `m` shared a code — `proctor_act` typing "n" presses M — and 1,818
tests stayed green. And `PixelCompare.meanDifference` backs the `regionMatches` assertion, so it is
the instrument every caller's tolerance is measured in; at stride 5 it reads misaligned channels and
visits four fifths of the pixels, and every existing test compared images that were either identical
or wildly different, both of which survive a broken stride.

**This figure is not copied into `.warrant/suite-health.json`.** `mutation_measured: false` there is
correct and is not stale: it means warrant's own assay has not run, and a value copied into a
generated file is a second source that drifts.

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

## The instruments, measured (PRO-0091)

Seven findings about the tools that measure this project rather than about the product, closed as
one item because they share a failure mode: an instrument reporting a clean result over a
population it never examined.

**The gate printed twelve and meant eighteen.** `campaign.py check` capped its list of unwitnessed
requirements at twelve and said nothing about the cut. Wave 11 was scoped off that printed list
against a real set of eighteen, and ten requirements were named by no item — the campaign's own
first failure mode, covering a subset and reporting it as the whole, arriving through the gate
rather than through a surface map. Raising the cap is not the remedy, because the next set
outgrows the next cap. Every capped list now carries its own denominator: `… (showing 12 of 18)`
when it truncates and `(showing 3 of 3)` when it does not, so a reader never has to work out
whether anything was cut. Measured on a fixture built to the shape of the loss, with the 0.9.3
bytes read out of git and run rather than described.

**A rung that was not on the ladder, decided rather than relabelled.** CASE-0102..0105 recorded
`oracle: "static-analysis"`, so all four counted `unrated` — the bucket whose own comment says it
counts never as adequate — while being real armed instruments that exit 1 on a one-line mutation
and 0 on the file as written. The fork went to grok-4.6 at effort xhigh, which ran its own
three-family panel; fable-5 and gemini-3.7-flash-high agreed with the options presented in swapped
order, and the codex lane failed to initialise and was recorded as a lane failure rather than
counted as agreement. The answer was neither option: `source-analysis` is a rung **parallel** to
the ladder rather than a position on it, because the ladder is one axis — what a case checked
against the running product — and a reader of source text is off that axis rather than ranked on
it. Re-expressing the four against the built product is not available, since a hardcoded
`Text("Open log")` and a `Text(Copy.openLog)` render identically. The gate now reads
`Off-ladder: source-analysis 4` where it read `unrated 4`. Reclassifying them to `structural` was
the ruled-out route and was not taken.

**REQ-024 is `vacuous`, not `none`.** Its declared `subprocess` effect named a boundary the
browser-routing path does not cross: `BrowserTarget` is pure, `Session.browserHandoff` returns a
disclosure that six call sites attach to a reply, and `ToolLocator.locate` decides availability
with a stat. The class is kept and the evidence recorded `vacuous`, because the requirement's text
does name a dispatch and the honest finding is that nothing performs it. Softening the class to
`none` would have made the census green by denying the claim rather than by recording what was
found. External effects now read `witnessed=12 vacuous=1`.

**Three instruments repaired and guarded.** The census control arms both of the gate's
requirement-level passes, each watched from clear to red in one session against a fixture — and
that fixture is needed because `uncensused` is already red on the real registry, which the shipped
control does not refuse, recorded as DEF-075. `mutate_swift.py`'s integer operator no longer
matches closure shorthand, so a sampled slot stops going to an edit the compiler must reject.
CASE-0074's starting load reads 22.92, parsed out of its evidence file rather than copied into the
note, so the two cannot drift again silently.

**The hand-merge is a script now.** `scripts/campaign/merge_registry.py` sweeps the union of both
documents' keys, asserts id uniqueness per key, refuses a real conflict rather than resolving it to
one side, and carries a `--verify` mode that reads a merge somebody else performed and names every
dropped row. Its fixture is a reproduction of the loss it exists to prevent: a five-key registry
hand-merged on `defect` and `requirement` with ours as the base, which exits 1 naming
`flow/FLOW-010`.

Fifteen checks in `scripts/campaign/test_instruments.py`, run by
`Tests/ProctorCoreTests/CampaignInstrumentTests.swift` so `./scripts/test.sh` owns the verdict, and
each of them watched red on a one-line mutation and green again in the same session. The wrapper
asserts the count of checks as well as the exit code, because `0 passed, 0 failed` exits 0 and is
the shape of the thing this whole item is about. Suite: 1,832 tests in 217 suites, up from 1,829 in
216.

`campaign.py` itself is not in this repo. It is fixed in `~/Dev/fledgeling-plugins` as
test-campaign 0.9.4 and mirrored into the active plugin cache; both copies read sha256
`a7d97822…`. Neither is pushed.
