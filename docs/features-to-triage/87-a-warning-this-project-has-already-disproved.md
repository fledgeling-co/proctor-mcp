---
sources: [REQ-108]
status: retired
---
# Proctor ships a guest warning its own spec records as not reproducing

**Wave 13, brief 7.** Raised by a consumer session on 2026-08-21 that was about to download a
Sequoia image on the strength of this warning. Sequence it ahead of the rest of wave 13: it is
cheap, and it is costing somebody else time right now.

## The warning, and the measurement that contradicts it

`proctor_doctor`'s guest lane says, without qualification:

> Tahoe guests currently render no application windows (trycua/cua #870, Apple FB21748086); verify
> against Sequoia.

It is shipped in three places — `Sources/ProctorCore/ToolchainLanes.swift:161`,
`Sources/ProctorCore/ToolCatalogue.swift:1173`, and
`Sources/ProctorAgent/Session/SessionGuest.swift:134`.

This project measured it and it did not hold. `docs/specs/spec-PRO-0076.md:581-583`:

> **The Tahoe window-rendering warning did not reproduce.** […] In this Tahoe 26.6.2 guest,
> Calculator, System Settings and Setup Assistant all rendered normally.

So Proctor tells every reader that a whole lane cannot draw a window, while its own spec records
three applications drawing windows in exactly that configuration. A consumer session read the
warning, could not check it, and concluded its isolated lane might need a different macOS image —
a download and a scheduling decision, both bought with a claim this repo had already disproved.

**Do not simply delete it.** The upstream issues are real and were real when the note was written;
what is wrong is the tense and the certainty. One guest on one host at one version is not proof the
bug never bites, and a bare deletion would replace an over-claim with a silence. The note should say
what was measured, when, and on what — and let the reader judge.

## The gap that makes it uncheckable

**Nothing reports a guest's macOS version.** A grep across `Sources/ProctorAgent/Guest/` and
`Sources/ProctorCore/Guest*.swift` for `osVersion`, `productVersion` or `sw_vers` returns nothing,
and the consumer session confirmed it from the other side: neither `lume get` nor tart's
`config.json` records it — both report only `macOS`/`darwin`.

So a reader told "verify against Sequoia" has no way to discover whether the guest they hold is
Sequoia or Tahoe. The advice is unactionable through Proctor's own surface, which is why the warning
propagated instead of being checked.

`proctor_guest --action status` is where this belongs. A running guest can be asked directly; a
stopped one may not be answerable at all, and reporting `unknown` with a reason is the honest
result rather than a guess from the image name.

## One thing the reporting session got wrong, worth correcting back

Their note says Proctor's guest lane "requires lume/prlctl, not tart". Tart **is** supported:
`TartProvider` is at `Sources/ProctorAgent/Guest/GuestProvider.swift:307`, and
`ToolchainLanes.swift:134-153` builds the lane from `[lume, prlctl, tart]` and names all three in
its blocker text. If that was not obvious from the tool surface, that is a discoverability finding
of its own and should be recorded.

## What to build

- The three warning sites carry one sentence sourced from one constant, stating what was measured
  (Tahoe 26.6.2, three applications rendering), when, and that the upstream issues remain open. Not
  three hand-written copies — a second copy is a second source, and this repo has already shipped
  that defect twice.
- `proctor_guest --action status` reports the guest's OS version where it can be established, and
  `unknown` with a reason where it cannot. Never inferred from the image name.
- A test that the warning text and the recorded measurement cannot drift apart — the note cites the
  measurement, so the citation is checkable.

## What this brief does not do

It does not claim the upstream bug is fixed, and it does not close trycua/cua #870. It does not
change guest provisioning, which deliberately happens outside a tool call.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-108
- surface: SURF-002
- cases: CASE-0002, CASE-0074, CASE-0154, CASE-0370, CASE-0372, CASE-0373
- rungs reached: metamorphic, outcome
- provider: none
