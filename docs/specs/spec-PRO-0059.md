# PRO-0059: `proctor_guest`, the lifecycle tool

**ID:** PRO-0059
**Status:** In Review
**Created:** 2026-08-17
**Last updated:** 2026-08-17
**Branch:** `ai/pro-0059`

Fourth item of the guest-target wave. See `docs/features-to-triage/57-vm-targets.md`.
Depends on PRO-0058.

## The problem

PRO-0058 made `lume` and `prlctl` look like one seam. Nothing a caller can
invoke uses it. A model that wants to start a guest, or even know which guests
exist, has no tool.

## What was built

`proctor_guest` with actions `list` / `status` / `start` / `stop` / `clone`,
following `proctor_ios`'s shape:

- A non-window handle (`gst-` plus a hash of provider and name). Every
  window-taking tool refuses it by name rather than reporting a missing window.
- The ceiling is stated in the catalogue description *and* on every `list`
  result, because a model that reads a handle and reaches for a snapshot has
  already stopped reading descriptions.
- Nothing provisions. A guest that does not already exist is refused. The
  grant-once-then-clone recipe lives on the tool and on the listing note.
- Ambiguity across two providers is an error naming the candidates, not a
  guess.
- Neither CLI present is a named refusal, not an empty listing: those are
  different facts.
- Mutating actions are audited under `proctor_guest.start` / `.stop` / `.clone`.

The adapters stay injectable. Tests plant a fake; production builds them from
the filesystem probes PRO-0058 already added.

## Evidence

`GuestToolTests`, 11 tests: the catalogue states the ceiling and the five
actions; a guest handle is refused at the window seam; an ordinary unknown
window is unaffected; list returns handles and starts nothing; start changes
state and lands on the trail; clone copies and will not invent a source; a
name held by two providers is refused; neither CLI is a named refusal.

Catalogue count is now 21. Gate: **1494 tests in 171 suites**.

## Not in scope

SSH reach (PRO-0060), auto-routing (PRO-0061), the overlay badge (PRO-0062).
Nothing in production attaches a session to a guest yet. Changelog deferred
to the end of the wave.
