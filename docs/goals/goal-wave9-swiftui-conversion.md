# Goal: ship wave 9 — the surface set becomes the app

- **slug:** wave9-swiftui-conversion
- **armed:** 2026-08-20 (pending — see Preflight)
- **project:** /Users/lukerhodes/Dev/proctor-mcp
- **bound:** 60 turns / deadline 2026-08-21 09:00 local / stuck after 3 identical failures

## Objective

Take the eleven wave-9 briefs from untriaged to merged, converting the surface set at
`design/surfaces/proctor-surfaces.html` into SwiftUI, the operator CLI and the supervision
TUI. Finished means every item is terminal in `LEDGER.md`, the Swift suite is green, and the
test campaign accounts for every case with the coverage ratchet held — no case unmeasured,
no case unarmed.

The wave exists because `Sources/ProctorUI` was built surface by surface across eight waves
and does not read as one designed thing. The method that makes the conversion provable is in
`docs/features-to-triage/58-swiftui-conversion-direction.md` and every brief inherits it.

## Worklist

Eleven items. Ids are allocated by `/triage` at run time; `gate-wave9.sh` maps each brief to
whichever spec cites it and reads that spec's id out of `LEDGER.md`, so the gate does not
depend on guessing them.

| ID | Item | Brief | Status |
|---|---|---|---|
| W9-01 | Design tokens as a generated Swift value | `59-design-tokens-as-a-swift-value.md` | pending |
| W9-02 | The fidelity harness — Proctor measures Proctor | `67-the-fidelity-harness-proctor-on-proctor.md` | pending |
| W9-03 | Status window to the mock | `60-status-window-to-the-mock.md` | pending |
| W9-04 | Walkthrough to the mock | `61-walkthrough-to-the-mock.md` | pending |
| W9-05 | Menu bar and the command surface | `62-menu-bar-and-the-command-surface.md` | pending |
| W9-06 | Run HUD and the seven character states | `63-run-hud-and-the-character.md` | pending |
| W9-07 | Takeover overlay and the drawn pointer | `64-takeover-overlay-and-the-drawn-pointer.md` | pending |
| W9-08 | History window to the mock | `65-history-window-to-the-mock.md` | pending |
| W9-09 | Consent sheets | `66-consent-sheets.md` | pending |
| W9-10 | The operator CLI | `68-the-operator-cli.md` | pending |
| W9-11 | The supervision TUI | `69-the-supervision-tui.md` | pending |

Total: 11.

**Build order is not brief order.** W9-01 first and alone — everything reads its output.
W9-02 second, because the fidelity records for W9-03 … W9-09 are unwritable without it, and
a wave that converts seven surfaces and then looks for a way to check them has drifted.
Then W9-03 and W9-04 in parallel; W9-05 after W9-04; W9-06/07/08 disjoint; W9-09 after
W9-03; W9-10 and W9-11 last, W9-11 after W9-10.

## Gates

Run by the guard at the end of every turn, in the repo root, judged on exit code alone.
Ordered cheapest first.

| Name | Command | Passes when |
|---|---|---|
| build | `swift build` | compiles |
| tests | `./scripts/test.sh` | every test passes |
| campaign | `campaign.py check docs/test-campaign` | every case produced a measurement; none unattempted |
| ratchet | `strict-check.py docs/test-campaign` | checked-case count has not regressed |
| wave9 | `bash docs/goals/gate-wave9.sh` | all 11 items terminal in `LEDGER.md` |
| runners | `bash docs/goals/gate-runners.sh` | no worktree HEAD older than 45 minutes |

`campaign` and `ratchet` are the "no testing unknowns or gaps" half of the finish line, and
they are separate on purpose: one asks whether every case was measured, the other whether
coverage went backwards. Combined they would name the failure imprecisely.

`runners` passes vacuously when no runner worktree exists and says so in its own output
rather than reporting a clean population as a healthy one. It skips the main checkout and the
integration worktree by path identity.

**`tests` is `./scripts/test.sh` and not `swift test`, and the difference is load-bearing.**
Measured on this branch: bare `swift test` exits 1 while reporting all 1,520 tests passing —
the run leaks a continuation at teardown. The repo's script writes the run to a file and
reads the verdict back, so it is not fooled by that or by a pipe eating the status. Arming
the bare command would have held this gate permanently red.

## Blocked-item policy

**Do not stop to ask.** Every question goes through `/clarify:clarify`, which settles what it
can from the repo and this file, refers technical forks to another model family, and reaches
a human only for taste, cost, scope, risk tolerance or something irreversible.

- A fork `/clarify` can settle → settle it, and record the call in the item's spec.
- A fork that needs a human → **park the item**, append the question to Open questions
  below with what each answer would change, and take the next item. A parked item does not
  block the wave; it blocks itself.
- A gate failing for a reason outside this wave (the peer session's work, a flaky
  environment) → say so in the ledger note rather than editing the gate to pass.

**Never edit a gate to make it green.** A gate that was changed to pass is a finish line
that moved, and the run cannot tell the difference afterwards.

## Resources

| Resource | Reserved for this run | Conflicts with |
|---|---|---|
| `/Applications/Proctor.app` + its launchd agent | shared | the campaign drives the installed app; W9-02 needs a debug build with the Reflector embedded, which is a *different* artifact — do not overwrite the installed one mid-campaign |
| 1 booted simulator | no | no wave-9 item uses the iOS lane; the campaign may |
| Local `main` | **contested** — see Preflight | the peer session `proctor-mcp-5b` |
| Agent socket | shared, single | two runs driving the same agent will interleave; the run queue arbitrates but the campaign's evidence does not |

## Delivery

- **Driver:** `/ship-fleet:ship-fleet`
- **Verification:** `/test-campaign:test-campaign` after each surface item merges, extending
  the existing 32-case campaign rather than starting a new one
- **Model / effort:** `claude-opus-5` / `high`
- **Concurrency cap:** 3 — the cap this repo has used since wave 1, and measured rather than
  preferred: two capacity failures on 2026-08-15 (a 503 `over_reserve` that killed four
  stage-1 runners at once, and `replayd` saturating machine-wide under fleet load)
- **If an agent dies:** `/workflow-resume`, then refill the slot. The `runners` gate is what
  notices; the watcher is what wakes the run when the ledger goes quiet.

## Stop conditions

- All six gates pass and no item is pending. This is the finish line.
- 60 turns, or the deadline, or three identical gate fingerprints in a row.
- The agent socket becomes unreachable and `proctor doctor` cannot be made to answer — the
  campaign cannot produce evidence without it, so continuing would bank unverified work.

## Open questions

_Appended during the run by the blocked-item policy. Empty at arm time._
