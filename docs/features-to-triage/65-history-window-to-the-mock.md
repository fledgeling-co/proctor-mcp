---
sources: [REQ-033]
status: retired
---
# The history window, and the detail that says what it could not check

**Wave 9, brief 7 of 11.** Reads `58`, `59`. Mock anchors: `#mac/history/ideal`,
`#mac/history/empty`.

## The problem

`HistoryWindow.swift` lists runs. The mock adds two things: an **empty state that names the
action that fills it**, and a **per-run detail** showing each assertion's verdict — including
the ones that were skipped, with the reason.

The skipped verdict is the point. Proctor's whole thesis is that a check which could not run
is not a check that passed, and the history window is where a person reads the result of a
run. A detail pane that shows three passes and silently omits the fourth check because no
reflector was available is the exact failure the product exists to prevent, committed by the
product's own UI.

## What it should do

Two states, and a detail pane.

- **Ideal** — the folded run rows, one expandable, its assertions with `pass`, `fail` and
  `skipped` each drawn differently, and `skipped` carrying its reason.
- **Empty** — no runs recorded, what starts the trail, and the retention that governs it.

## The conversion contract

- `RunHistory` already owns the projection and is pure, and it deliberately excludes the
  redacted value and script fingerprints, the post-state hash, the key ids and the session
  handles. **Nothing in this brief widens that.** A field not on the face of the window is
  not in the type, and that is the guarantee.
- The detail pane reads the same projection.

## Acceptance

1. `skipped` renders differently from both `pass` and `fail`, and carries its reason string.
   A test asserts a skipped assertion can never be counted into a pass total.
2. The empty state names the action that fills it, not the absence of data.
3. No redacted fingerprint, hash, key id or session handle is reachable from any view in this
   window — a test over the projection's field list, so a later widening of `RunHistory` fails
   here rather than leaking.
4. An application is identified by bundle id, never by the `app-3` handle, which is
   meaningless once the agent restarts.
5. Retention is stated on the surface: 14 days or 10,000 entries, and the trail rotates whole
   rather than pruning from the front.

## The hard parts, named

**Every string in this window came from somewhere else.** App titles are authored by the
application under test; flow and run names are authored by the calling model. Both are
untrusted, both are fenced by `RunHistory.Object`, and the view must render through the
fence rather than around it — the compiler is the rule here, because the failure is invisible.

**Rotation is not pruning, and the copy must not say it is.** The trail is hash-chained from
a genesis over its own prefix, so removing entries from the front is unrepresentable: the
first survivor would link to a record that is gone. The window says the trail rotates.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-033
- surface: SURF-017, SURF-036
- cases: CASE-0033, CASE-0034, CASE-0035, CASE-0036, CASE-0040, CASE-0041
- rungs reached: effect-witness, metamorphic, outcome
- provider: Darwin.bind/listen/accept in Sources/ProctorAgent/Server.swift; Darwin.connect in Sources/ProctorCore/Transport.swift
