# PRO-0025: Prefer the background, and draw the pointer in the target's plane

**ID:** PRO-0025
**Status:** Merged
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/26-prefer-background-and-pointer-in-plane.md`
**Plan:** `docs/plans/plan-PRO-0025.md`
**Blocks:** PRO-0026 (foreground takeover overlay) — see "What PRO-0026 inherits".

## What it is

Two halves of one complaint. Proctor takes the foreground more often than it
needs to, and the pointer it draws while working in the background floats above
the app somebody is actually using — a picture that says Proctor is clicking
your foreground window when it is driving something else entirely.

Nothing here makes a step work that genuinely cannot travel the accessibility
plane. A drag, a hover and a canvas click have no accessibility expression and
keep refusing exactly as they do today.

## The measurement that decides the pointer half

The brief says the restacking question is to be answered by trying it, not by
reasoning. It was tried, on this machine, macOS 26.6, 2026-08-15, with two
scratch probes against real other-process windows (Chrome, Ghostty) on the main
display. Three conditions, each verified by capturing the screen and sampling
the pixel at the drawn point rather than by asking the window server what it
believed:

| # | Condition | Pointer pixel | Reading |
|---|---|---|---|
| M3 | Panel at `.screenSaver` (today), target window fully covered by another app | **visible** | the misrepresentation, reproduced |
| M2 | Panel at `.normal` + `order(.above, relativeTo: <foreign CGWindowID>)`, same covered target | **absent** — the covering window's own pixels | the pointer is genuinely occluded |
| M1 | Same restack, target window frontmost | **visible** | it still draws when it should |

Ordering held: the panel sat at window-list index 28 with the target at 29 and
the app above it at 27 — sandwiched between two windows of another process — and
was still immediately above the target after three seconds of idling.

So **`NSWindow.order(_:relativeTo:)` against another process's `CGWindowID`
works**, provided the panel is at a level that shares a band with the target
(`.normal`). At `.screenSaver` the call is accepted and inert — level dominates,
exactly as the brief warned — which is why M3 and the un-restacked control are
indistinguishable. **The in-plane pointer is what ships.** The dimmed fallback
the brief authorises is kept, but demoted to the one case that cannot be
resolved: a target window with no correlated `CGWindowID`.

Not machine-verifiable here, and stated as unverified rather than claimed:
behaviour across a Space switch, across a full-screen target's own Space, and
under a target minimised mid-run. Assumption A2 below is what those degrade to.

## Acceptance clauses

**The background half**

- **A1 — An inert `foreground: true` no longer takes the foreground.** A batch
  that asked for the front but contains no step that could ever use it (no
  synthetic kind, no `type`/`scroll` that might fall back, no `raise`) does not
  take the exclusive global lane, does not arm the contention watch, and says
  nothing about bringing an app forward. Nothing in the batch ever calls
  `activate`, so the promise was never kept in the first place.
- **A2 — A `foreground: true` that *could* be used is unchanged.** A batch with a
  certain synthetic step, or a `type`/`scroll` that might fall back, keeps
  today's global lane, today's disclosure and today's contention arming.
  `LaneDemand.forBatch` learns the conditional set so it can tell the two apart;
  it does not grow a second opinion about the foreground.
- **A3 — The result says the request was inert.** `ForegroundReport` carries it
  and its prose note states it once, so a caller passing `foreground: true` out
  of habit is told rather than silently corrected.
- **A4 — `type` tries a second accessibility route before falling back.** A field
  that refuses an `AXValue` write — or *accepts* one that does not take — but
  accepts a full-range `AXSelectedText` write is typed into on the accessibility
  plane, in the background, and reports `.accessibility`.
- **A5 — `scroll` tries the enclosing scroll area before falling back.** When the
  element is not itself a scroll bar and offers no scroll action, the nearest
  ancestor `AXScrollArea`'s scroll bar takes the value write, on the
  accessibility plane.
- **A5b — A route that does not take is not a route.** Every new route reads its
  own effect back and, if nothing changed, hands on to the next route rather
  than reporting a success that did not happen.
- **A6 — Every step says which route it took.** `StepResult.route` names it —
  `valueWrite`, `selectedText`, `scrollBar`, `scrollAction`, `action`,
  `eventStream`, `appleEvent`, `declared` — so "it stayed on the accessibility
  plane by a different route" is visible rather than inferred from a plane that
  cannot distinguish them.

**The pointer half**

- **A7 — The pointer is drawn in the target window's z-order.** The overlay panel
  for the screen the pointer is on is restacked immediately above the target
  window's `CGWindowID` before each drawing, at a level that lets that ordering
  hold, so a window stacked above the target covers the pointer.
- **A7b — The placement is verified, not assumed.** After restacking, the window
  list is read back: if the panel is not actually above the target, the pointer
  demotes itself to A9's dimmed fallback for that step. An undocumented ordering
  that stops working on some future macOS degrades to a marked pointer rather
  than to a pointer quietly lying about its plane.
- **A8 — A target that is not on screen gets no pointer.** Minimised, on another
  Space, or absent from the on-screen window list: nothing is drawn, rather than
  a pointer floating over unrelated windows on the Space somebody is looking at.
- **A9 — An unresolvable target falls back honestly.** No correlated
  `CGWindowID` means the plane cannot be established, so the pointer is drawn
  visibly dimmed at the old floating level and never claims to be in the
  target's plane.
- **A10 — `PROCTOR_CURSOR=0` still turns the pointer off entirely**, including
  every window-list read this feature adds: a disabled overlay costs nothing.
- **A11 — One panel per display.** The measurement in `CursorOverlay`'s header
  stands untouched; nothing here builds a union-sized panel.

## Design

### Background half

**`ForegroundDemand` gains a consumer test, and keeps being the single answer.**

```
mightPost       = certainSteps > 0 || (requestedForeground && conditionalSteps > 0)
takesForeground = mightPost || raises
requestWasInert = requestedForeground && conditionalSteps == 0 && certainSteps == 0 && !raises
```

`mayTakeForeground` is unchanged. This reads as "might post, or moves the ground
under somebody else's events", which is what the lane was always for. It is not
a loosening: a `type` or `scroll` step with `foreground: false` **cannot** reach
the event stream — the actuator refuses that fallback outright rather than
activating (`Actuator.type`, `Actuator.scroll`), so `requestedForeground` is a
precondition of posting and gating on it costs no coverage. And `takesForeground`
still counts only what is knowable now: a batch of `press` and `setValue` steps
cannot turn out to need the front however it is flagged.

`LaneDemand.forBatch` today passes `conditional: []`, which was harmless while
`requestedForeground` alone forced the lane. Under the new predicate that empty
set would strip the global lane from a foreground `type` batch — a real
regression against a deliberate decision recorded in `RunQueue.swift`. So the
agent passes `Session.conditionalKinds` there **in the same change**, and the two
callers of the predicate see the same batch.

`notice()` returns nil for an inert request: accessibility is the rule and is
never announced, and there is now nothing exceptional to announce.

**Two more accessibility routes, tried before the fallback that costs the front.**

`type`, in order:

1. `AXValue` write, **then read the value back**. A web input or a custom text
   view commonly accepts the write and ignores it; today that is reported as a
   background success that did nothing, and it is also what would stop route 2
   from ever being reached on exactly the fields that need it.
2. Read `AXSelectedTextRange`, select the whole value, write `AXSelectedText`,
   read back. The range write is a precondition, not an optimisation:
   `AXSelectedText` with no selection *inserts at the caret*, which is a
   different outcome from the replace `type` has always meant, so a failed range
   write drops the route rather than quietly changing what the step does. On any
   failure after the range write, the original selection is restored — a field
   left select-all'd would be emptied by the first keystroke of the fallback.
3. The existing refusal (when `foreground` is false) or the synthetic post.

`scroll`, in order: the element's own scroll-bar value write → its
scroll-by-page action → **new:** walk up to the nearest ancestor `AXScrollArea`
(bounded to 12 parents), read its `AXVerticalScrollBar` / `AXHorizontalScrollBar`
— both are element references — and write `AXValue` **on that bar element**,
reading it back, using the same `current + delta/100` clamped-to-0…1 mapping the
existing scroll-bar branch uses → the existing refusal or the synthetic wheel
event. `AXScrollToVisible` is deliberately not used: it scrolls to an element,
so it cannot express the delta the caller gave.

Two knowingly-kept limitations. The `delta/100` mapping is crude — it is a
fraction of the document, not lines — but it is the mapping already shipped on
the scroll-bar branch, and re-deriving it here would change behaviour that is
not what this item is about. And the page action is still tried before the new
bar write, so an element that offers `AXScrollDownByPage` scrolls by a page
rather than by the delta; reordering them would change what already-working
scrolls do. Both are recorded as child work rather than smuggled in.

**Route reporting.** `Actuator.perform` returns an `Actuation { plane, route }`
rather than a bare plane; `AXEngine.perform` and its one fake follow.
`ActuationPlane` is untouched, because `ForegroundReport` counts
`.syntheticEvent` on it and a finer plane would change what "this run took the
foreground" measures.

### Pointer half

**A decision function in Core, so the part that can be tested is.**

```swift
enum PointerPlane { case inPlane(above: UInt32), floatingDimmed, hidden }
PointerPlanePolicy.decide(targetWindowID: UInt32?, targetIsOnScreen: Bool) -> PointerPlane
PointerPlanePolicy.held(panel: UInt32, above target: UInt32, in order: [UInt32]) -> Bool
```

`hidden` when the target is not in the on-screen window list; `inPlane` when it
is and carries a `CGWindowID`; `floatingDimmed` when it is on screen but no id
could be correlated, **or when the restack was attempted and did not hold**.
`CursorOverlay` applies the decision: `inPlane` sets the active surface's level
to the in-band level and calls `order(.above, relativeTo: Int(id))`;
`floatingDimmed` restores the floating level and drops the pointer's opacity to
the dimmed constant; `hidden` takes it off screen. The window server does the
occluding — there is no software occlusion test here, because the compositor
already knows the answer and a second one would be a second thing to keep true.

**The restack is verified rather than trusted.** Ordering a panel relative to
another process's window number is not a documented capability; it is measured
behaviour on one OS version, and a pixel sample on macOS 26.6 is not a contract.
So the placement is read back from the window list immediately after: the panel
must appear ahead of the target. If it does not, the pointer demotes to
`floatingDimmed` for that step, which is exactly the honest fallback the brief
authorises, reached by measurement rather than by a static guess. A future macOS
that stops honouring the call therefore degrades to a marked pointer instead of
to a pointer that lies.

The target window travels with the step: `runSteps` already holds the
`WindowHandle`, so `showCursor(for:)` takes it and `CGWindowIndex.records(option:
.optionOnScreenOnly, pid:)` answers both on-screen-ness and the read-back. That
read is the instrument this repo already trusts; `WindowHandle.isMinimized` and
`isOnActiveSpace` are AX beliefs and are not used for it. It needs no Screen
Recording grant — only window *names* are gated on it, and nothing here reads a
name.

The restack happens on each drawing entry point (travel, click, drag) — one
window-list read per step, against the several AX round trips a step already
costs — not on a timer and never per animation frame. Between two steps the user
can reorder their windows and the pointer will be one step stale; a resident
window-order observer inside an agent that already holds Accessibility is not
worth that.

Unchanged: one panel per display, click-through, non-activating, never
`activate(_:)`, `.canJoinAllSpaces`, and every draw inside the
`ProctorCatchNSException` barrier PRO-0022 put there.

## Assumptions recorded in place of questions

- **A1 — Hide rather than dim when the target is off screen.** The alternative
  was a dimmed pointer on whatever Space the reader is looking at, which draws a
  pointer over windows it has nothing to do with — the exact misrepresentation
  this item removes. Hiding loses nothing: the HUD still says what is happening.
- **A2 — A Space switch or a full-screen target degrades to A8, not to a lie.** A
  `.normal`-level panel does not present on another Space, and the target is
  absent from the on-screen list in the cases that matter, so the pointer
  disappears rather than appearing in the wrong plane. This is reasoned from the
  window-band rules, not measured; if it turns out a full-screen target is
  reported on screen while the panel is not presented, the pointer is missing,
  which is the safe direction.
- **A3 — An inert `foreground: true` changes scheduling for habitual callers.**
  Their runs stop taking the exclusive global lane and stop serialising against
  everything else. That is the brief's stated intent, and A3 discloses it.
- **A4 — Route is a new optional field, not a new plane.** Adding cases to
  `ActuationPlane` would change what `ForegroundReport.measured` counts.
- **A5 — `type`'s second route must replace, not insert**, and must restore the
  selection it made if the route fails. Recorded above.
- **A5b — A read-back changes what a lying `AXValue` write reports.** A `type`
  whose write is accepted and ignored is reported as a success today; after this
  it tries the second route and, failing that, refuses or falls back. That is a
  deliberate behaviour change in the direction of honesty, and it is what makes
  A4 reach web inputs at all.
- **A6 — The HUD panel's level is untouched.** It is a supervision surface, not an
  annotation of a window, so it stays where it is. Only `CursorOverlay` moves.
- **A7 — Window-scoped captures are unaffected.** `proctor_capture` is scoped to
  the target window, so a panel stacked above that window does not enter its
  frame; the invariant in `CursorOverlay`'s header ("never appears in a frame")
  survives the level change. Not machine-witnessable from `swift test`.
- **A8 — The panel's other properties do not change**: click-through
  (`ignoresMouseEvents`), non-activating, `.canJoinAllSpaces`, `.stationary`,
  `.ignoresCycle`, `.fullScreenAuxiliary`, one per display. Only the level and
  the ordering move. The package floor stays macOS 14; nothing here uses an API
  newer than that.

## Progress

**Branch** `ai/pro-0025` · **worktree** `.worktrees/PRO-0025` · commits `aa81d5f`
(implementation) and `a383048` (critic fixes). Ready to merge; not merged, not
rebased, not pushed.

**Gate.** `swift build` clean (three pre-existing `ProctorUI` warnings, nothing
new in Core or Agent). `swift test`: **563 tests / 70 suites**, from 544 / 66 at
HEAD. Runtime smoke on a scratch socket (`PROCTOR_SOCKET=/tmp/pro25/agent.sock`,
the reader's installed agent untouched): the agent starts under the new code,
listens, and `proctor_doctor` answers `ready: true`, both grants, no blockers.

| Clause | Proved by |
|---|---|
| A1 inert request takes nothing | `raiseAndRequest`, `foregroundTakesTheMachine`, `inertForegroundRequestIsReported` |
| A2 a usable request is unchanged | `requestWithSomethingToSpendItOn`, `foregroundTakesTheMachine`, `liveForegroundRequestIsKept` |
| A3 the result says it was ignored | `inertRequestIsDisclosed`, `inertRequestIsNotAnnounced`, `inertForegroundRequestIsReported` (incl. the prose note) |
| A5b a route that did not take is not a route | `writesAreReadBack`, `movedIsMeasured` |
| A6 every step says its route | `routeReachesTheCaller`, `refusedStepHasNoRoute` |
| A7 in-plane placement | `inPlane` (the decision); the placement itself is measured, not tested — see below |
| A7b verified, not assumed | `heldIsStrict`, `heldFailsClosed` |
| A8 an off-screen target draws nothing | `offScreenDrawsNothing`, `planeFollowsTheWindowList` |
| A9 uncorrelated falls back honestly | `uncorrelatedIsDimmed`, `dimmedIsMarkingNotHiding` |
| A10 `PROCTOR_CURSOR=0` | `killSwitch` |
| A2/A1 agreement with the scheduler | `matchesTheLanePredicate`, over every kind pair × both flags |

**Code-complete and not machine-witnessable here.** `swift test` has no window
server and no live application, so none of these is proved by the suite: the
restack itself, the occlusion, the dimmed and dashed treatment, any panel
presenting, and the two new AX routes against real elements (`AXSelectedText`
into a text view, an enclosing scroll area's bar). The restack and the occlusion
**are** measured, by the two probes recorded above and reproduced in
`CursorOverlay`'s header; the rest is a code reading and is named as one.

A4 and A5 sit in that gap deliberately. The route *ladder* runs against real
`AXUIElement`s, and the only honest way to unit-test it would be a mock AX layer
that tests itself, so what is tested is the three rules with content —
`scrollFraction`, `moved`, `tookValue` — and the ordering is left as reviewed
code.

**Child work found.**

- **A pre-existing flaky test, not caused by this work.** `aHeldRunSaysSo`
  (`YieldWiringTests`) fails intermittently on `endedBy == "person"`, roughly one
  run in six under load. Verified on the **base commit** `cae5f80` in a separate
  worktree with this branch's code absent: 1 failure in 6. The event log already
  records this test as historically fragile. Left alone rather than hardened,
  because loosening somebody else's assertion is how a real defect gets buried.
- The two scroll limitations recorded above (`delta/100` as a fraction of the
  document, and the page action outranking the precise bar write).
- `type`'s synthetic fallback appends rather than replaces, where both
  accessibility routes replace. Pre-existing, and now reached strictly less often
  than before, but the two paths mean different things under one verb.

## What PRO-0026 inherits

PRO-0026 is a full-screen takeover overlay that holds the machine visibly, and
it lands in `Sources/ProctorAgent/Overlay/` beside this work. Three things it
must know:

1. **Do not reuse `PointerPlanePolicy`.** A takeover overlay is a claim on the
   whole machine, not an annotation of one window. It belongs above everything,
   at a high level, permanently — the opposite of what this item does to the
   pointer.
2. **`CursorOverlay`'s panels are now at a normal-band level while a run is
   drawing.** A takeover overlay at a high level will therefore cover the
   pointer. That is correct — during a takeover the pointer is not the thing
   being said — but it is a change from what PRO-0026 would have found before.
3. **The one-panel-per-display rule is not negotiable** and applies to the
   takeover surface too: the union-panel measurement in `CursorOverlay`'s header
   is about the window server, not about this overlay.

## Child work found, not done here

- **`scroll`'s delta mapping is a fraction of the document, not lines.** The
  shipped `current + delta/100` on a scroll bar means a delta of 3 barely moves
  and 200 jumps to the end. Fixing it changes what every existing scroll does.
- **The page action outranks the precise bar write.** An element offering
  `AXScrollDownByPage` scrolls a page rather than the delta asked for. Same
  reason for leaving it.

## Out of scope

Making a step work that genuinely cannot travel the accessibility plane. A
resident window-order observer. Any change to which kinds are synthetic. Any
change to the HUD's design, level or placement.

## Verification

`swift build` + `swift test`; 544 tests / 66 suites are green at HEAD and stay
green. New tests per clause. What a Swift test cannot reach is named plainly:
the restack itself, the occlusion, the dimming, the presentation of any panel,
and anything else that needs a window server. Those are covered by the probe
measurements recorded above and by the decision function's unit tests, and the
gap is stated rather than dressed up.

## Triage review

Out-of-family gate: **grok-4.6, `xhigh`, read-only**, 2026-08-15, evidence
inlined (Codex is off for this repo). Fifteen findings; four were real and are
folded into the design above.

| # | Finding | Disposition |
|---|---|---|
| 4 | Cross-process `order(_:relativeTo:)` is not a documented capability; one pixel sample on 26.6 is not a contract | **Accepted — changed the design.** A7b: the placement is read back and demotes to the dimmed fallback when it does not hold. |
| 10 | No read-back: an AX write that succeeds and does nothing is a silent no-op | **Accepted.** A5b; and it is what lets A4 reach web inputs, whose `AXValue` writes are commonly accepted and ignored. |
| 11 | A failed `AXSelectedText` after select-all leaves the field selected, so the fallback's first keystroke empties it | **Accepted.** The original selection is restored on any failure after the range write. |
| 5 | The proposed predicate is tautological (`certainSteps` appears twice) | **Accepted.** Restated as `mightPost \|\| raises`. |
| 8 | `AXVerticalScrollBar` is an element reference, so the value goes on the bar, not the scroll area | **Accepted as a clarification** — that was the intent; the design now says it. |
| 1 | Scroll writes an absolute thumb position with wrong units | **Rejected as stated.** The existing branch is `current + delta/100`, relative, and this reuses it verbatim; the crudeness is real and recorded as child work rather than changed here. |
| 3 | A default `type`/`scroll` batch takes no lane and can still post | **Rejected on evidence.** `Actuator.type` and `Actuator.scroll` *refuse* the synthetic fallback when `foreground` is false, so a batch that did not ask for the front cannot reach the event stream. The new predicate is exactly "might post". |
| 2 | `type` should insert at the caret, not replace | **Rejected.** Replace is the shipped contract of the verb; changing it is a different item. |
| 9 | The page action is tried before the precise bar write | **Rejected with reason.** Reordering changes what already-working scrolls do. Child work. |
| 12 | The nearest of 12 ancestors is often the wrong scroller; `AXWebArea` has no bar | **Accepted as a limitation.** The walk takes the first `AXScrollArea` exposing a settable bar and otherwise falls through to today's behaviour — no regression. |
| 13 | `optionOnScreenOnly` "goes blind without Screen Recording" | **Rejected on evidence.** Only window *names* are gated on that grant; number, bounds and layer are not, and nothing here reads a name. |
| 6, 7 | `LaneDemand` must ship in the same change; three predicates glued together | Already in A2 / the design. |
| 14 | The dimmed fallback still draws above everything; per-draw window-list reads | Answered: the dim *is* the marker, and the read is once per step. Both stated in the design. |
| 15 | `collectionBehavior`, `ignoresMouseEvents`, macOS floor unspecified | Answered in assumption A8. |


## Completeness critic

Out-of-family gate: **grok-4.6, `xhigh`, read-only**, 2026-08-15, evidence
inlined. Seven findings; two were real and are fixed at `a383048`.

| # | Finding | Disposition |
|---|---|---|
| 5 | The inert-foreground sentence has no surface: `notice()` is nil in exactly that case | **Accepted, fixed.** `ForegroundReport.note` is computed, so Codable never emitted it and `act` said nothing in prose. It now rides alongside as `foregroundNote`, and flow replay's identical sentence takes the same key instead of its own `note`. |
| 7 (part) | The global window-list index is poisoned by the other screens' panels, since only one is restacked | **Accepted, fixed.** Every other surface goes back to the floating band before a placement, so a sibling left in the normal band by an earlier step cannot land between this panel and its target and fail a placement that was correct. |
| 1 | `type` reports success on an unverified write, and a readable mismatch is unspecified | **Half accepted.** The mismatch case *is* specified and falls through to the second route (`writesAreReadBack` pins it). Treating an **unreadable** value as "took" is deliberate and documented: a secure field never reports its value, and disbelieving every such write would push them all to the event stream. No regression either way. |
| 2 | The event fallback is orphaned: a failed selected-text write returns false and never reaches `CGEventPost` | **Rejected on evidence.** `typeIntoSelection` returning false falls straight through to that `guard foreground` and the post. |
| 3 | The synthetic `type` appends where the AX rungs replace; `activate` is async | **Accepted as pre-existing.** Both are unchanged by this work and the path is now reached less often, not more. Recorded as child work. |
| 4 | Synthetic steps take the exclusive lane without raising anything | **Rejected on evidence.** `pointer`, `key` and `drag` all call `activate(target.pid)` before posting. A lone `raise` taking the lane is PRO-0016's deliberate rule. |
| 6 | Scroll magnitude and target are wrong on every rung; the walk can skip an area that *is* the element; the wheel posts at the cursor | **Mixed.** The walk starts at the element, and the wheel fallback warps to the element's centre first: both rejected on evidence. The unit and ordering complaints are the two limitations already recorded as child work. All-or-nothing across axes is kept, because this route is only reached where the old code always refused, so nothing regresses. |
| 7 (rest) | `.normal` cannot match a target on another layer; `orderFrontRegardless` leaves the panel frontmost when the order fails; the fallback promotes to `.screenSaver`; no Screen Recording means an empty list | **Answered.** The first two are exactly what the read-back catches, and the end state is the dimmed pointer rather than a stuck panel. The dimmed promotion is the fallback the brief names in so many words. `CGWindowListCopyWindowInfo` gates only window **names** on Screen Recording, and nothing here reads a name: the probes ran unsigned from `/tmp` with no grants at all and got a full list. |
