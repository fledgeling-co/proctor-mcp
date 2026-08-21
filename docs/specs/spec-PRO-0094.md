# PRO-0094: a guest warning this project has already disproved, and the version nobody reports

**ID:** PRO-0094 · **Status:** To Do · **Created:** 2026-08-21
**Brief:** `docs/features-to-triage/87-a-warning-this-project-has-already-disproved.md` (Wave 13)
**Branch:** `ai/pro-0094` off `ai/wave-9` · **Lane:** headless, `./scripts/test.sh`
**Requirements:** REQ-059, REQ-060 · **Defects:** DEF-090..DEF-094 · **Cases:** CASE-0180..CASE-0189
**Ledger id:** allocated by the orchestrator. This item does not write `docs/feature-specs/LEDGER.md`.

## Ready for implementation plan

**What a reader gets today.** Ask Proctor whether the machine is healthy and it tells you, flatly,
that guests running the current macOS cannot draw an application window, and to go and check
against the previous macOS instead. There is no date on it, no hedge, and no way to find out
whether the guest you are holding is even the version being warned about — Proctor never reports a
guest's macOS version anywhere. On 2026-08-21 a reader acted on it and was about to download a
20 GB operating-system image on the strength of a claim this project had already tested and found
not to hold.

**What they get after this.** The same warning, with its date, the machine it was tried on, and
what actually happened when it was tried — three applications drew their windows normally. It still
names the two unresolved reports upstream, so a reader can weigh them; it no longer states as
settled fact something that was measured once and did not reproduce. And asking for a guest's
status now answers "which macOS is this?" — with the version when Proctor can genuinely establish
it, and with `unknown` plus the reason why when it cannot. It never guesses from the name of the
image.

**One more thing a reader could not see.** Proctor drives guests through any of three providers,
and the tool's own description named only two of them. Someone reading it concluded the third was
unsupported. It is fixed here.

### Assumptions

1. **The version comes from the guest itself, or not at all.** Proctor establishes a guest's macOS
   version only by asking the Proctor running inside it, over a link this session already holds —
   rather than reading it off the provider's own listing (none of the three records one) or
   reaching in over SSH (Proctor deliberately opens no tunnel).
2. **A guest nobody is attached to answers `unknown`, with the route to an answer.** Rather than
   status opening a link of its own, which would take one of the two macOS guest slots for a read.
3. **"Verify against Sequoia" is dropped from the note.** Rather than kept: the same reader who is
   told to verify has no way through Proctor to discover which macOS they hold, so the advice sent
   somebody to buy an image instead of a check.
4. **The note carries its citation in the text a reader sees.** Rather than in a source comment,
   which nobody reading a tool result can check.

### Pipeline record

Sentinel tier **S1** — a developer-facing tool surface; no user data, no access-control or
sharing-scope default, no external dependency added. Lenses run: product, UX-copy, correctness,
observability, compliance. No Essential Questions survived the divergence test: every fork above
resolves the same way under both readings, or is settled by measurement already in this repo.
**Out-of-family spec review.** The codex lane (`gpt-5.6-sol`) was down — *"You've hit your usage
limit … try again at Aug 27th"* — recorded as a lane outage, not a skip. The next family answered:
`agy` / `gemini-3.7-flash-high`, read-only, grounded in this worktree. Verdict **0 Critical,
0 High, 1 Medium, 2 Low**; transcript `/tmp/pro0094-agy.md`. Tally **3 accepted, 0 rejected**:

- *Medium — the missing-guest refusal at `SessionGuest.swift:77` also names two providers.*
  Accepted; folded into REQ-060b, which now covers the refusal text and the `Wire.swift` comments
  as well as the schema.
- *Low — the defect table cited `GuestRecord` for DEF-093 while the spec says its wire shape does
  not change.* Accepted; the row now cites the grep result and `guestStatus`.
- *Low — CASE-0182 must anchor the repo root on `#filePath`, not the working directory.* Accepted;
  written into the clause.

Its two escalations were considered and not taken. It read assumption 2 (an unattached guest
answers `unknown` rather than status opening a link) as an owner policy call: the repo already
encodes it — `SessionGuest.swift`'s own header states "No implicit start … Powering on is stateful
and takes tens of seconds", and a status read that took one of Apple's two macOS guest slots would
reverse that. It read assumption 3 (dropping "verify against Sequoia") as an owner copy call: the
brief that commissioned this work states the fault is "the tense and the certainty", and REQ-060 is
that advice made actionable rather than the advice withdrawn. Both stay assumptions.

One caution about that lane's evidence: it cited provider parsing at `TartInventory.swift` and
`LumeInventory.swift`, files this repo does not have, while giving `GuestInventory.swift` line
numbers. The claim it supports — that no provider listing carries an OS version — is separately
grounded in the brief's own `lume get` / `config.json` check and in the grep recorded above, so
nothing here rests on that citation.

## The problem

`proctor_doctor`'s guest lane, `proctor_guest`'s tool description and every `proctor_guest` result
carry this sentence:

> Tahoe guests currently render no application windows (trycua/cua #870, Apple FB21748086); verify
> against Sequoia.

Three hand-written copies, at `Sources/ProctorCore/ToolchainLanes.swift:161`,
`Sources/ProctorCore/ToolCatalogue.swift:1173` and
`Sources/ProctorAgent/Session/SessionGuest.swift:134`.

This project measured it and it did not hold. `docs/specs/spec-PRO-0076.md:581-583`, against the
`lume` guest `proctor-guest` on macOS 26.6.2 on 2026-08-21: *"Calculator, System Settings and Setup
Assistant all rendered normally."* The same session's evidence at `spec-PRO-0076.md:501` records
that guest's own `proctor_doctor` answering `os 26.6.2` over the attach link — so the configuration
the warning describes is the configuration Proctor drove, five steps deep, with the guest's screen
as the second witness.

Two separate faults, and the second is what let the first travel:

- **The tense and the certainty are wrong.** "currently render no application windows" is a
  present-tense claim about every Tahoe guest. What is true is that two upstream reports are open
  and that one measurement here did not reproduce them. Neither of those is the other.
- **Nothing reports a guest's macOS version.** `osVersion`, `productVersion` and `sw_vers` return
  zero hits across `Sources/ProctorAgent/Guest/` and `Sources/ProctorCore/Guest*.swift` (measured
  by grep on this branch, 2026-08-21). Neither `lume get` nor tart's `config.json` carries one —
  both say only `macOS`/`darwin`. So "verify against Sequoia" is advice a reader cannot act on
  through Proctor's own surface, and the cheapest thing left to do with the warning is believe it.

A consumer session on 2026-08-21 did exactly that: read the warning, could not check it, and
concluded its isolated lane might need a Sequoia image — a download and a scheduling decision, both
bought with a claim this repo had already disproved.

### The defects

| id | what | where |
|---|---|---|
| DEF-090 | An unqualified present-tense claim that Tahoe guests render no windows, contradicted by this repo's own recorded measurement | the three sites below |
| DEF-091 | The same sentence hand-written in three places, so a correction lands in one and not the others | `ToolchainLanes.swift:161`, `ToolCatalogue.swift:1173`, `SessionGuest.swift:134` |
| DEF-092 | `proctor_guest`'s `provider` input schema enumerates only `lume` and `prlctl`, so a caller naming the supported third provider is rejected by schema validation before reaching code that accepts it | `ToolCatalogue.swift:1205`, and the prose at `:1124`, `:1176`, `:1200` |
| DEF-093 | No surface reports a guest's macOS version, which is what made DEF-090 uncheckable rather than merely wrong | `SessionGuest.guestStatus`; `osVersion`/`productVersion`/`sw_vers` return zero hits across the guest sources |
| DEF-094 | Reserved for a fault this work uncovers; unallocated if none does | — |

DEF-092 is the discoverability finding the brief asks to be recorded: `TartProvider` is at
`Sources/ProctorAgent/Guest/GuestProvider.swift:307`, `ToolchainLanes.swift:134-153` builds the
guest lane from `[lume, prlctl, tart]` and names all three in its blocker text, and
`SessionGuest.resolvedGuestProviders` constructs all three. The tool surface a reader actually sees
named two. A reader concluded from it that tart was unsupported, and they were reading the only
surface that speaks to them.

## The behaviour

### REQ-059 — one note, from one constant, bound to its measurement

`GuestNotes.tahoeRendering` in `Sources/ProctorCore/GuestInventory.swift` is the single source. It
holds the measurement as fields — the guest's macOS version, the date, the applications that
rendered, the upstream issue ids, and the path of the spec section that records it — and composes
the sentence from them, so the prose cannot say one thing while the fields say another.

The sentence states what was measured, when, on what, that the upstream issues remain open, and
where to check:

> Tahoe guests were reported to render no application windows — trycua/cua #870 and Apple
> FB21748086, both still open — but on 2026-08-21 Proctor drove a macOS 26.6.2 guest in which
> Calculator, System Settings and Setup Assistant all rendered normally (docs/specs/spec-PRO-0076.md),
> so treat it as an open report upstream rather than a settled property of every Tahoe guest.

All three sites interpolate that constant. The literal strings `FB21748086` and `#870` appear
**exactly once each** across `Sources/`, which is the mechanical form of "one source": a second
occurrence is a second copy and is red.

"verify against Sequoia" is gone. It is replaced by nothing rather than by different advice,
because REQ-060 is the actionable form of the same instruction.

### REQ-060 — `proctor_guest --action status` reports the guest's macOS version

The status result gains one field, `osVersion`, of a new pure `ProctorCore` type:

```swift
public struct GuestOSVersion: Codable, Sendable, Equatable {
    public var version: String?   // nil exactly when unknown
    public var source: String     // "guest-agent" when known, "unknown" otherwise
    public var reason: String?    // present exactly when version == nil
}
```

**Known.** When this session holds an open link to that same guest — the link `action "attach"`
opened — status asks the Proctor inside it the same question `probe()` already asks
(`proctor_doctor`, which actuates nothing), and reports the `osVersion` that answer carries.
`source` is `guest-agent`. That is the channel `spec-PRO-0076.md:501` measured live.

**Unknown, with a reason.** Every other case, and each reason names what would change it:

| situation | reason |
|---|---|
| the guest is not running | it cannot be asked, and no provider records a guest's macOS version — start it and attach |
| the guest is not macOS | a delegated guest carries no Proctor to ask |
| running, but this session is not attached to it | there is no link to ask over; attach and read status again |
| attached, but the guest's Proctor did not answer or carried no version | what the link said, verbatim |

**Never inferred.** No branch reads the version out of `record.name`, the image name, the provider
id, or `record.platform`. `platform` answers *which OS*; it has never answered *which version*, and
a guest named `macos-sequoia-cua` is not evidence of anything. The negative is checkable: the
resolution is a pure function of `(record, attachment-state, agent answer)` and takes no name.

The decision is a pure `ProctorCore` function so every branch is provable with neither `lume`,
`prlctl` nor `tart` on the machine — the rule `GuestInventory.swift` already sets for this lane.
`source` is a string rather than an enum for the reason `GuestRecord.state` is: a channel a later
build adds survives into an older reader's report instead of being flattened.

### REQ-060b — the third provider is discoverable

`proctor_guest`'s `provider` enum becomes `["lume", "prlctl", "tart"]`, and its description, the
tool's summary line and its `Requires` line name all three. The enum is the load-bearing half:
prose that omits a provider misleads, but a schema that omits one refuses the call.

The same two-provider list is also in the refusal a caller reads when they omit the guest
(`SessionGuest.swift:77`) and in the `Machine` field comments at `Wire.swift:704-706`. Both are
fixed here. A correction that lands on the schema and leaves the error message saying something
else is DEF-091's shape a second time, in a different file.

### Edge cases

A session attached to guest A calling status on guest B gets `unknown` for B with the not-attached
reason, never A's version — the link is matched to the guest by provider and name, not by "this
session has a link". A link that fails mid-status yields `unknown` carrying what the link said, and
does **not** tear down the attachment: status is a read, and a read must not release somebody's
pool slot. A guest whose Proctor answers with an empty or absent `osVersion` is `unknown` with that
stated, not `version: ""`.

### Failure modes

Status costs one extra round trip over a link that is already open, and only when one is. Nothing
here starts a guest, opens a tunnel, takes a pool slot, or runs a provider CLI it would not
otherwise run.

## What this does not change

It does not claim the upstream bug is fixed and does not close trycua/cua #870. It does not
provision, start, stop, clone, delete, prune, rename or export any guest — `proctor-guest` and
`anvil-mac-node` are stopped and stay stopped. It does not open an SSH tunnel. It does not add a
provider, change `GuestRecord`'s wire shape for `list`, or touch attach, detach or the pool.

## Acceptance

1. `FB21748086` and `#870` each appear exactly once in `Sources/`, counted with `len()` over the
   grep hits rather than read off a printed list. (CASE-0180)
2. The doctor guest-lane note, the `proctor_guest` tool description and `guestCapabilities` each
   contain `GuestNotes.tahoeRendering` verbatim, asserted against the constant rather than against
   a copy of its text. (CASE-0181)
3. The constant's measurement fields — `26.6.2`, `2026-08-21`, and each of Calculator, System
   Settings and Setup Assistant — are each found in the recorded measurement at
   `docs/specs/spec-PRO-0076.md`, read from disk at test time. The repo root is derived from
   `#filePath`, never from the process's working directory, which `swift test` does not promise.
   The test fails if the file moves or the paragraph changes, which is the drift it exists to
   catch. (CASE-0182)
4. No site anywhere in `Sources/` contains the string `verify against Sequoia`. (CASE-0183)
5. A session attached to a guest whose injected link answers `proctor_doctor` with
   `osVersion: "26.6.2"` gets `osVersion.version == "26.6.2"`, `source == "guest-agent"`, and no
   reason, from `action "status"` on that guest. (CASE-0184)
6. A stopped guest, a delegated guest, an unattached running guest and an attached guest whose link
   throws each yield `version == nil` with a distinct non-empty reason naming what would change it
   — four cases, four different reasons, asserted individually. (CASE-0185)
7. A session attached to guest A reading status on guest B gets B's not-attached reason and not A's
   version. (CASE-0186)
8. A guest named `macos-sequoia-cua` with a link answering `26.6.2` reports `26.6.2`; the same
   guest with no link reports `unknown`. The name is never the answer. (CASE-0187)
9. A status call whose link throws leaves the attachment intact: the session is still attached
   afterwards and its pool slot is still held. (CASE-0188)
10. `proctor_guest`'s input schema enumerates `tart` alongside `lume` and `prlctl`, no prose in the
    tool's description names a two-provider set, and the refusal a caller gets for a missing guest
    names all three. (CASE-0189)
11. `./scripts/test.sh` green, with the run count and its denominator stated, and the real exit
    code read from a file rather than through a pipe.
