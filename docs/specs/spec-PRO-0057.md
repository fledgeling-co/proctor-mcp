# PRO-0057: The witness tier, and what it refuses

**ID:** PRO-0057
**Status:** In Review
**Created:** 2026-08-16
**Last updated:** 2026-08-17
**Branch:** `ai/pro-0057` (worktree `.worktrees/PRO-0057`)

Second item of the guest-target wave. See `docs/features-to-triage/57-vm-targets.md`.

## The problem

The wave adds Linux and Windows targets, driven through Cua. Proctor's
instruments are macOS APIs: `SCFrameStatus` on a capture, an `AXUIElement` tree,
and the tri-observer `agree` check that reports where the tree, the geometry and
the pixels disagree. None of those cross into a delegated lane. What arrives
instead is a screenshot with no completeness signal and whatever the driver says
it did.

Without a gate, `proctor_assert` would run its tree-reading kinds against a tree
that does not exist and report the results as if they meant something. Both
out-of-family reviewers named this as the failure mode of the whole wave: a
reachable non-macOS guest *looks* first-class and silently degrades.

## What was built

`WitnessTier` in `Sources/ProctorCore/Wire.swift`: `native` for a macOS machine
running a full Proctor, `delegated` for actuation-and-screenshots through another
tool. It sits on `Machine` as a stored property.

`WitnessTier.cannotEvaluate(_ kind:)` returns the reason a kind cannot be asked,
or nil. `SessionAssert` consults it once before the `switch kind`, and a refused
kind returns `status: .skipped` carrying that reason.

A tier does **not** scale a score or soften a verdict. It decides what can be
asked at all. That is the skill's existing rule — an assertion that could not be
evaluated is not an assertion that passed — applied to a substrate rather than to
one call.

## Three decisions worth the words

**The gate is a list of what survives, not a list of what is refused.**
`pixelKinds` holds `regionMatches` and everything else is refused. The two shapes
fail in opposite directions: a kind added later and forgotten is *refused* by this
one and *silently permitted* by the other. A refusal on a kind that would have
worked is visible and gets complained about; a permission on one that cannot be
evaluated is a pass nobody measured. `anUnknownKindIsRefused` pins it.

**Checked once, above the switch, rather than inside each kind.** The question is
about the substrate rather than the assertion, and a per-kind check would be
sixteen places to forget it.

**`tier` has no default.** It is the only parameter on `Machine` without one. A
default of `.native` would let a construction site that forgot to say describe a
Linux guest as carrying a frame-status channel and an accessibility tree it does
not have, and every assertion this gate exists to skip would then be evaluated
against nothing and pass. Same argument `ActuationBackendID` makes about lanes:
absent is detectable, wrong is not.

That choice has a visible cost, and it is the intended one. Rebasing onto main
broke `MachineDisclosureWiringTests` at three construction sites, each of which
now names its tier. A compile error is exactly what should happen when somebody
adds a machine and does not say what it can observe.

## The pixel caveat, and why it is attached rather than folded in

`regionMatches` is the one kind a delegated machine can attempt, so it is the one
that needs qualifying. The comparison genuinely ran; what is missing is any
guarantee that the frame it ran against was complete. The caveat is appended to
the outcome's reason rather than changing the verdict, because downgrading a real
pass to a fail would be inventing a defect, and reporting it unqualified would be
claiming evidence Proctor did not have.

## Evidence

`WitnessTierTests`, 12 tests: native refuses nothing across all fifteen kinds;
delegated refuses all fourteen tree-reading ones; an unclassified kind is refused;
`regionMatches` survives; the refusal names the kind, the cause and a way forward;
a delegated assertion through a real `Session` comes back `skipped` with a reason
and not `pass`; the same assertion on a native machine is actually evaluated; a
skipped assertion cannot make the run `ok`; both caveat states; and the tier
round-trips on the wire.

One thing the tests found rather than assumed: `assertAll` already computes
`ok` as `failed == 0 && skipped == 0`, so a skipped assertion could never have
made a run green. That is pre-existing and correct, and the test now pins it
against future edits.

Gate: **1459 tests in 161 suites pass in 7.1s** (1447 before).

## Not in scope

Anything that sets a machine to `delegated` in production. Nothing constructs a
guest yet and nothing routes to one; those are PRO-0058 through PRO-0061. The
changelog for the whole wave lands with PRO-0062, per the direction document.
