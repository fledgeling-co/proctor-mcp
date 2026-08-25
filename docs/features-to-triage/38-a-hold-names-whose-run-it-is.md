---
sources: [REQ-038]
status: retired
---
# A hold names whose run it is

## The problem

PRO-0018 taught Proctor to hold a run when a person takes the machine back, and
logged what it could not say. With two runs in flight against different
applications, the menu bar shows the highest-precedence hold across all of them
and does not say whose it is. The queue bar has the rows; nothing joins the two.

A person seeing a hold indicator therefore knows something is held and not what,
which on a machine running one session is enough and on a machine running three
is the wrong half of the information.

A second gap sits next to it, from PRO-0016: `proctor_apps.activate` brings an
app to the front and takes no lane, because that spec scoped queueing to a batch,
a replay and a sweep. So a call that genuinely takes the foreground is invisible
to the thing that accounts for who has the foreground.

## What it should do

Attribute a hold to the session and the display it belongs to, and account for
`activate` in the lane model that already exists for every other way of taking
the front.

## The hard parts, named

- **This is a change to the queue's model**, which PRO-0016 built with three
  lanes and a keeper living outside the actor. Read what is there before adding
  to it: the keeper exists because a reentrant actor drops isolation at every
  `await`, and anything that joins the hold state to the queue state has to hold
  that same line.
- **A menu bar item is one glyph.** Attribution has to live somewhere that can
  carry a name, which is the queue bar or the panel, with the menu bar continuing
  to show precedence. Say what each surface is responsible for rather than trying
  to make the icon say more than an icon can.
- **Session identity is derived from the peer process, never client-supplied.**
  That was settled in PRO-0016 for a reason that holds here exactly: a connection
  that could name itself could impersonate another one in the very UI a person
  uses to decide whether to stop it. Whatever names a hold uses the derived
  identity.
- **`activate` taking a lane changes when it blocks.** It currently never waits.
  Giving it a lane means it can. Say what a caller sees when it does, because a
  call that used to return immediately and now queues is a behaviour change for
  anything already driving Proctor.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-038
- surface: SURF-020, SURF-038
- cases: CASE-0048, CASE-0049, CASE-0055, CASE-0086, CASE-0750, CASE-0751
- rungs reached: effect-witness, outcome
- provider: none
