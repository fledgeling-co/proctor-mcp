---
sources: [REQ-034, REQ-035, REQ-036]
status: retired
validated-by: REQ-034, REQ-035, REQ-036 via CASE-0044, CASE-0045, CASE-0046, CASE-0057, CASE-0080, CASE-0081
validated-rungs: effect-witness, metamorphic, outcome
validated-provider: Darwin.bind/listen/accept in Sources/ProctorAgent/Server.swift; Darwin.connect in Sources/ProctorCore/Transport.swift
---
# `proctor`, the operator CLI

**Wave 9, brief 10 of 11.** Reads `58`, `59`. Specified in `docs/PRD.md` §15. Mock anchors:
`#cli/catalogue/all`, `#cli/doctor/human`, `#cli/doctor/json`, `#cli/act/ok`,
`#cli/act/refused`, `#cli/act/assertfail`, `#cli/act/stability`, `#cli/install/flow`.

## The problem

**Status: not built.** `proctor-shim` has seven commands and every one is install-or-serve
plumbing. No capability of the product is reachable from a shell.

Four jobs have no path. Debugging a selector needs a model in the loop to issue each call.
CI cannot run a flow and assert without embedding an MCP client. A campaign cannot be
scripted. And a defect report cannot carry a reproduction command, because there is no
command to carry — which is a real cost the test campaign paid, since every one of its
28 cases had to be driven through an MCP session by hand.

## What it should do

One binary, one verb per tool, over the same socket. `proctor-shim` stays as an alias so
existing host configurations keep working.

**A CLI call is not a privilege bypass.** Same socket, same policy gate, same queue lane,
same audit trail, same HUD disclosure. The only thing that differs is who called — and the
trail needs an actor field to say so, which it does not have today.

**Two output contracts.** Human tables by default; `--json` emits the **exact wire object**
the MCP tool returns, unaltered, so a script and a model see the same bytes and a bug
reproduces identically through either front end.

**Exit codes carry the verdict**, because CI reads an exit code rather than prose:

| Code | Means |
|---|---|
| 0 | the call succeeded and any assertion passed |
| 1 | the call succeeded and a verdict failed |
| 2 | usage error |
| 3 | agent unreachable |
| 4 | refused by the policy gate or the guest-route gate |
| 5 | refused for a missing grant or an unavailable lane |

1 and 3 must not be confused: one is a failed check, the other is nothing measured.

## Acceptance

1. Every one of the 21 tools has a verb, and a test enumerates `ToolCatalogue.all` against
   the verb table so a new tool without a verb is a red test.
2. `--json` output is byte-identical to the MCP `tools/call` result for the same arguments.
3. A refused call exits 4 and appears in the audit trail with `outcome=refused`, with an
   actor distinguishing it from an MCP caller.
4. A CLI actuation takes a queue lane; two concurrent CLI calls against one app serialise,
   and against different apps run in parallel — the same three-lane model, proven through
   the new front end.
5. `proctor doctor --json --lane mac` exits non-zero when that lane is not ready, and 0 when
   it is.
6. The CLI installs nothing. A test asserts no code path in it spawns a package manager.
7. Shell completion is generated from `ToolCatalogue`, so it cannot drift.

## The hard parts, named

**Handles live in the agent and survive between invocations**, so a stateless CLI process can
use them — but a person should not be copying `win:3:3` by hand. `--app com.apple.TextEdit`
and `--window front` resolve at call time and print the handle chosen, so the next command
can use it.

**Reads must not queue.** The three-lane model says reads never join the line, and a CLI that
takes a lane for `proctor snapshot` would serialise a person's debugging behind a model's run.

## Open decisions, for triage rather than the implementer

- **How `act` takes a step batch.** Repeated flags are pleasant for one step and unusable for
  six, which is the shape batching exists for; stdin JSON is honest for a batch and awkward
  interactively. Both is a defensible answer and costs a parser.
- **Whether the CLI holds a session identity across invocations.** Attachment state already
  persists in the agent, but "which session is this" decides queue attribution and the hold
  attribution the HUD shows. Per-invocation makes every call a new session; per-terminal
  needs somewhere to keep an id.
