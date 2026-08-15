# Wave 7 direction: Cua underneath, Proctor on top

**Read this before any wave 7 brief.** It is the architecture every item in this wave
assumes, and it reverses decisions made in waves 1 to 6. Where a spec from an earlier
wave contradicts this file, this file wins, and the spec should say so rather than
quietly diverging.

The evidence behind it is `docs/research/2026-08-15-dossier-proctor-vs-cua.md`: a
42-source panel, four adversarial lenses, two of which changed the conclusion. Read
that before designing, not after.

## What changed

Cua Driver (`trycua/cua`, MIT, macOS 14+) does what Proctor's actuation layer does,
better resourced and cross-platform: background accessibility-plane actuation, window
targeting, a drawn agent cursor, permission checks, and a browser lane that binds a
native window to its tab and drives it over CDP. It ships 130+ commits a week.

**Proctor stops competing on actuation and delegates it.** What Proctor keeps is
everything Cua deliberately does not do, plus the whole supervised-run surface the
reader asked to keep working.

## The split, and it is not negotiable in either direction

**Cua owns actuation.** Clicks, typing, key events, scrolling, drags, menu invocation,
window targeting and raising. Proctor calls it rather than reimplementing it.

**Proctor owns observation.** This is the half a counter-review forced, and it is the
one thing that must not be handed over. Cua returns screenshots with **no frame-status
metadata**, while Apple defines six `SCFrameStatus` values and makes checking them a
precondition of trusting a frame. Cua's own docs say the accessibility tree "lies on
some surfaces", and its screen-lock defect is open with a capture returning zero pixels
beside 746 menu-bar-only elements. A verification layer needs at least one channel it
can trust, so **Proctor keeps its own ScreenCaptureKit path and its own trustworthiness
reporting.** Do not replace `proctor_capture` with a Cua screenshot.

**Proctor owns the verdict.** Assertions, the accessibility audit, visual fidelity,
determinism and flake scoring, the tri-observer disagreement check, and the reflector
for apps you own. Cua-Bench scores agents; nothing in that stack scores an application
under test.

**Proctor owns supervision.** The run HUD, the character, the menu bar, the queue, the
yield-when-a-person-takes-the-machine behaviour, Stop, the policy gate and the sealed,
signed audit trail. Delegating actuation must not weaken any of it: a run driven
through Cua is still a run somebody can see, pause and stop, and every delegated call
is still gated and recorded.

## Three things that will go wrong if nobody says them

- **The audit trail must not develop a hole.** PRO-0005, PRO-0013 and PRO-0032 built a
  gated, sealed, signed trail on the assumption that Proctor performs the action it
  records. If actuation moves to a subprocess and the gate stays where it was, Proctor
  records intent rather than action, which is a weaker claim wearing the same words.
  Whatever the design, say plainly what the trail now attests to.
- **Stop must still stop.** PRO-0033 made a person's click reach Stop on the first
  press through Proctor's own event tap. A delegated step is posted by another process,
  so the discrimination rule "only what Proctor posted" no longer identifies the same
  set of events. This needs an answer, not an inheritance.
- **A fallback is a decision, not a safety net.** Proctor's existing planes still work.
  Keeping them as an automatic fallback means two actuation paths with different
  failure modes, and a run that silently changes plane mid-flight is the kind of thing
  that makes a determinism score meaningless. If they are kept, say when they are used
  and make it visible in the run record.

## iOS is a second driver lane, not a port

The reader wants iOS support through **deep links and Maestro**, following the lane
`acceptance-e2e` already documents: drive the iOS Simulator via Maestro `.maestro` YAML
flows, navigating deep-link-first with `xcrun simctl openurl`.

Treat it as a peer of the Cua lane behind the same Proctor surface: same flow shape,
same evidence, same audit trail, same HUD. What differs is that a Maestro flow is a
file executed by a separate binary rather than a step list Proctor drives call by call,
so the honest reporting of *what was proven* differs too, and the spec should say how.

## What this wave must not do

Do not rebuild anything Cua already does. Do not delete the reflector. Do not weaken
the recovery decision from PRO-0013: a lost keychain key still means a permanently
unreadable history, and no export path, second secret or plaintext copy is added to
work around it.
