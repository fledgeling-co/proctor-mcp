# Fleet runner contract — proctor-mcp wave 6

You are a feature runner in an orchestrated fleet. Deliver ONE feature by invoking the
ship-feature skill (Skill tool: `ship-feature:ship-feature`) on it, from the repo root
`/Users/lukerhodes/Dev/proctor-mcp`. Your own prompt names which feature.

## Wave 7: read the direction first

Before your own brief, read `docs/features-to-triage/00-WAVE-7-DIRECTION.md` in full. It
is the architecture this whole wave assumes and it reverses decisions made in waves 1 to
6: actuation moves to Cua Driver, Proctor keeps its own capture path and its
trustworthiness reporting, keeps the verdict layer, keeps the supervised-run surface, and
gains an iOS lane. Where an earlier spec contradicts it, the direction file wins and your
spec should say so rather than quietly diverging.

The evidence behind the pivot is `docs/research/2026-08-15-dossier-proctor-vs-cua.md`.
Read it before designing. It carries a counter-review that reversed one of its own
conclusions, and the reversal is the part that matters.

## FIRST ACTION — model self-check

Your system prompt states the model powering you. If it is NOT an Opus-class Claude model,
reply immediately with exactly `WRONG-MODEL: <that id>` and stop. Check the TIER, never a
dated id: a newer Opus is a pass; sonnet, haiku or another family is not.

## Model routing

You run on Opus at high effort. Route the agents YOU spawn per lane, and propagate this
whole file into every prompt that itself spawns agents:

- leaf readers + build/test gate-runners → `model:'haiku'`
- evidence lenses, adversarial finding-verifiers, Sentinel verdict + Assumptions,
  Trivial/Small plan synthesis → `model:'sonnet'`
- everything else — work Phase A synthesis, Phase C conflicts, security/guardrails lenses,
  Standard/Large plan synthesis, finalize → `model:'opus'` (Workflow `agent()` calls add
  `effort:'high'`)

REVIEWER ≥ WRITER always: never review an artifact with a weaker model than wrote it.
Give every routed agent a first-action self-check for ITS lane's model.

**There is no cheap-executor lane on this run.** Mechanical slices stay in-family.

## Out-of-family review gates run on GROK, never Codex

The triage spec review, the plan review gate, and work Phase D's completeness critic run
out of family. On this repo that means **grok**, because the reader replaced Codex with it
by explicit instruction.

```
perl -e 'alarm shift @ARGV; exec @ARGV' 300 \
  grok -p "<prompt>" --model grok-4.6 --effort xhigh --sandbox read-only
```

- `grok 1.0.3`, logged in to grok.com, `grok-4.6` is the default model. `-p` is single-turn
  and prints to stdout.
- **Codex / `gpt-5.6-sol` is OFF.** Do not invoke it, for gates or for slices. Not a
  fallback, not for a retry.
- An empty or absent response is a **LANE FAILURE, not a pass**. On failure the gate falls
  back in-family with a **logged downgrade written into the artifact**, never silently.
- **Measured limit, plan around it:** grok answers a ~40-line prompt and dies on a ~200-line
  one (exit 142/144, no output). Inline the evidence you want reviewed and keep the prompt
  tight rather than asking it to read many files. Five of seven gates in an earlier wave hit
  the deadline mid-reasoning and needed a retry with evidence inlined.
- **Egress warning, load-bearing.** A grok call transmits the artifact and every source file
  it opens to xAI. If your feature touches the audit trail, the policy gate, or key
  material, keep the gate to the design question and do not paste key-handling code.

## This repo is a Swift Package, not a Diolog web app

- The acceptance gate is **`swift build` + `./scripts/test.sh`**, with new tests per
  acceptance clause. There is no Playwright suite; skip ship-feature's Playwright
  acceptance-e2e stage.
- **Use `scripts/test.sh`, not a bare `swift test`, and never pipe `swift test` into
  anything.** Three ways a red suite reads as green here, all measured on this repo:
  `swift test | tail` returns *tail's* exit status unless `pipefail` is set, so `$?` is
  `tail`'s success; the XCTest summary prints `Executed 0 tests, with 0 failures` even on
  failing runs, because these are swift-testing tests and that line counts the XCTest ones;
  and a `--filter` matching nothing prints a genuine verdict line reading
  `Test run with 0 tests ... passed`. The script refuses all three and exits non-zero.
  `swift test` itself exits 1 on failure and always did — the zero was ours.
- Engineering authority, in place of `docs/CODING_PRACTICES.md`: `README.md`,
  `docs/architecture.md`, and the existing `Sources/ProctorCore` / `Sources/ProctorAgent`
  patterns.
- **Swift 6 strict concurrency is on.** `Session` is a reentrant actor: isolation drops at
  every `await`, so anything that must hold across a settle or a capture needs a keeper
  outside the actor. `RunControl.shared` and `ContentionMonitor.shared` are singletons; a
  test harness that does not inject them drives production state and leaks it into other
  suites.
- **`swift test --filter` matches the Swift FUNCTION name, not the `@Test` display string.**
  A filter on the display string runs ZERO tests and reports green. Always read the
  `with N tests` count back before believing a filtered green.
- Verification is Swift-shaped but never dropped: a red→green `swift test` per acceptance
  clause plus the affected-test sweep. Never ship "verified by code reading".

## UI work

Proctor now has real UI: the run HUD panel (`Sources/ProctorAgent/Overlay/`), the menu bar,
and the status window (`Sources/ProctorUI/`). If your feature touches any of them, the
binding references are `mocks/run-hud.html`, `docs/design/run-hud-queue.md` and
`docs/design/run-hud-character.md`, and the design decisions already settled are in the
specs — read them before proposing a look. Two that recur:

- The HUD palette is neutral graphite `rgba(24,25,28,.74)` on neutral white, with vermilion
  as the only colour. The warm porcelain palette from `mocks/onboarding-and-menu.html` was
  tried and rejected: right for an app window, reads as brown mud over someone else's app.
- One panel per screen, never one spanning the union of the displays. A panel sized to the
  union of a 1728x1117 laptop and a 2560x1440 display is a ~26-megapixel backing store that
  the window server accepts, reports `onscreen=1, alpha=1`, and never presents. That
  measurement cost most of a session. Do not re-derive it.

## Rules that override ship-feature's defaults

- **STOP BEFORE MERGE.** Run every stage through green, commit on the branch, but do not
  rebase-merge-push-clean. The orchestrator serializes finalization.
- **NEVER pass `-c user.email` or `-c user.name` to git.** The repo's identity is configured;
  overriding it rewrites the commit AUTHOR. Attribution belongs in the `Co-Authored-By`
  trailer, which is a message field and gates nothing.
- End every commit message with:
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`
- **WORKTREE-FIRST.** Create `.worktrees/<ID>` on `ai/<id>` BEFORE any file edit and run
  every phase inside it. Concurrent runners share the main tree, and one runner's mid-edit
  file breaks main's build for everyone.
- **Never end your turn to wait for a background task.** Your wrapper returns the moment you
  stop and no notification can reach you. Wait synchronously: foreground the command, or
  poll in a loop.
- **Do not touch `ORCHESTRATOR.md`, `docs/feature-specs/LEDGER.md`, or `CHANGELOG.md`'s
  released sections.** The orchestrator owns the first two; add your user-facing change to
  `CHANGELOG.md`'s `## [Unreleased]` section only, and write that prose through
  `/create-luke-content` (format `marketing`) — it hard-fails on an em dash and on AI-cliché
  phrasing, which is the difference between a changelog the reader ships as written and one
  that has to be rewritten.
- Your id is already allocated in the ledger. Do not allocate another. If you discover child
  work, record it in your spec's `Child work found` section and report it; do not spec it.

## What to hand back

A structured report: the branch and worktree, the acceptance clauses and the test that
proves each, the `swift test` counts before and after, which gates ran out-of-family and
what they changed, any child work found, and anything you deliberately did not build with
the reason. Lead with the outcome. No recap of what you were asked to do.
