# PRO-0073: `proctor`, the operator CLI

**ID:** PRO-0073 · **Status:** Merged · **Created:** 2026-08-20
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
  **Settled 20 Aug 2026, and the assumption had not been built.** Every flag value was typed as
  a scalar, so `--steps '[…]'` reached the agent as a string and came back "requires steps as an
  array", and nothing read stdin — which left eight of the twenty-one verbs unable to be given
  their main argument. `CLIArguments` now parses a bracketed flag value as JSON and merges an
  object from stdin underneath the flags. Stdin is asked for with `-` or `--stdin` rather than
  inferred: inferring it from `isatty` hung any caller whose stdin was an open pipe nothing
  wrote to, which is what a CI runner and an agent harness both give you.
- **Whether the CLI holds a session identity across invocations.** It decides queue attribution
  and the hold attribution the HUD shows. **Assumption taken:** per-invocation session, because
  it needs no new state; revisit if the HUD's attribution reads wrong.

## Verification

Status: **Merged** on `ai/wave-9`. Suite: 1,618 tests in 189 suites, green.

### Settled here

- **A1** — `CLISurface.verbs` is derived from `ToolCatalogue.all` rather than listed, and two
  tests assert the derivation: every tool has a verb, and no verb collides with another or with
  a service verb. A tool added without a verb is a red test rather than a gap somebody notices.
- **A3, exit-code half** — `exit(for:)` maps every `AgentError.Code` the wire can produce, and a
  test asserts 1 and 3 are never the same answer. The default is `verdictFailed`, so a code this
  build has not heard of reads as a failed check rather than as an unreachable agent.
- **A3, actor half** — `AuditRecord.via` names the front end, stamped at `AuditLog.append`, the
  single point every row passes through. The value comes from the peer process's executable name
  as the kernel reports it, never from the request — the same rule `SessionIdentity` already
  holds for the project name, and for the same reason: a caller that could name itself could
  name itself as the other one, in the record used to argue about what it did. Nil reads as
  "this build did not say", never as "MCP". Eight tests, including that a row sealed before the
  field existed still decodes.
- **A5** — `queues` is `!spec.readOnly`, so the three-lane model's "reads never queue" reaches
  the CLI from the catalogue rather than from a second list. Asserted over every tool.
- **A6** — `CLISurface.exit(forReply:lane:)` was moved out of the CLI target so it could be
  asserted against replies written by hand; a decision only reachable through a live agent is a
  decision nothing checks. Six tests, including that `--lane mac` stays 0 when the iOS lane is
  unusable, and that an explicit `"failedAt": null` is the wire saying nothing failed rather than
  a failure at step nil.
- **A7** — `forbiddenInstallMarkers` asserted over the usage text and both completion scripts.
- **A8** — completion is generated from the catalogue for zsh and bash; an unknown shell returns
  nil rather than a script that would be wrong.

### Settled later, by the 0.8.0 campaign

- **A2 is settled.** `proctor doctor --json` and the MCP `tools/call` result for the same tool
  agree across 23 top-level keys and 51,195 characters, measured against a wave-9 agent on its
  own socket. The fields that differ are the ones that must: a tool probe re-run seconds later
  stamps a new `checkedAt`. Evidence: `docs/test-campaign/evidence/cli-json-identical.json`.

### Needs a live agent

- **A2** — that `--json` is byte-identical to the MCP `tools/call` result. The code encodes the
  reply verbatim and adds nothing, but byte-identity is a claim about two running front ends and
  only a live agent can settle it.
- **A4** — that two concurrent CLI actuations against one app serialise and against different
  apps do not. The CLI takes the same socket into the same scheduler, so the behaviour is
  inherited rather than reimplemented; the inheritance is what needs measuring.
- **A3, end-to-end** — that a refused CLI call actually lands `outcome=refused` with `via=cli` in
  the operator's trail. Each link is tested; the chain through a real socket is not.

### A defect found by building rather than by reviewing

The product was first named `proctor`, which is what a person types. On a case-insensitive
volume — which APFS is by default — that is the same file as the UI product `Proctor`, so the
two link targets collide. `swift build` reported success, and the binary at `.build/…/proctor`
was the SwiftUI app: `proctor --help` opened a window and hung instead of printing usage.
Nothing in the toolchain says so, and the app bundle would have shipped whichever product linked
last.

The product is now `proctor-cli`, ships in the bundle under that name beside the agent and the
shim, and is reached as `proctor` through a symlink the person makes. `CLISurface.shippedBinaries`
holds the four names, and three tests stand behind it: no two differ only by case, the invoked
name is not a shipped name, and `build-app.sh` places and signs every one of them.
