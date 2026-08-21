# Plan — PRO-0094: one sourced note, and a guest that says which macOS it is

**Spec:** `docs/specs/spec-PRO-0094.md` · **Branch:** `ai/pro-0094` off `ai/wave-9`
**Tier:** Small. Five production files, two new test files, no new unit of architecture.
**Design stage:** skipped — no rendered surface changes. The three sites are a doctor lane note, an
MCP tool description and a JSON field; the reader is a model, not a person looking at a window.

## Ordering, and why the constant comes first

Phase 1 removes the second and third copies of a sentence before phase 2 adds a field next to it.
The reverse order gives the drift test something to pass against while three copies are still in
the tree, which is the failure mode the spec exists to close.

| Phase | Work |
|---|---|
| 1 | `GuestNotes` in `ProctorCore`; the three sites interpolate it |
| 2 | `GuestOSVersion` + its pure resolver in `ProctorCore`; `guestStatus` fills it from the link |
| 3 | The third provider on the tool surface: schema enum, prose, refusal text, field comments |
| 4 | The tests, and what arms each one |

## Phase 1 — one constant

`Sources/ProctorCore/GuestInventory.swift`, appended. It is the file that already owns "what a
guest is, decided purely", and this is a fact about guests rather than about the doctor.

```swift
public enum GuestNotes {
    /// PRO-0094. What is known about Tahoe guests and window rendering, held as
    /// the measurement rather than as prose, so the sentence cannot say one
    /// thing while the fields say another.
    public enum TahoeRendering {
        public static let upstream = "trycua/cua #870 and Apple FB21748086"
        public static let guestOS = "26.6.2"
        public static let measuredOn = "2026-08-21"
        public static let applications = ["Calculator", "System Settings", "Setup Assistant"]
        public static let citation = "docs/specs/spec-PRO-0076.md"
        public static let sentence = "..."   // composed from the five above
    }
    public static var tahoeRendering: String { TahoeRendering.sentence }
}
```

`sentence` is built by interpolating the other five — `applications` joined with commas and "and" —
so a field edited without the prose is impossible by construction and a prose edit that contradicts
a field is what CASE-0182 catches against the spec on disk.

Three call sites, each replacing its hand-written copy with `\(GuestNotes.tahoeRendering)`:

- `Sources/ProctorCore/ToolchainLanes.swift:161` — the guest lane's `note`.
- `Sources/ProctorCore/ToolCatalogue.swift:1173` — the `proctor_guest` tool description.
- `Sources/ProctorAgent/Session/SessionGuest.swift:134` — `guestCapabilities.note`.

`ToolCatalogue`'s description is a `"""` literal in a `static let`; Swift statics are lazily
initialised, so interpolating another `static let` from the same module is safe and needs no
ordering care. `SessionGuest` is in `ProctorAgent`, which already imports `ProctorCore`.

The words "verify against Sequoia" leave the tree entirely. What replaces them is a pointer to the
surface that answers the question — the doctor lane says where a guest's macOS version is reported,
and the tool description documents the new field. No site tells a reader to go and get a different
operating system, which is the rule; naming the surface that settles it is phase 2 being
discoverable rather than the old advice rephrased. *(Amended after the D-prime validator read the
original wording, "nothing replaces them", against the diff and called the contradiction.)*

## Phase 2 — `osVersion` on `proctor_guest --action status`

### The pure half, in `Sources/ProctorCore/GuestInventory.swift`

```swift
public struct GuestOSVersion: Codable, Sendable, Equatable {
    public var version: String?      // nil exactly when unknown
    public var source: String        // "guest-agent" when known, "unknown" otherwise
    public var reason: String?       // present exactly when version == nil
    public static func known(_ v: String) -> GuestOSVersion
    public static func unknown(reason: String) -> GuestOSVersion
}

public enum GuestOSVersionResolution {
    /// Why this guest cannot be asked, or nil when it can be.
    public static func obstacle(record: GuestRecord,
                                attachedByThisSession: Bool) -> String?
    /// The reason for a guest that should be answerable but whose agent did not.
    public static func silentAgent(name: String, said: String?) -> String
}
```

`obstacle` checks in this order, and the order is the finding rather than a tidying:

1. **platform is not `.macos`** → a delegated guest carries no Proctor to ask. First, because
   starting or attaching to it would not help, so a power-state reason would send the reader to do
   something that cannot work.
2. **not running** → it cannot be asked; no provider records a guest's macOS version, so start it
   and attach.
3. **not attached by this session** → there is no link to ask over; attach and read status again.

Each returns a distinct non-empty sentence naming what would change it. `obstacle` takes a
`GuestRecord` and a `Bool` and nothing else — no name, no image, no provider id — which is how
"never inferred from the image name" is checkable rather than asserted. It runs with none of
`lume`, `prlctl` or `tart` on the machine, the rule this file already sets for the lane.

`source` is a `String` rather than an enum, matching `GuestRecord.state`: a channel a later build
adds survives into an older reader's report instead of being flattened into the nearest case.

### The impure half, in `Sources/ProctorAgent/Session/SessionGuest.swift`

`guestStatus` (currently lines 138-146) gains one field and one helper:

```swift
private func guestStatus(guest: String, provider: String?) async throws -> JSONValue {
    let record = try await resolveGuest(guest, provider: provider)
    return .object([
        "guest": try JSONValue.encode(record),
        "machine": try JSONValue.encode(record.machine),
        "osVersion": try JSONValue.encode(await guestOSVersion(for: record)),
        "capabilities": Session.guestCapabilities
    ])
}
```

`guestOSVersion(for:)`:

- reads `guestAttachments[SessionIdentity.current.key]` and treats it as attached **only** when
  `slotHeld && provider == record.provider && name == record.name`. That triple is what makes
  CASE-0186 pass: a session attached to A asking about B is not attached *to B*.
- returns `.unknown(reason:)` on any obstacle, without touching the link.
- otherwise sends `AgentRequest(tool: "proctor_doctor", arguments: .object([:]))` over
  `guestLinks[key]` — the same request `SocketGuestLink.probe()` already sends, which actuates
  nothing — and reads `osVersion` out of the object it gets back.
- an empty or absent `osVersion`, a response carrying an `error`, or a thrown send all become
  `.unknown` with `silentAgent`.

**The failure path deliberately diverges from `forwardToGuestIfAttached`.** That function releases
the attachment and refuses when a send fails, because it is answering *for* the guest and a wrong
machine's verdict is the thing it exists to prevent. This one is a read *about* the guest: it
returns `unknown` and leaves the attachment and its pool slot exactly as they were. Calling
`releaseGuestAttachment` here would let a status poll evict a live run's slot. CASE-0188 is that
clause; without the divergence it is red.

No `guestVanishedError()` call either, for the same reason — it releases.

## Phase 3 — the third provider, on every surface a caller reads

| file:line | today | after |
|---|---|---|
| `Sources/ProctorCore/ToolCatalogue.swift:1205` | `enum: ["lume", "prlctl"]` | `["lume", "prlctl", "tart"]` |
| `Sources/ProctorCore/ToolCatalogue.swift:1124` | "reach through lume or prlctl" | names all three |
| `Sources/ProctorCore/ToolCatalogue.swift:1176` | "Requires lume, prlctl, or both." | "Requires lume, prlctl or tart — any one is enough." |
| `Sources/ProctorCore/ToolCatalogue.swift:1200` | "the name you type at lume or prlctl" | names all three |
| `Sources/ProctorAgent/Session/SessionGuest.swift:77` | refusal remedy names two | names all three |
| `Sources/ProctorCore/Wire.swift:704,706` | `Machine` field comments name two | name all three |

The enum is the load-bearing row. The other five are prose; a schema that omits a provider makes
the call fail validation at the client before any of this repo's code sees it, which is what the
reporting session actually hit.

## Phase 4 — the tests, and what arms each one

Two new files. Every case below fails at `HEAD` of `ai/pro-0094` before phase 1, and the reason it
fails is named — a clause whose red state I have not identified is a clause I cannot claim is
falsifiable.

### `Tests/ProctorCoreTests/GuestNoteSourceTests.swift`

Repo root from `#filePath` — three `deletingLastPathComponent()` calls, the pattern
`ToolchainShellFragmentTests.repositoryRoot` at `Tests/ProctorCoreTests/ToolchainTests.swift:432`
already uses. Never `currentDirectoryPath`, which `swift test` does not promise.

| case | assertion | why it is red today |
|---|---|---|
| CASE-0180 | `FB21748086`, `#870` and `render no application windows` each appear exactly once across every readable file under `Sources/` | three copies each |
| CASE-0181a | `Toolchain.lanes(...)`'s `guest` row note contains `GuestNotes.tahoeRendering` | `GuestNotes` does not exist |
| CASE-0181b | `ToolCatalogue.guest.description` contains `GuestNotes.tahoeRendering` | same |
| CASE-0182 | each of `26.6.2`, `2026-08-21`, `Calculator`, `System Settings`, `Setup Assistant` from the constant is found in the *measurement section* of `docs/specs/spec-PRO-0076.md`, located by an anchor the constant carries | same |
| CASE-0183 | `verify against Sequoia` appears zero times under `Sources/` | three today |

CASE-0180 and CASE-0183 walk `Sources/` with an enumerator and count over a list, not over printed
output. Before believing the zero in CASE-0183, the same walk is asserted to find a control string
that *is* present (`FB21748086`), so a walk that silently enumerated nothing cannot read as green.

### `Tests/ProctorAgentTests/GuestOSVersionWiringTests.swift`

Harness copied from `GuestAttachWiringTests.harness` (`Tests/ProctorAgentTests/GuestAttachWiringTests.swift:59-75`):
`FakeGuestProvider` + `FakeGuestLink` (same file, lines 14-47) through
`session.setGuestProviders` and `session.setGuestLinkFactory`. `FakeGuestLink.reply` is settable,
so the guest's answer is the fixture rather than anything production wrote.

| case | assertion | why it is red today |
|---|---|---|
| CASE-0181c | `Session.guestCapabilities`'s note contains `GuestNotes.tahoeRendering` | `GuestNotes` does not exist |
| CASE-0184 | attached, link replies `{"osVersion": "26.6.2", ...}` → `version == "26.6.2"`, `source == "guest-agent"`, `reason == nil` | `status` returns no `osVersion` field |
| CASE-0185 | stopped / delegated / running-unattached / attached-and-link-throws → four `nil` versions with four **distinct** non-empty reasons, compared pairwise so two branches returning one string is red | same |
| CASE-0186 | attached to A, `status` on B → B's not-attached reason, and `version == nil` | same |
| CASE-0187 | guest named `macos-sequoia-cua`: with a link answering `26.6.2` → `26.6.2`; with no link → `unknown`. The name never appears in the answer | same |
| CASE-0188 | after a `status` whose link throws, the session is still attached (a following forwarded call reaches the link) and `poolStatus()`'s macOS `held` count is unchanged, read rather than inferred | same |
| CASE-0189 | `ToolCatalogue.guest`'s `provider` enum contains `tart`; no string anywhere in its title, description or input schema names a two-provider set; `requireGuest(nil)`'s remedy names `tart` | enum is `["lume","prlctl"]` |

CASE-0185's fixture answers are supplied by the test, but the *reasons* are produced by
`GuestOSVersionResolution.obstacle`, which the test does not write — the assertion is that four
inputs yield four different production strings, and the distinctness is computed with a `Set` count
against `4`, not eyeballed.

CASE-0188's "still attached" is proved by an observable rather than by reading a field: a
subsequent forwarded tool call arrives at `FakeGuestLink.forwarded`. A session whose attachment was
released would refuse that call instead.

Whole-suite gate: `./scripts/test.sh`, exit code read from a file rather than through a pipe. The
run count and its denominator go in the completion record; "the suite is green" without a number is
not a claim this repo accepts.

Each case is also mutation-checked rather than assumed armed: a mutant is planted in production (or,
for the drift case, in the cited spec), the filtered suite is run, the kill is recorded, and the tree
is restored with `git checkout`. A case no mutant can kill has measured nothing.

## Scope-narrowing check

Every requirement in the spec is carried by a phase above: REQ-059 → phase 1, REQ-060 → phase 2,
REQ-060b → phase 3, and all ten cases → phase 4. The four triage assumptions each survive intact —
1 and 2 are phase 2's design, 3 is phase 1's deletion, 4 is `TahoeRendering.citation` appearing in
the sentence. Nothing in "What this does not change" overlaps a requirement. **No narrowing.**

DEF-094 was allocated by the work rather than invented for the row: the out-of-family critic found
that `guestOSVersion`'s link read is unbounded, so a frozen guest agent hangs a `status` call. It is
recorded in the spec and deliberately not fixed here, because the transport sets no receive timeout
at all and a deadline on this one read would leave every actuation path exactly as it is.

## Out of scope

No provisioning, starting, stopping, cloning, deleting, pruning, renaming or exporting of any
guest — `proctor-guest` and `anvil-mac-node` are stopped and are not touched. No SSH tunnel. No new
provider. No change to `GuestRecord`'s wire shape, to `list`, to attach, detach, or the pool. No
claim about trycua/cua #870, which stays open.
