# PRO-0073: `proctor`, the operator CLI

**ID:** PRO-0073 · **Status:** Ready for Plan · **Created:** 2026-08-20
**Brief:** `docs/features-to-triage/68-the-operator-cli.md` · **PRD:** §15
**Branch:** `ai/pro-0073` off `ai/wave-9` · **Depends on:** PRO-0064
**Mock:** `#cli/catalogue/all`, `#cli/doctor/*`, `#cli/act/*`, `#cli/install/flow`

## The problem

Not built. `proctor-shim` has seven commands and every one is install-or-serve plumbing, so no
capability of the product is reachable from a shell. Debugging a selector needs a model in the
loop; CI cannot assert without embedding an MCP client; a campaign cannot be scripted; and a
defect report cannot carry a reproduction command. The 28-case campaign paid that cost — every
case was driven through an MCP session by hand.

## Acceptance criteria

1. **A1** — every one of the 21 tools has a verb. A test enumerates `ToolCatalogue.all` against
   the verb table, so a new tool without a verb is a red test.
2. **A2** — `--json` output is byte-identical to the MCP `tools/call` result for the same
   arguments, so a script and a model see the same bytes.
3. **A3** — a refused call exits 4 and appears in the audit trail with `outcome=refused` and an
   actor distinguishing it from an MCP caller.
4. **A4** — a CLI actuation takes a queue lane: two concurrent CLI calls against one app
   serialise, against different apps run in parallel.
5. **A5** — reads do not queue. A `proctor snapshot` must not serialise a person's debugging
   behind a model's run.
6. **A6** — `proctor doctor --json --lane mac` exits non-zero when that lane is not ready.
7. **A7** — the CLI installs nothing; a test asserts no code path spawns a package manager.
8. **A8** — shell completion is generated from `ToolCatalogue` so it cannot drift.

**Exit codes:** 0 pass · 1 verdict failed · 2 usage · 3 agent unreachable · 4 refused by a gate
· 5 missing grant or unavailable lane. 1 and 3 must never be confused: one is a failed check,
the other is nothing measured.

## Decisions taken at triage

- **A CLI call is not a privilege bypass.** Same socket, same policy gate, same queue lane,
  same audit trail, same HUD disclosure. The only difference is who called, and the trail gains
  an actor field to say so.
- **`proctor-shim` stays as an alias** so existing host configurations keep working.
- **Handles resolve at call time.** `--app` and `--window front` print the handle chosen, so a
  person is not copying `win:3:3` by hand.

## Parked for the reader — appended to the goal brief's Open questions

- **How `act` takes a step batch.** Repeated flags are pleasant for one step and unusable for
  six; stdin JSON is honest for a batch and awkward interactively. Both is defensible and costs
  a parser. **Assumption taken to unblock:** support both, stdin JSON as the documented path.
- **Whether the CLI holds a session identity across invocations.** It decides queue attribution
  and the hold attribution the HUD shows. **Assumption taken:** per-invocation session, because
  it needs no new state; revisit if the HUD's attribution reads wrong.
