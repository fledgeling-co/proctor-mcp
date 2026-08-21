# PRO-0084 — The cua path leaves Proctor's plane silently

**Status:** To Do → Ready for AI · **Brief:** `docs/features-to-triage/77-the-cua-path-leaves-proctors-plane-silently.md`
(Wave 12, brief 1 of 2) · **Branch:** `ai/pro-0084` off `ai/wave-9`
**Ledger id:** allocated upstream. This item does not write `docs/feature-specs/LEDGER.md`.
**Ranges:** cases CASE-0230..0249 · defects DEF-120..129 · requirements REQ-070..072.

## The reproduction, first, because the brief asked for it

### 1. What draws "Automation Running" — identified

macOS draws it, from a private framework, and the artifact is exact:

```
$ plutil -extract en xml1 -o - \
    /System/Library/PrivateFrameworks/AutomationMode.framework/AutomationModeUI.app/Contents/Resources/Localizable.loctable
  <key>Automation Mode Enabled Title</key>
  <string>Automation Running</string>
  <key>Automation Mode Disabling Interaction</key>
    <key>mac</key>  <string>Press . to stop</string>

$ ps -Ao pid,comm | grep AutomationModeUI
64198 /System/Library/PrivateFrameworks/AutomationMode.framework/AutomationModeUI.app/Contents/MacOS/AutomationModeUI
```

The binary carries the classes `Overlay` and `OverlayView` and the log line
`Failed to set up event tap, user interaction will not cause the automation mode UI to fade.`
It is parented to `launchd` (ppid 1) and was already running on this machine.

**This reverses the brief's caution, with evidence rather than by assumption.** The brief was right
to refuse the unchecked claim; the checked claim now holds. The banner belongs to macOS's
AutomationMode, which XCTest / `testmanagerd` drive — **not to Proctor and not to cua-driver**.

**The scan that found nothing is recorded as having proved nothing.** `strings` over
`dyld_shared_cache_arm64e` and its fifteen subcaches returned zero — and so did a control probe for
`NSApplicationDelegate`, which must be present. A dead instrument's zero is not a negative, and it
is only reported here because it was armed and failed. The finding above came from an instrument
that was armed and passed.

### 2. What this means for the report's first clause

> "Some apps using Xcode accessibility with 'Automation Running' overlays don't show the HUD or use
> the fake cua mouse at all, and instead take over the real mouse."

Those runs are **XCUITest under macOS AutomationMode, not Proctor**. Proctor never armed an overlay
for them because Proctor was not driving. No Proctor defect is reachable from that clause, and no
change in this item can make an overlay appear over another automation stack's run. Recorded as
**REQ-072's ceiling**, not fixed.

The report's *second* clause is Proctor's, and is the whole of the work below.

### 3. The trigger, and why "not often"

`CuaDriverTool.laneSelected` (`Sources/ProctorCore/CuaDriverTool.swift:51`) is
`environment["PROCTOR_ACTUATION"]?.lowercased() == "cua"`, read **once** in
`main.swift:makeActuationBackend`, and `Session.actuator` is immutable. `main.swift:60-70` states
there is deliberately no condition that flips it. So **lane selection is not intermittent**: within
one agent process it is fixed.

What *is* intermittent is escalation **inside** the lane. `CuaActuationBackend.backgroundCapability`
answers `.maybe` for every kind the driver can perform (`:64-66`) because the driver tries an
accessibility action, then a routed event, and escalates to the front only when neither works —
decided per element, knowable only when `perform` returns. That is the "not often", and it is
per step rather than per run.

`PROCTOR_ACTUATION` is also a saved switch (`SwitchCatalogue.actuation`, timing `.nextStart`), so
it can be set from the status window and persist. On this machine it is currently unset:
`launchctl getenv PROCTOR_ACTUATION` is empty and no `settings` file carries it.

## What the tree actually does today, re-read on this branch

The brief predates several of these. Each is re-measured here.

| Brief's claim | As the tree stands |
|---|---|
| No HUD on the cua path | **Already fixed.** `hudRunBegan(…, delegated: actuator.id != .native)` is unconditional at `SessionAct.swift:263`. |
| No takeover notice | **Wrong, and only arming showed it.** See §5. |
| Nothing reaches the pointer overlay; grep returns zero | **Wrong seam, right symptom.** `showCursor(for:window:owner:)` *is* called on this path (`SessionAct.swift:415`). It returns immediately when `owner == .deferredToDriver` (`SessionCursor.swift:38`). |
| The covered-target rule is never consulted | **Only when the pointer is deferred.** When Proctor draws, `CursorOverlay.applyPlane` consults `PointerPlanePolicy.fallback` (`CursorOverlay.swift:324`). |
| `unrequestedForeground` is recorded, never shown | **Holds.** It reaches `StepResult.carry` and the wire; no HUD event and no overlay reads it. |

### 5. The claim that did not survive arming — and the guard that replaced it

The brief says an unrequested escalation raises no takeover statement, and the source reads that
way: `takeoverShow` fires under `(synthetic || stepsAside)` (`SessionAct.swift:411`) and cua answers
`.maybe`, never `.never`, so `synthetic` is false. A first cut added a second raise on
`unrequestedForeground`, with a test asserting the statement went up.

**The test passed with that production line deleted.** Evidence:
`docs/test-campaign/evidence/PRO-0084/arming.txt`.

The cause is a coupling two files apart. `CuaActuationBackend` sets `escalated` only for a path in
`CuaVocabulary.foregroundPaths` — `{cgevent_fg, key_events_fg}` — and `CuaVocabulary.planes` maps
**both** to `.syntheticEvent`, which `SessionAct.swift:653` has always raised the statement for. So
`unrequestedForeground` is a strict subset of a branch that already fires, the second raise could
never fire alone, and the statement was never missing.

What *was* missing is the **wording**. The raised statement and the panel's exception line both say
the batch needs the front — `exceptionLine` is literally "Synthetic event — X must stay in front" —
and neither says the batch **never asked** and the driver took the front anyway. That is the
distinction a person watching an unexplained takeover needs, and `unrequestedForeground` is the only
value carrying it.

The redundant raise was removed rather than kept as harmless. The coupling that makes it redundant
was **unguarded by any test**, so CASE-0236..0238 now pin it: if a vocabulary change ever mapped a
foreground path to another plane, the statement would silently stop appearing for a real takeover.

So the mechanism is narrower than the brief drew it, and it is real. The three symptoms reduce to
**two silent facts**, each knowable at a moment Proctor already has:

1. The driver took the front without this batch asking — `Actuation.unrequestedForeground`, true
   when `perform` returns.
2. Proctor stood its own pointer down — `PointerOwnership.decide(delegated:driverSuppressible:)`
   returned `.deferredToDriver`, decided once per run at `SessionAct.swift:349`.

Neither reaches the screen. Both already reach the wire.

## Requirements

**REQ-070 — An unrequested escalation is distinguishable from a requested one.**
When a delegated step returns `unrequestedForeground`, the run panel says the front was taken and
that this batch did not ask for it — rather than the existing sentence, which says the batch needs
the front. The takeover statement itself already goes up (§5) and is not raised twice. Late by one
step is the only honest moment: the driver decides at the element and reports on return.

Folded into REQ-070 rather than given an id of its own: the coupling that keeps the statement
appearing at all — every path in `CuaVocabulary.foregroundPaths` maps to the plane `SessionAct`
raises the statement for, and no other path does — is guarded by CASE-0236..0238.

**REQ-071 — A run that cannot draw its own pointer says so.**
When `pointerOwner == .deferredToDriver`, the panel states that this batch drives the real cursor
through cua-driver and that the pointer on screen is not Proctor's. No fabricated pointer stands in
for one Proctor is not posting — the brief forbids that, and it would be a drawn claim about a
position Proctor never chose.

**REQ-072 — The two ceilings are recorded as ceilings.**
(a) A deferred pointer cannot carry wave 9's covered-target rule: the rule places or hides
*Proctor's* panel, and a pointer drawn by another process is neither placeable nor hideable by
Proctor. Stated in source at the stand-down, not worked around.
(b) Another automation stack's run (macOS AutomationMode, §2) is outside every surface Proctor
arms. Stated here.

## Out of scope, stated so it stays out

- `sharingType = .none` on the HUD and takeover overlay. Correct; evidence must not change because
  somebody was watching.
- Removing or demoting the cua backend.
- Widening `noteSyntheticPost`'s grace window to the delegated lane. `SessionAct.swift:468-479`
  refuses this for two measured reasons and neither has changed.
- Arming contention on a delegated escalation. It is defensible and it is a **behaviour** change to
  yielding rather than a **visibility** one; the brief scopes this item to what the screen says.
  Carried out as an open question rather than taken silently.
