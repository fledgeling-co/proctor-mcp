# Notice when a person is taking the machine back, and yield

## The problem

A synthetic-event run needs the foreground. While it holds it, the person sitting
at the Mac is fighting it: they click, the run clicks somewhere else; they type,
the keystroke lands in whatever the run just raised. Today Proctor has no idea
this is happening. It carries on, and the only way out is to find the Stop button
on a panel that may be on a display they are not looking at.

The person's own input is the signal, and it is already there for the taking. What
is missing is Proctor treating it as meaning something.

## What it should do

Notice the contention, and get out of the way. When Proctor is driving through the
event stream and a person's own input arrives against it, that is a person taking
the machine back. Proctor should pause the run, say so on the HUD, and offer to
hand it back rather than carrying on and losing the argument on their behalf.

Two behaviours, and the second is the one that was asked for:

- **Yield automatically for a short window.** Hold the run and let the person do
  what they came to do. This costs nothing when it fires wrongly: a paused run
  resumes, and pausing is already a thing Proctor knows how to do.
- **Ask, where asking is possible.** Better than a silent pause, because a person
  who did not mean to interrupt gets to say so and a person who did gets a real
  choice. The HUD already has room for one line and two controls, and the queue
  work established that a run can be held indefinitely without breaking.

## Signals worth considering, and their honesty

The strength of this feature is entirely the quality of its signal, so the spec
should name which one it takes and what it costs.

- **Real user input while a synthetic step is in flight.** The most direct reading,
  and it needs care: Proctor's own synthetic events must never count as the
  person's. `CGEventSource` state and the event's own source can separate them.
  Getting this wrong makes Proctor pause itself forever, which is worse than not
  having the feature.
- **The frontmost application changing under the run.** Cheap and unambiguous: if
  the run raised an app and something else is now in front, a person did that.
- **Secure Event Input turning on.** Already reported by `proctor_doctor`. It means
  a password field somewhere has focus, which is a person mid-task and the one
  moment where injected keystrokes are least welcome.

An input observer is a real privacy surface, and this repo already declined one
for PRO-0015's click-through. Triage should decide deliberately: whether a
foreground-only, run-scoped monitor is a different proposition from an always-on
one, and whether the frontmost-app signal alone buys enough to skip it.

## Scope

- Only a run that is actually contending. An accessibility-plane run does not take
  the foreground and does not need this; pausing it would be noise.
- The pause is the existing `RunControl` pause, with its backstop, not a new
  mechanism.
- A yielded run reports it: the trail says the run was held because a person was
  using the machine, so a slow test run has a reason rather than a mystery.

## Not in scope

Deciding whether the person's action was a mistake. Proctor does not get a vote on
what somebody meant to do with their own Mac.
