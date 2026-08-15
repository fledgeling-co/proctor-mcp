# Implementation plan — PRO-0032: The audit trail is signed, and it records what Proctor recommended

**Spec:** `docs/specs/spec-PRO-0032.md` · **Plan size:** Standard
**Branch:** `ai/pro-0032` · **Worktree:** `.worktrees/PRO-0032`
**Gate:** `swift build` + `swift test` (no web, design or e2e stages in this repo)

## Intent, in one paragraph

Two things. Make a forged, deleted, reordered, truncated or rolled-back audit entry
detectable, by chaining each sealed line to the one before it and signing that link with a
key held in the Mac's secure element — a key that cannot be copied off the machine, which
is what makes the claim true rather than nearly true. And record that Proctor recommended
a browsing lane, carrying the decision's own inputs (tool, browser, lane, rule, URL scheme)
and nothing that would turn the trail into a browsing history.

## What exists today (verified, not assumed)

| Thing | Where | What it does |
|---|---|---|
| Seal construction | `Sources/ProctorCore/AuditSeal.swift` | Per-line X25519+HKDF+AES-GCM. `SealedLine{v,kid,epk,ct}`. `isSealed` decodes that struct; `open` requires `v == version` and binds `kid`/`epk` as AAD. |
| Trail I/O | `Sources/ProctorAgent/Session/PolicyStore.swift` (`enum AuditLog`) | `append` under `withAuditFileLock` (an `flock` on a sidecar `audit.lock`), `appendRawLocked` via `O_APPEND`, one-time plaintext conversion, `tail`/`openedTail`/`lineCount`/`status`. Process-wide `State` behind an `NSLock`. |
| Key store | `Sources/ProctorAgent/Session/AuditKeyStore.swift` | X25519 private key in the login keychain; public half cached at `audit.pub`. |
| Record shape | `Sources/ProctorCore/Policy.swift` (`AuditRecord`) | `jsonLine()` — compact, sorted keys. `Redaction` = len+sha256. |
| Trail surfaces | `Sources/ProctorAgent/Session/SessionPolicy.swift` | `policyStatus()` and `auditTail(limit:)` build the operator-facing objects; `auditSink` is the injectable write seam (`setAuditSink`). |
| Handoff decision | `Sources/ProctorCore/BrowserTarget.swift` | `decide(for:probe:lanes:) -> Decision{lane,why,url,urlUnavailable,toolUnavailable}`; `handoff(...)` builds the wire object. `why` is one of a small fixed set of sentences. |
| Handoff emission | `Sources/ProctorAgent/Session/Session.swift:479` and `:495` | The only two funnels; five call sites (`listApps`, attach, `snapshot`, find, `SessionAct.swift:128`) all go through them. |
| Test interlock | `AuditLog.isTestProcess` | Redirects a test process's trail into `NSTemporaryDirectory()`. **Verified firing** under `swiftpm-testing-helper` on 2026-08-15, with the live trail's checksum unchanged across a real run. |

Two facts that shape the design, both measured on this machine rather than assumed:
`SecureEnclave.isAvailable` is true; a SEP key persists as a 284-byte opaque blob, re-creates
in a later process without a prompt, signs in 4.6 ms and verifies with its public half alone;
a keychain item update costs 12.9 ms and a read 1.66 ms.

## Design

Everything in this section is written to one rule the plan review forced: **every byte that
is hashed or signed is defined exactly once, and the writer and the verifier read the same
definition.** The review's finding was that "hash the previous line" and "sign the line's
JSON" are not specifications — newline handling, hex case, key order, whitespace and
duplicate keys all differ between two honest implementations, and the failure mode is
`signatureInvalid` on honest entries or a silent pass on edited ones.

### The exact definitions

- **A record's bytes** are the exact bytes of that line as they sit on disk, **excluding**
  the terminating `\n`.
- **`prev`** is the lowercase hex SHA-256 of the previous record's bytes.
- **Genesis** — the first chained record in a trail — sets `prev` to the lowercase hex
  SHA-256 of the **entire file prefix that precedes it, newlines included, exactly as it sits
  on disk**. That pins the pre-chain history. An empty prefix hashes as SHA-256 of no bytes.
  Genesis is identified, at write, as "no chained record exists yet", and at verify as the
  record at index `preChainCount`; with no anchor, as the first record carrying chain fields.
  The two procedures are written against each other in one file so they cannot drift.
- **The signed material** is a **length-prefixed concatenation of values, never a
  re-serialised JSON document**:

  ```
  "proctor-audit-chain-v1"
    ‖ u32(v) ‖ lp(tid) ‖ prev-as-32-raw-bytes ‖ lp(skid) ‖ lp(cls)
    ‖ lp(kid) ‖ lp(epk) ‖ lp(ct)
  ```

  where `lp(x)` is a 4-byte big-endian length followed by the UTF-8 or raw bytes. No
  canonicalisation problem exists because no JSON is signed: the components are the values
  the writer already holds. Extra keys, reordered keys or whitespace in the raw line
  therefore do not change the signature — they change the record's *bytes*, which breaks the
  **next** record's `prev`, which is where the chain catches them.
- **`sig`** is base64 of the 64-byte P1363 form (`rawRepresentation`), and a signature whose
  raw form is not exactly 64 bytes is a fault.

**High-s signatures are accepted, and this is a measured decision against the review's
advice.** The review asked for canonical low-s to close ECDSA malleability. Measured here:
99 of 200 secure-element signatures and 97 of 200 software signatures are high-s, and
CryptoKit verifies an s-flipped signature happily — so rejecting high-s would reject roughly
half of all honest entries. Malleability is instead closed by the construction already in
place: flipping `s` changes the record's bytes, which breaks the next record's `prev`. The
only record where it changes nothing is one written since the last anchor update, and a
malleated signature there alters no field anybody reads.

### The line format — additive, so nothing already on disk changes meaning

`SealedLine` gains five **optional** fields: `prev`, `tid`, `skid`, `cls` (`"se"` secure
element / `"sw"` software), `sig`. `AuditSeal.version` stays `1` and the sealed box is
untouched, so every already-sealed line on the reader's machine keeps opening and `isSealed`
keeps discriminating. Lines with no chain fields are pre-chain.

**`cls` is never trusted from the line.** It is derived from how the key is actually stored,
and at verify it is compared with the machine's own signer class — a line claiming `se` on a
machine whose key is software is a fault, not a stronger entry.

### The anchor lives in the keychain, not beside the trail

`{tid, count, head, skid, preChainCount}`, written under the same `flock` as the append.
On disk it would be restorable together with the trail, which is a free rollback. `head` is
the hash of the record at position `count`; `preChainCount` is frozen at genesis and is what
stops the downgrade where an attacker strips every chained line and the remainder reads as an
ordinary legacy trail.

### Writing, in the order that survives a crash

Inside the existing lock, after the seal succeeds:

1. **Find the previous record properly.** Scan backwards from the end in growing chunks
   until a complete record is in hand — never a fixed window, because one sealed line can
   exceed any window and hashing a mid-line suffix would break the chain permanently.
2. **A file not ending in `\n` is a torn final write.** Terminate it with a newline first and
   treat the torn fragment as the previous record for hashing. The damage is then recorded
   permanently in the chain and reported as `tornFinalEntry`, rather than being fused with the
   next record's bytes and hidden.
3. Build the chain fields and sign. **A signature that cannot be made drops the entry** —
   no line is written and the existing `auditWritable` / `auditError` / `auditDropped` state
   carries it. There is no unsigned path out of `append`.
4. Append the record, **`fsync` the descriptor**, then update the anchor. The fsync is what
   stops the ordinary case — a keychain item the OS has flushed, against trail bytes it has
   not — from reading as "entries missing from the end".

### Verifying, stated so that neither honest state is accused

Walk the records; for each chained one check the link, the trail id, the signer id, the class
and the signature. Then place the anchor:

- The record at `count` must hash to `head`. Everything up to there is **anchored**.
- Records past it must chain from that record: that suffix is reported as
  `unanchoredTail(n)` — normal growth after a crash — and it is still fully
  signature-checked, so its contents cannot differ, only its existence.
- The trail **behind** its anchor by exactly one record, with everything else intact, is
  `lostFinalEntry` — a crash between the fsync and the anchor write — not an accusation.
  Behind it by more, or `head` not found at `count`, is `missingFromEnd`.
- **No anchor at all is `notProvable`, never clean.** An anchor present with `count > 0`
  against a file whose records carry no chain fields is a fault, not a legacy trail.
- Every record at index ≥ `preChainCount` must be chained, or it is
  `unchainedAfterChainStart`.

**A record signed by a key this machine does not hold is a fault (`keyNotHeld`), not a
flag.** Otherwise anything with write access to the file could append entries under its own
key and read as clean apart from a boolean callers would ignore. `keyConfirmed: false` is
reserved for the different case where the key store could not be reached at all, and it
means "internally consistent, unconfirmed" — never clean.

### New files

- `Sources/ProctorCore/AuditChain.swift` — **pure**. The definitions above, `AuditAnchor`,
  and `AuditChain.verify(records:anchor:expected:)` returning the verdict. Signature
  verification arrives as a closure, so tests drive it with software P-256 keys made
  in-process and it never reaches a key store.
- `Sources/ProctorAgent/Session/AuditSigningKeyStore.swift` — the secure-element key
  (falling back to a software key where there is no secure element, and reporting its own
  class), the anchor item, and no export path anywhere, matching `AuditKeyStore`'s terms.

### The verdict

```swift
public struct AuditVerdict: Codable, Sendable, Equatable {
    public var total: Int
    public var verified: Int
    public var preChain: Int
    public var faults: [AuditFault]        // first is what the surfaces lead with
    public var completeness: Completeness  // proven | unanchoredTail(Int) | lostFinalEntry
                                           // | missingFromEnd(Int) | notProvable(String)
    public var keyConfirmed: Bool
}
```

`AuditFault.Kind`: `signatureInvalid`, `unsigned`, `linkBroken`, `fork`, `wrongTrail`,
`keyNotHeld`, `wrongKeyClass`, `unchainedAfterChainStart`, `tornFinalEntry`,
`malformedSignature`. Each carries its 1-based position. `keyNotHeld` is deliberately
separate from `signatureInvalid`: a reset key store is not an accusation of forgery.


### Recording the recommendation

`BrowserTarget.Decision` gains `rule: BrowserLaneRule?` — a small `String`-raw-valued enum
(`internalScheme`, `default`) set beside the existing `why` sentence, so the trail gets a
token and PRO-0024's wire text is untouched. `AuditRecord` gains
`recommendation: LaneRecommendation?` (`{lane, rule, scheme}`) and the `outcome` vocabulary
gains `"recommended"`, which is what makes an advisory distinguishable from an actuation.

Both `Session.browserHandoff` funnels call one private `recordRecommendation(_:bundleId:)`
after building the handoff. It returns early unless `handoff.use` is non-nil, derives the
scheme with `URL(string:)?.scheme?.lowercased()` and **never touches any other component of
the URL**, and de-duplicates against a `Set<String>` on `Session` keyed by
`bundleId|lane|rule|scheme`. It writes through `auditSink`, so the entry is sealed, chained
and signed like everything else, and a failure is discarded exactly as every other append is.

### Surfaces

`policyStatus()` and `auditTail(limit:)` gain `auditVerdict` (the encoded verdict) and
`ToolOutputSchemas` documents it under `proctor_policy`. No new verb, no new tool, no
status-window change.

## Steps

1. `AuditChain.swift` — fields, signed material, anchor, verdict, `verify`. Pure; unit tests
   first (clauses 1-9, 11).
2. `AuditSeal.SealedLine` — the five optional fields, plus a `chainFieldsRemoved` helper the
   signed-material builder uses. Assert every existing seal test still passes unchanged.
3. `AuditSigningKeyStore.swift` — SEP key with software fallback, anchor read/write, no
   export.
4. `AuditLog` — the write path above, `verify()`, and the injection seams (`setSigner`,
   `setAnchorStore`, and a trail-location override) so a suite can drive it without a key
   store and without the operator's trail.
5. `Policy.swift` — `LaneRecommendation`, the `recommendation` field, `"recommended"`.
6. `BrowserTarget.swift` — `BrowserLaneRule` on `Decision` only. No wire change.
7. `Session.swift` — `recordRecommendation`, the dedup set, calls in both funnels.
8. `SessionPolicy.swift` + `ToolOutputSchemas.swift` — `auditVerdict` and its schema.
9. `CHANGELOG.md` `## [Unreleased]` only, prose through `/create-luke-content` (marketing).

## Testing

`Tests/ProctorCoreTests/AuditChainTests.swift` — the chain and verdict, on files in
per-test `temporaryDirectory/audit-chain-<UUID>` directories (the house idiom at
`ProctorCoreTests.swift:1870`), with software P-256 keys made in-process. Covers forgery,
deletion, reorder, fork, edit, splice, truncation, rollback, pre-chain pinning, key change,
unconfirmed key, torn tail.

`Tests/ProctorAgentTests/AuditChainWiringTests.swift`, `@Suite(.serialized)` — `AuditLog`'s
write path against an injected signer, anchor store and trail location: the no-unsigned-entry
rule, the crash-ordering case, two writers under the lock, and the recommendation clauses
(14-20) driven through a `Session` with an injected `auditSink`.

**The live-data rule.** No test writes to
`~/Library/Application Support/app.fledgeling.procter/audit`. The interlock is verified
firing before the suite runs, every new suite injects its own trail location, and **no test
touches the keychain or the secure element** — the key store is exercised by running the
agent, not by `swift test`.

## Out of scope

Key rotation and re-signing an existing trail (the door is open via `skid`; walking through
it is a separate change). Any change to the one-time plaintext conversion. Any change to
PRO-0024's handoff wire text, including its line about the second lane and the audit trail,
which stays true. A `proctor_doctor` policy block. A status-window surface for the verdict.
Any new tool verb. Pinning the trail to a non-synced volume.

**Scope-narrowing check:** every triage assumption is carried by a step above; nothing in
the spec's clause list or assumption block is excluded here. The out-of-scope lines are the
spec's own "child work found" items, not requirements dropped from it.

## Plan review gate

**Mechanical path check:** every backticked path in this plan was checked against the tree;
all eleven existing paths resolve, and the four marked new are the only missing ones.

**Out of family, on grok-4.6** (`--effort xhigh --sandbox read-only`), 2026-08-15, no
downgrade. The prompt carried the construction only — no key-handling code was transmitted,
per the egress rule. Ten defects, **eight accepted and folded in above**, one answered with a
measurement, one rejected against a prior decision:

1. **Genesis was specified one way and written another.** The whole-file genesis hash and the
   last-record procedure would have disagreed, so an honest verifier would either accuse a
   correct genesis or wave through a rewritten pre-chain history. Genesis is now one
   definition, identified the same way at both ends.
2. **The signed material was not a byte string.** "The line's JSON with fields removed" leaves
   key order, whitespace, escaping and duplicate keys undefined — honest writers and verifiers
   would disagree. Replaced with a length-prefixed concatenation of values, so no JSON is
   signed at all.
3. **The crash window was either a false alarm or a free mutation slot.** The verifier now
   requires the record at `count` to hash to `head` and the suffix to chain from it, and
   reports that suffix as an unanchored tail rather than as growth it does not check.
4. **The anchor was durable while the trail was not**, so an ordinary crash would report
   entries missing from the end. The trail is fsynced before the anchor is written, and being
   behind by exactly one record is its own state rather than an accusation.
5. **A fixed-size tail read is not a last-record read.** One sealed record can exceed any
   window, and a file with no trailing newline would fuse a torn fragment into the next
   record. Backward scanning until a complete record, and an explicit torn-tail rule.
6. **An unconfirmed key was a boolean rather than a fault**, so anything with write access
   could append under its own key and read as clean apart from a flag. A record signed by a key
   this machine does not hold is now a fault.
7. **Unsigned and pre-chain were the same shape on disk.** Resolved by freezing
   `preChainCount` in the anchor: no anchor is `notProvable` and never clean, and an
   all-unsigned file with a populated anchor is a fault.
8. **`cls` was self-reported**, so a software signer could claim the secure element. It is
   derived from the store and checked at verify.

**Answered with a measurement rather than adopted:** canonical low-s signatures. Measured on
this machine, 99 of 200 secure-element signatures and 97 of 200 software signatures are
high-s, and CryptoKit verifies an s-flipped signature — so rejecting high-s would reject
roughly half of all honest entries. Malleability is closed by the chain instead, as set out
above.

**Rejected, with the reason:** that a signing failure should fail the caller rather than drop
the entry. PRO-0013 settled that a dropped entry never fails the action it was recording, and
that answer is authoritative; what this change adds is that a stopped trail is now visible in
the verdict as well as in the status.
