# PRO-0068: The menu bar, and the complete command surface

**ID:** PRO-0068 · **Status:** Merged · **Created:** 2026-08-20
**Brief:** `docs/features-to-triage/62-menu-bar-and-the-command-surface.md`
**Branch:** `ai/pro-0068` off `ai/wave-9` · **Depends on:** PRO-0067
**Mock:** `#mac/menubar/idle|running|foreground|down`, `#mac/menus/all`

## The problem

Two gaps, and the second is the serious one.

The extras menu has three states in the mock and one in the app — the missing one is the
foreground disclosure, the only moment a person can act on the information that a run is
*about to* take the machine.

**And there is no menu bar.** `ProctorUIApp` declares two windows, a `MenuBarExtra`, and a
`.commands` block with one item. The HIG rule is explicit: every toolbar command also exists
as a menu command, because people hide and customise toolbars. Today Pause and Stop are
reachable from a floating panel and a menu-bar extra and from no menu at all — so somebody who
has hidden the panel and does not know about the extras item has **no path to the kill
switch**.

## Acceptance criteria

1. **A1 — the clause this item exists for.** Every command reachable from the run panel or the
   extras menu is also in the menu bar. A test enumerates both and fails on any command present
   in one and absent from the other.
2. **A2** — Pause and Stop are present in all four states, disabled rather than absent where
   they do not apply.
3. **A3** — the foreground disclosure reads `ForegroundDemand` rather than re-deriving it, and
   is stated as a floor. Three answers to one question is how they drift.
4. **A4** — shortcuts are unique across the whole surface.
5. **A5** — the panel switch is disabled with its reason stated when the agent was launched
   with `PROCTOR_HUD` off, rather than left as a greyed item nobody can explain.

## Decisions taken at triage

- **`CommandSurface` in Core is the single table** for both the menu bar and the extras menu.
  `RunHUDMenuBar` already owns part of this and has tests; extend it rather than adding a
  parallel table.
- **No Settings window.** The platform grammar puts Settings behind ⌘, and this app keeps the
  switches in the status window instead. Defensible for a background agent, and recorded here
  as a deliberate deviation rather than an oversight.

## Out of scope

Which character state shows when is this item's; the asset set is PRO-0069's.

## Verification

`CommandSurfaceTests` is 8 tests; suite 1,563 in 181 suites.

- **A1** — `commandsMissingFromMenuBar` is asserted empty, and the failure message names the
  titles. Pause, Resume and Stop are additionally asserted present on all three surfaces
  individually, because the aggregate clause would still pass if the kill switch were the one
  command nobody had put anywhere.
- **A2** — enablement and presence are separate questions. Commands disabled with nothing
  running keep their surfaces, and Pause/Stop flip on `hasLiveRun`.
- **A4** — key equivalents are unique across the whole surface, with the clashing set printed.
- **A5** — Show Run Panel requires `panelEnabled`; Hide stays available, because hiding is
  always reversible within a launch.

The menu bar now carries 20 commands across four menus. It carried one.

### The wording was not mine to change

`CommandSurface` says **Pause Run**, **Resume Run** and **Stop Run** rather than the shorter
labels the mock drew. `ProctorUIApp` records why, and it is a real rule rather than a style
preference: the queue has its own pause/resume pair, the two pairs never sit together, and
calling both "pause" is how somebody stops the wrong thing. The shipped wording is kept and
the reason is now in `CommandSurface` where the next person to shorten it will read it.

**A3 is carried, not claimed.** The menu reads the same `ForegroundDemand` value the panel and
the extras menu read, so there is one answer rather than three — but asserting the *rendered*
menu shows it needs the harness.

## A second flake found and fixed, 2026-08-20

The `tests` gate went red one turn after this item merged, on
`two sessions driving the same app take turns, and both finish` — roughly one run
in five under a loaded machine.

**The scheduler's injected clock did not govern its ceiling.** `RunScheduler` takes
`now:` and its own comment promises "a test's clock is its own", but `deadlineTask`
slept on `Task.sleep` and never consulted `now`. So a wiring test injecting
`now: { 0 }` — saying, explicitly, that time does not pass — still had a real
five-second timer racing the work it was measuring. On an idle machine eight steps
finish inside five seconds; under a parallel suite they do not, and the queue
refused a run that was about to succeed.

An injected clock that is not honoured is worse than no injection, because the test
reads as deterministic and is not.

`sleep:` is now injected alongside `now:`, defaulting to the real `Task.sleep`.
`RunScheduler.stoppedClock` pairs a stopped clock with a sleeper that suspends until
cancellation, which is safe because the deadline task is cancelled on all three paths
out of the queue. The wiring harness uses it.

**A correction to my own reasoning while fixing it.** I claimed no test asserted the
ceiling firing and started to add one; the compiler rejected it as a duplicate,
because `a call still waiting when the ceiling fires is told the machine was busy`
already existed. It builds its own scheduler at `waitLimit: 0.05` with the default
sleeper, so it still fires in 50ms and the ceiling stays proven. My addition was
removed. The grep that missed it was too narrow, and the compiler caught what the
grep did not.

Six consecutive full runs clean afterwards.
