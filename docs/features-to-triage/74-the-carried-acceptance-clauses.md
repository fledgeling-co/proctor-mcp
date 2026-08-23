---
sources: [REQ-048]
---
# Two acceptance clauses that merged carried rather than green

**Wave 11, brief 5 of 6.** Independent of `70`-`73`. Both clauses were honestly recorded as
carried at merge rather than reported as passing, which is why they are still findable — and why
closing them is a small job rather than an archaeology one.

## The measurement

**PRO-0066's A2 does not pass and its spec says so.** The clause reads *every user-facing string
comes from `StatusSurface`; a grep for a quoted string literal in `MainWindow.swift` outside an
identifier returns nothing.* The progress note records what actually shipped:

> A2 is partly done and is honestly recorded as such. The window's body, the new agent-down block
> and the new Lanes section read every string from `StatusSurface.Copy`. The five older sections
> still carry their own literals; converting them is mechanical and did not fit this change
> without risking a working window.

Measured today against `Sources/ProctorUI/MainWindow.swift`: **188 quoted literals that are not
identifiers.** The clause is not close to passing, and nothing in the suite fails because of it.

**PRO-0067's A3 is unverified and its spec says so.** The clause reads *the disabled next button
is present in the tree in every state where it is disabled* — a control that disappears makes the
layout jump and teaches the user the step does not exist. The progress note:

> A3 is not verified. The disabled-next-button clause needs the rendered view, and this repo has
> no `ProctorUI` test target. The identifier is defined and set; whether the control is
> present-and-disabled rather than absent is a fidelity-harness question and is carried to the
> campaign lane rather than claimed here.

## Why they are worth closing now rather than carrying again

Both carries were made for the same reason and that reason has since expired.

A2 was deferred because converting five sections risked a working window with no instrument to
prove it still worked. `SurfaceFidelity` and the embedded `ProctorReflector` shipped in PRO-0067
and now give exactly that instrument: the conversion can be proved surface-by-surface rather than
argued for.

A3 was deferred because there was no `ProctorUI` test target and no way to ask whether a control
is present-and-disabled versus absent. The `macos-glass` lane is now attached and proved, with
eight captures and a working capture manifest, so the question has somewhere to be asked.

A carried clause that outlives its reason stops being a deferral and becomes an untested claim.

## What to do

**A2.** Move the five older `MainWindow` sections' strings into `StatusSurface.Copy`, one section
at a time, with the fidelity harness run between each. The clause's own grep is the gate: it has
to return nothing at the end, and it is the acceptance evidence. Strings that are genuinely
identifiers stay where they are, which is what "outside an identifier" in the clause means — keep
that distinction mechanical rather than judged, so the grep stays honest.

**A3.** Ask the question on the glass lane: render the walkthrough in each state where next is
disabled, and assert the control is in the tree and disabled rather than absent. If the harness
cannot resolve present-versus-absent for a SwiftUI control, that is a real ceiling and the honest
result is a case at `inconclusive:` naming the instrument — not a clause quietly dropped.

Note what is already established and must not be re-litigated: there is no supported way to read
resolved SwiftUI modifier values from outside the framework, and this package does not pretend
otherwise. `ProctorReflector` walks AppKit views. A3's question is about tree presence, which the
accessibility tree can answer, rather than about a resolved modifier value, which it cannot.

## The conversion contract

- A2's grep returns nothing, run as the acceptance evidence rather than described.
- A3 either passes on the glass lane with its capture manifest, or resolves to `inconclusive:`
  with the instrument named and the ceiling recorded in structural terms.
- Both specs' progress notes updated so the carry is closed where it was recorded, not only in a
  new document. A carry closed somewhere else is a carry a future reader will find still open.
- `./scripts/test.sh` green, with the suite count before and after.

## What this brief does not do

It does not convert any surface the mock and the build already agree on, and it does not revisit
the composition decisions settled in wave 9 — the status window keeps its explanation, its title
block and its grant-row treatment. Those were the reader's call and they were made.
