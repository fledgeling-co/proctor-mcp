# PRO-0019: A foreground-only run is obvious before it takes the machine

**ID:** PRO-0019
**Status:** In Review
**Created:** 2026-08-14
**Last updated:** 2026-08-14
**Brief:** `docs/features-to-triage/20-foreground-run-is-obvious.md`
**Plan:** `docs/plans/plan-PRO-0019.md`

## What it is

Disclosure, not policy. Make "this run is going to interrupt you" legible
**before** it happens, unmissable **while** it does, and a fact about the suite
**afterwards**. Which steps are synthetic does not change; no step gains an
accessibility route; nothing is refused that is not refused today.

`Session.syntheticKinds` and `Session.isSynthetic` already classify a step. The
gap is reach and timing.

## The decisions PRO-0018 is waiting on

**D1 — The reusable answer is `ForegroundDemand`, in
`Sources/ProctorCore/ForegroundDemand.swift`.** A value computed from a batch's
step kinds and its `foreground` flag before anything runs, carrying:

| field | meaning |
|---|---|
| `certainSteps` | steps that can only travel the event stream (`syntheticKinds`) |
| `conditionalSteps` | steps that *may* fall to it — `type` into a field the AX plane cannot write, `scroll` with no `AXScrollToVisible` |
| `raises` | contains a `raise`, which moves the ground under everybody else's events |
| `requestedForeground` | the batch asked for `foreground: true` outright |
| `totalSteps` | denominator for the disclosure |

Two predicates, and the difference between them is the whole honesty problem:

- `takesForeground` — `certainSteps > 0 || raises || requestedForeground`. This
  is exactly the predicate `LaneDemand.forBatch` already applies, so
  `LaneDemand` is re-expressed in terms of it and there is one answer to the
  question rather than two. **Scheduling behaviour is unchanged.**
- `mayTakeForeground` — `takesForeground || conditionalSteps > 0`. Disclosure
  only. It never reaches the scheduler, because a `type` batch that takes the
  global lane on the chance it falls back would serialise runs that never touch
  the foreground.

PRO-0018 reads `takesForeground` to decide whether a run is a candidate for
holding, and `mayTakeForeground` if it wants to be cautious. It does not
recompute either.

**D2 — A batch declares its foreground content up front, at `runBegan`, not at
the first synthetic step.** The brief calls this "more useful and slightly less
honest, since a batch can end before it gets there." The honesty objection is
answered by the wording rather than by the timing: the up-front line states what
the batch **contains**, never what will happen. "2 of 6 steps need Acme Console
in front" is true of the batch whether or not step 2 is ever reached. The
present-tense statement — "Synthetic event — Acme Console must stay in front" —
is unchanged and remains the only thing that claims something is happening now.

Corollary: the up-front count is a **floor**, because `type` and `scroll` decide
their plane at the element. That is why the count is conditional-aware up front
and **measured** afterwards, from `plane == .syntheticEvent` on the step results,
rather than predicted twice.

## Acceptance clauses

**A1 — one value answers the question.** `ForegroundDemand.forBatch(kinds:
synthetic:conditional:foreground:)` returns the counts above; `takesForeground`
matches `LaneDemand.forBatch`'s global-lane predicate for every combination of
kinds and flags; `LaneDemand.forBatch` is implemented through it.

**A2 — the panel says it before the run starts, and the number never claims more
certainty than it has.** `RunHUDEvent.runBegan` carries the demand. Three
phrasings, chosen by the demand:

| demand | row |
|---|---|
| certain > 0, conditional = 0 | "N of M steps need <app> in front" |
| certain > 0, conditional > 0 | "At least N of M steps need <app> in front" |
| certain = 0, conditional > 0 | "Up to N of M steps may need <app> in front" |
| neither | absent, exactly as today |

**And it revises upward when a conditional step actually falls back.**
`stepSettled` carries the plane it travelled; a step that was not certain and
reported `syntheticEvent` increments the count on the row. The up-front number
is a floor that converges on the measured one, rather than a prediction that
ends up contradicting A6's measurement. (This clause is the out-of-family spec
gate's finding: an unqualified "N of M" stated up front is prophecy wearing
content's clothes when `type` and `scroll` can add to N at runtime.)

**A3 — the notice survives non-synthetic steps.** A batch of `[press, click]`
keeps the up-front line during `press` and swaps to the present-tense exception
line while `click` is in flight, then returns to the up-front line. The panel
never goes quiet about a batch that is going to take the machine.

**A4 — the mouse gate is driven by the step in flight, not by the text.**
`RunHUDPanel` currently sets `panel.ignoresMouseEvents = model.exception != nil`.
A2 makes `exception` non-nil for the whole of any batch containing a synthetic
step, which would leave Pause and Stop unclickable for that entire batch. A new
`RunHUDModel.syntheticInFlight` carries the gate instead, and is a **pure
extraction of today's predicate**: it is set true on `stepApproaching`/
`stepActing` of a synthetic step and false on `stepApproaching`/`stepActing` of
one that is not, plus on refusal, failure and run end — the identical window
`exception != nil` covers at HEAD, so it opens before the first `CGEventPost`
and stays open past a multi-event `dragPath`. The layout keeps reading
`exception != nil`, because that is genuinely about whether a row is drawn.

**A5 — the menu bar states it while it is happening.** `proctor_recent_activity`
gains a `foreground` block (`active`, `certain`, `conditional`, `total`, `app`).
`MenuBarContent`'s activity line states it in words, and the menu-bar glyph
changes while `active` is true, so the fact does not depend on opening the menu
or on which display the panel landed on.

**A6 — the result says how much of the run needed the front.** `ActResult` gains
`foreground: ForegroundReport` — `declaredCertain`, `declaredConditional`,
`measured` (steps whose `plane` was `syntheticEvent`), `total`,
`ranInForeground`. Flow replay reports the same block, replacing its existing
free-text `note`, so "this suite cannot run unattended" is a field rather than a
sentence to parse.

**A7 — nothing new is refused.** `Session.refusal(for:foreground:)` is untouched;
lane demand for every batch is byte-identical to HEAD.

## Assumptions recorded in place of questions

- **A-i. Disclosure counts steps, not time.** A batch of 1 synthetic step out of
  40 could hold the machine longer than 20 short ones. Steps are what is known
  before the run; duration is not. Stated as a count, never as a duration.
- **A-ii. `conditional` is `[type, scroll]`, named on `Session` beside
  `syntheticKinds`.** Plane policy stays in the agent; Core takes the set as a
  parameter, the way `LaneDemand.forBatch` already takes `synthetic`.
- **A-iii. The up-front notice reuses the single exception row.** The binding
  design says the synthetic exception is stated in words, once. One row, one
  size, one wording function with three phrasings — no second row, no chip, no
  colour beyond the amber that row already uses.
- **A-iv. The menu-bar glyph is one added case at the head of `menuIcon`'s
  switch.** PRO-0021 rewrites that property; keeping the change to a single
  leading case makes the merge mechanical.
- **A-v. Stability sweeps disclose per pass, not per sweep.** A sweep calls
  `runSteps` once per repeat and the panel is per run; the report block is added
  to `act` and flow replay only. `proctor_stability` already reports its own
  determinism shape and gains nothing here.

## Out of scope

- **Refusing or holding a foreground run — PRO-0018.** The brief asks whether
  this should be able to refuse rather than only warn. It should not be answered
  twice: 0019 computes and discloses, 0018 acts on what 0019 computed. The
  primitive it needs is D1.
- Changing which steps are synthetic, or adding an accessibility route to a step
  that has none.
- The HUD's design. Settled and binding (`mocks/run-hud.html`).

## What a `swift test` cannot witness here

The panel drawing the row, the menu-bar glyph changing, and the menu line
rendering are window-server surfaces. The model, the wording, the demand
arithmetic, the mouse-gate flag and the wire blocks are all values and are
tested; the drawing of them is code-complete and needs a human glance.

## Known limits, stated rather than hidden

- **A `type` or `scroll` that falls back cannot be announced in the present
  tense.** The actuator reports its plane only when `perform` returns, so
  nothing before that moment knows the step went to the event stream. The row
  therefore says the batch *may* need the front, revises the count upward the
  moment the step settles, and the finished run reports it as measured. Making
  the present-tense line cover it would mean the actuator declaring its plane
  before it posts, which is a change to the actuation path and not to
  disclosure. Logged as child work.
- **The same gap applies to the panel's mouse gate**, unchanged from HEAD: it is
  driven by the step's kind, so a fallback `scroll` posts a wheel event that the
  panel does not step aside for. Narrow — a wheel event landing on the panel
  scrolls nothing, and a fallback `type` posts keyboard events, which never
  reach a panel that is never key. Not a regression and not widened here.
- **The menu bar samples.** The UI polls every two seconds, so a synthetic step
  shorter than one poll can begin and end unseen there. The panel is the
  instantaneous surface; the menu bar is the one that does not depend on which
  display the panel landed on.

## Gates

- **Spec review, out of family, `grok-4.6 --effort xhigh`, 2026-08-14.** Held (1),
  (3) and (4); called the unqualified up-front count a real defect, and confirmed
  the `takesForeground` refactor equivalent and the mouse-gate split safe provided
  the flag opens before the post and stays open past a multi-event gesture. Both
  findings are folded into A2 and A4 above.
- **Completeness critic, out of family, `grok-4.6 --effort xhigh`, 2026-08-14.**
  Called it incomplete and was right three times over, none of which the build
  or the suite would have caught:
  1. **The live menu-bar state was a single slot.** Two runs on different
     applications are two app lanes and genuinely overlap, so a harmless run
     ending would wipe the state of a foreground run still posting events and
     the menu bar would report the machine free while it was being taken. Now
     keyed by a run token and folded across every run in flight.
  2. **The hedge never came off.** "At least N of M" stayed up for the whole run
     even after every conditional step had run and resolved the doubt. The
     demand now carries its conditional kinds so the reducer can tell when one
     has settled, and the row drops to an exact count — or disappears, when
     nothing turned out to need the front.
  3. **The upward revision double-counted**, which the cap had been hiding. A
     certain step reporting `syntheticEvent` on its way out was counted a second
     time; only a conditional step may move the number. Caught by an existing
     test the moment the cap was loosened.
  Its two remaining points are answered rather than fixed: the fallback step's
  present tense is a known limit above, and the conditional-vs-lane asymmetry is
  decision D1.
