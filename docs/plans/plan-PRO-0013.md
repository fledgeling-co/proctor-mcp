# Plan — PRO-0013: Encryption-at-rest for the audit log

**Spec:** docs/specs/spec-PRO-0013.md · **Branch:** ai/pro-0013 · **Tier:** Standard
**Gate:** `swift build` + `swift test` from the worktree root.
**Parent:** PRO-0005 (which built the trail this seals).

## Shape

The repo's standing split, followed exactly: the cryptography and the on-disk line
format are **pure and unit-tested** in `ProctorCore` next to `Policy.swift`; the key
store, the migration and the status wiring are thin, stateful and **build-verified**
in `ProctorAgent`, because they reach a Keychain no test runner has. Nothing about
what is logged or how it is redacted changes; `AuditRecord.jsonLine()` stays the
input, and sealing wraps it.

The one design decision that everything else follows from is the reader's assumption
that **writing must not need the protected key**: an unattended agent has to keep
recording between a restart and the first unlock. So the scheme is asymmetric —
sealing takes a public key that is not a secret and lives in a file next to the log,
opening takes a private key that never leaves the Mac's key store.

## ProctorCore — `Sources/ProctorCore/AuditSeal.swift` (pure, unit-tested)

Sealed-box-per-line over X25519 + HKDF-SHA256 + AES-GCM, all CryptoKit (already a
dependency of `Policy.swift`).

- `AuditSeal.keyId(for: Curve25519.KeyAgreement.PublicKey) -> String` — first 16 hex
  of SHA-256 over the raw public key. Recorded on every line, so a later key change
  stays possible (spec assumption) and a line sealed to a different key is detected
  rather than mis-decrypted.
- `AuditSeal.seal(line:to:) -> String?` — fresh ephemeral X25519 pair per line,
  agreement with the recipient public key, `HKDF<SHA256>` to a 32-byte
  `SymmetricKey` (salt `proctor-audit-seal-v1`, info = kid ‖ ephemeral public), then
  `AES.GCM.seal` with the line's UTF-8 as plaintext and the header as **authenticated
  data**, so a swapped `kid`/`epk` fails to open rather than silently decoding.
  Output is one compact sorted-key JSON object and never contains a newline:
  `{"ct":"<b64 combined>","epk":"<b64>","kid":"<hex>","v":1}`.
- `AuditSeal.open(_:with: Curve25519.KeyAgreement.PrivateKey) -> String?` — nil on a
  malformed line, a wrong `kid`, a failed tag, or a version it does not know. Never
  throws into the read path.
- `AuditSeal.isSealed(_ line: String) -> Bool` — the migration's and the reader's
  discriminator: a JSON object carrying `v`, `kid`, `epk` and `ct`. A plaintext
  `AuditRecord` line carries none of them.
- Ephemeral-per-line is what keeps the file append-only: no shared nonce counter to
  coordinate, so two concurrent appends can never reuse one. The cost — a 32-byte
  ephemeral key per line — is the trade the spec already accepted when it chose
  per-entry sealing over whole-file encryption.

## ProctorAgent — `Sources/ProctorAgent/Session/AuditKeyStore.swift` (build-verified)

- Private key: a Keychain **generic password**, service
  `app.fledgeling.procter.audit`, account `audit-x25519-v1`, value the 32 raw bytes,
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and non-synchronizable — bound to
  this Mac and this login, never exported, never backed up or synced (spec
  assumption). No export path exists anywhere in the code (reader's answer (a)).
- Public key: cached at `.../audit/audit.pub` (raw 32 bytes, 0600, directory 0700).
  **The write path reads only this file** and so needs no Keychain and no unlock.
  Bootstrap — creating the Keychain item and writing the cache — happens on first use
  and is the only write-path operation that can touch the key store.
- `publicKey()` / `privateKey()` return optionals; both are lock-guarded in a
  `final class ... @unchecked Sendable` with an `NSLock`, the house pattern
  (`UnlockCoordinator`, `AXQuietTracker`, `Server`).

## ProctorAgent — `PolicyStore.swift`: sealing, migration, fail-closed writes

`AuditLog` keeps its `url`, `directory`, `lineCount()` — both of the latter work with
no key, which is what keeps "where it lives and how big it is" answerable to an
operator who cannot read it.

- **State** moves into a lock-guarded `final class AuditLogState: @unchecked Sendable`
  behind `AuditLog.state`: `migrationDone`, `lastError: String?`, `convertedCount`,
  `unavailable: Bool`.
- `append(_:)` — ensure migration has run, fetch the public key, seal, append the
  sealed line plus `\n` with the existing single-`write(2)` append. **If any of those
  fails, nothing is written**: no plaintext fallback anywhere, `lastError` is set, and
  the function returns `false` as it does today, so the action it was recording still
  goes ahead (spec assumption: a dropped entry never fails the action).
- `migrateIfNeeded()` — once per process, before the first append. If the file holds
  any non-sealed non-empty line, seal every one of them (already-sealed lines are
  copied through untouched), write the whole result to `audit.jsonl.converting` in the
  same directory at 0600, then `FileManager.replaceItemAt` for an atomic swap. On any
  failure: remove the temp, leave the original byte-for-byte, set `unavailable`, and
  refuse every append for the rest of the run — the all-or-nothing rule, which is what
  stops a half-converted file and stops new entries landing in a readable one.
  **No `.bak`, no `.orig`, no sidecar**: the conversion removes the only readable copy
  and that is the reader's chosen trade.
- **Loud, not silent** (the reader's final line): a successful conversion writes one
  `proctor-agent: audit trail converted to encrypted-at-rest ...` line to stderr
  naming the entry count and stating the plaintext is gone, and the count is carried
  in status for the rest of the run. A failed conversion writes its own stderr line
  saying the trail is unavailable and why.
- `tail(_:)` keeps returning stored lines; a new `openedTail(_:)` opens each with the
  private key, mapping an unopenable line to `nil` for the caller to mark.

## ProctorAgent — `SessionPolicy.swift`: status and the reader

- `policyStatus()` gains `auditEncrypted: true`, `auditKeyId`, `auditWritable`
  (false whenever `lastError`/`unavailable` is set — today a failed write is silent,
  which is what one of the accepted spec-review findings was about), `auditError` when
  there is one, and `auditConverted` when this run performed the conversion.
- `auditTail(limit:)` returns the same records in the same shape and order as today.
  A line that cannot be opened becomes a marked placeholder object
  `{"unreadable": true, "reason": "...", "kid": "..."}` rather than breaking the read
  or blinding the whole trail, and the response carries `auditEncrypted` plus an
  `unreadable` count.
- `ToolOutputSchemas` gains the new key names (the object is already open, so this is
  discoverability, not validation); `ToolCatalogue`'s `proctor_policy` description
  gains a sentence saying the trail is encrypted at rest, that reading needs the
  machine's key store, and that a lost key is a permanently unreadable history.

## Not in this pass (spec-stated non-goals, restated so they are not drifted into)

Key rotation and re-sealing an existing trail (the `kid` on every line leaves the door
open); tamper-evidence / completeness proof; hiding entry count, timing or size; any
new tool, command or reader; transport security; and — binding, from the reader's
answer — any recovery key, escrow, export or plaintext fallback copy.

## Tests — `Tests/ProctorCoreTests/ProctorCoreTests.swift`, suite `AuditSeal`

Pure-crypto only; the Keychain is out of reach of a test runner (spec assumption), so
key-store behaviour is proved by running the tool, not here. One clause per test:

| # | Acceptance clause | Test |
|---|---|---|
| 1 | Sealed on disk, unreadable without the key | `sealHidesTheRecordText` — the sealed line contains none of the record's plaintext, and is not the input |
| 2 | Round-trips exactly | `sealRoundTripsTheLine` — `open(seal(x)) == x`, including a redacted `AuditRecord.jsonLine()` |
| 3 | Wrong key cannot read | `wrongKeyCannotOpen` — a different private key returns nil |
| 4 | Tamper is detected, not decoded | `tamperedCiphertextFailsToOpen` and `swappedHeaderFailsToOpen` (AAD binding) |
| 5 | Stays one JSONL line | `sealedLineIsSingleLineJSON` — no newline, parses as an object, survives a multi-line input |
| 6 | Each line is independently sealed | `twoSealsOfTheSameLineDiffer` — distinct `epk`/`ct`, both open |
| 7 | Which key sealed it is recorded | `keyIdIsStableAndDistinguishes` |
| 8 | Plaintext vs sealed is decidable (the migration's discriminator) | `isSealedDiscriminatesPlaintextRecords` |
| 9 | A bad line never throws into the read path | `openReturnsNilOnGarbage` |

Plus the existing 173 tests stay green.

## Plan-review gate — 2026-08-14

**Out-of-family lane: FAILED, logged downgrade.** Per ORCHESTRATOR.md the reviewer is
grok-4.6 at `xhigh`, read-only (Codex is off for this repo). Two attempts, one with
the full plan inlined and one with a compressed design summary, both returned an
empty response and exit 0. An empty response is a lane failure, not a pass, so the
gate fell back **in-family** (`claude --model claude-fable-5`, reading the three
changed source files directly). This matches the triage-stage result for the same
item, which also failed grok twice. The next reader should treat this gate as
in-family, which is weaker evidence than the out-of-family one it replaced.

**Verdict: DEFECTS (6). All 6 accepted and fixed; none rejected.**

| # | Sev | Finding | Fix landed |
|---|-----|---------|-----------|
| 1 | High | `try? String(contentsOf:)` conflated "no file" with "unreadable file", so a read error skipped the conversion, marked migration done, and appended sealed lines to a trail that might still hold readable ones | `fileExists` first; a file that exists but cannot be read is now a conversion failure, which marks the trail unavailable |
| 2 | Med | `FileHandle` + `seekToEnd` is not `O_APPEND`, so two writers can seek to one offset and overwrite each other, contradicting the "single write(2)" claim | append opens `O_WRONLY \| O_APPEND \| O_CREAT` and writes through the fd |
| 3 | Med | the migration reads then replaces under an in-process lock only, so a line appended by another process in between is discarded by the swap | both the migration and every append run under a `flock` on a sidecar `audit.lock` (sidecar because the conversion replaces the trail's inode) |
| 4 | Med | `clearError()` on the next success erased the only record that earlier entries were dropped, so status read clean after a silent loss | `State.dropped` is monotonic and surfaces as `auditDropped`; only the current error clears |
| 5 | Med | `audit.pub` was trusted unconditionally, so a replaced or desynced file would seal every future entry to a key nobody holds while every write reported success | the attended read path compares the cached public key against the Keychain key and reports `auditKeyMismatch` |
| 6 | Low | the threat-model comment disclosed deletion and reordering but not insertion, and forged appends are undetectable because sealing needs only the public key | the header comment now states authenticity is not claimed and says why, and it is added to the non-goals above |

**Non-goal added by finding 6:** entry authenticity. Anyone who can write the audit
directory can append a well-formed entry that opens cleanly, because sealing needs
only the public key that must sit there for unattended writing to work. Signing each
entry would close it and is a separate change.
