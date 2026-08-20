# PRO-0013: Encryption-at-rest for the audit log

**ID:** PRO-0013
**Status:** Merged
**Created:** 2026-08-13
**Last updated:** 2026-08-14
**Plan:** [docs/plans/plan-PRO-0013.md](../plans/plan-PRO-0013.md)

## Feature description

# Encryption-at-rest for the JSONL audit log

**Status:** untriaged · **Value:** high (security) · **Effort:** med · **Source:** deferred child of PRO-0005 (scheduled 2026-08-13 via whats-left ingest)
<!-- Promoted from ORCHESTRATOR.md "Deferred children" on the reader's all-three answer. Was an explicit exclusion in the PRO-0005 spec. -->

## What it is
Encrypt the redacting JSONL audit log on disk, rather than writing it in plaintext.

## The gap
PRO-0005 redacts secrets from the audit trail but writes the result as plaintext JSONL. It was an explicit spec exclusion, not an oversight. The log records what the tool did to the machine, so on a shared or multi-user system it is exactly the file you would not want readable at rest.

## Scope
- In: encrypt the audit log at rest (key handling via Keychain or an equivalent macOS-native path); decrypt on read for the tools that consume it.
- Out: changing what is logged or how it is redacted; transport security (this is at-rest only).

## Success looks like
The audit log on disk is unreadable without the key, and the tools that read it still work.

## Dependencies / notes
- Parent: PRO-0005.
- Key management is the real design question — resolve it at triage/plan, not here. Keychain is the likely home.
- Pairs with the replay-gate child (12).

---

## Triage — 2026-08-14

**Sentinel review:** S2 — Block pending the one essential question below. (Governance-adjacent: this is the audit trail itself. No price-sensitive or investor-facing content, so not S3.) Everything else is settled as an assumption, so one answer takes this straight to Ready.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** the permission-and-trail tool an agent or operator calls *(behind the scenes — nothing visible changes in any app)*. Nothing customer-facing changes, no new screen, and no new tool or command. The Mac's own secure key store gains one stored key.
- **What users will see:** nothing on screen. Reading the trail through the tool returns the same entries in the same shape as today. Opening the trail file directly — with any ordinary text or log viewer — no longer shows readable text.
- **Behaviour changes:**
  - The trail on disk is unreadable to anyone who can read the file but cannot reach the key.
  - The trail you already have is converted the first time the tool runs, so once that succeeds nothing readable is left in the live file. *(the essential question below can change this.)*
  - If an entry cannot be sealed, nothing is written — never a readable entry — the action it was recording still goes ahead, and the tool's status says the trail is not being written.

**Assumptions**
- `[Compliance]` Each entry is scrambled on its own, so writing stays a single append at the end of the file *(rather than scrambling the whole file and rewriting it every time, which would break the append-only shape and concurrent writes)*
- `[Compliance]` Writing an entry never needs the protected key — an entry is sealed with a half that is not itself a secret — so an unattended run keeps recording even between a restart and the first time anyone unlocks the Mac. *(the trail must not go dark exactly when the tool is running alone, which is the case the parent feature exists for)*
- `[Compliance]` The unsealing half lives in the Mac's own secure key store, created on first use, bound to this Mac and this user account, never exported, backed up or synced, and needed only to read. *(reading is the attended operation; a key that never leaves the machine is what makes a copied file useless)*
- `[Compliance]` If an entry cannot be sealed, nothing is written — never written readable as a fallback. *(a readable fallback silently undoes the feature)*
- `[Operations]` A dropped entry never fails the action it was recording, and the tool's status reports that the trail is not being written. *(today a failed write is silent, so a trail that stopped would go unnoticed)*
- `[Data & scope]` A readable trail that already exists is converted in place before the first new entry of that run is written. *(leaving it readable beside a new scrambled one keeps the exposure the feature exists to remove)*
- `[Data & scope]` Conversion is all-or-nothing: if it cannot finish, the original is left exactly as it was, no new entries are appended to it, and the status reports the trail as unavailable. *(stops both a half-converted file and new entries landing readable)*
- `[Compliance]` Conversion clears the readable trail from the live file only; copies already taken by backups, snapshots or disk images are beyond its reach. *(honest boundary — an in-place rewrite cannot recall a copy)*
- `[Compliance]` What this protects against: the file copied off the machine, a backup, another account or another administrator. Not claimed: a program already running as this same user, which can reach the key exactly as the tool does. *(the file is already unreadable to other users today; naming the real boundary stops an over-claim)*
- `[Operations]` Reading the trail returns the same entries, in the same shape and order, so callers need no change — with one addition: an entry that cannot be unscrambled comes back as a marked unreadable placeholder instead of breaking the read. *(the brief's success test, plus one bad or older entry must not blind the whole trail)*
- `[Operations]` Where the trail lives and how many entries it holds are still reported, without needing the key. *(operators still need to find it and see it is growing)*
- `[Data & scope]` No new tool, command or screen is added for reading the trail; the existing read path stays the read path. *(scope: the brief asks for encryption, not a new reader)*
- `[Compliance]` The number of entries, their timing and their rough size stay visible to anyone with file access; hiding those is not claimed. *(the trade for keeping writes a single append)*
- `[Compliance]` Proving the trail is complete — detecting deleted or reordered entries — is not claimed. This hides content only. *(tamper-evidence is a different change; naming it stops a false reading of "secure log")*
- `[Data & scope]` Changing the key later, and re-scrambling an existing trail, are not in this pass; each entry records which key sealed it so a later change stays possible. *(not asked for, and cheap to leave the door open for)*
- `[Operations]` Scrambling and unscrambling are proved by the automated checks on their own; reaching the Mac's key store is proved by running the tool, not by those checks. *(the checks run with nobody present and no live key store)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0013` before the planner picks this up.*

**Essential Questions** *(one gap that is yours, not the code's)*

1. *[Compliance]* Losing the unsealing key — a new Mac, a key-store reset, a rebuilt account — makes the whole history permanently unreadable, and converting the trail you already have destroys its only readable copy the first time the tool runs. Which do you want?
   a) No recovery copy. Convert what exists in place, accept that a lost key means a lost history. *(recommended — strongest at rest, and nothing extra to keep safe)*
   b) No recovery copy, and leave the trail you already have exactly as it is; only new entries are scrambled. *(keeps today's history readable, and therefore still exposed)*
   c) Give the operator an exportable recovery key to store themselves. *(survives losing the machine, at the cost of a second secret to protect and a weaker guarantee against a stolen backup)*

*Easy reply — edit your answer under the question (or correct any assumption), then re-run `/triage PRO-0013`:*
> `1. a`

**ANSWERED 2026-08-14 by the reader: (a).** No recovery copy. Convert the existing
trail in place and accept that a lost unsealing key means a permanently unreadable
history. The reader chose this knowing the first run destroys the only readable copy
of the trail that exists today, and knowing a new Mac or a key-store reset ends
access to everything written before it. Do not add an export path, a second secret,
or a "just in case" plaintext copy: each of those is the guarantee this option was
chosen for, weakened. The destructive first run needs to be obvious in whatever
performs it, not silent.

**Resolution — folded in 2026-08-14, spec now Ready for Plan.** The answer becomes
binding scope, promoted here out of the question block so no later stage re-reads it
as open:

- `[Compliance]` The unsealing key exists in exactly one place, the Mac's own key
  store, non-exportable and not synced. There is **no** recovery key, no export
  command, no escrow file. Losing it is a permanent loss of the whole history, and
  that is the accepted trade. *(reader's answer (a))*
- `[Data & scope]` A readable trail found on disk is converted **in place** on the
  first run that can seal, and the readable content is gone from the live file when
  it succeeds. No plaintext copy — not `.bak`, not `.orig`, not a sidecar — survives
  that conversion. *(reader's answer (a); a fallback copy reinstates the exposure)*
- `[Operations]` The conversion is loud, not silent: the run that performs it says
  so on stderr and the trail's status carries the fact that a conversion happened,
  with how many entries it moved. *(reader's answer (a), final line)*
- Assumption "Conversion is all-or-nothing" above stands unchanged and governs
  failure: a conversion that cannot finish leaves the original byte-for-byte, appends
  nothing, and reports the trail unavailable.

**Out-of-family spec review:** lane failure, logged downgrade. The repo's out-of-family reviewer (grok-4.6 at `xhigh`, read-only — Codex is off per ORCHESTRATOR.md) was tried twice: the first attempt returned preamble and no verdict before its deadline, the second returned nothing. Per ORCHESTRATOR.md an empty response is a lane failure, so the gate fell back **in-family** to a strong-model one-shot review of the same prompt. Verdict: material defects, 6 findings, **all 6 accepted**, none rejected — a key that cannot be reached would have silently disabled the whole trail (today's write failure is not surfaced anywhere); the conversion-failure state was undefined and contradicted the "nothing readable left behind" line; that line over-claimed against backups and snapshots; the stated threat was already closed by the file's existing permissions, so the real boundary needed naming; "reported" had no channel and the unreadable-entry marker contradicted "same shape"; and the automated checks cannot reach the key store. Each is now an assumption above. The next reader should know this gate was in-family, which is weaker evidence than the out-of-family one it replaced.

**Assumptions review gate:** a separate reviewer flagged 2 of 18 defaults. One was fixed rather than raised: requiring the protected key to write meant the trail of an unattended agent would go dark for a whole session after a restart, so writing no longer needs it — the key is needed only to read, which is the attended half. The other is the Essential Question above; it is a risk-tolerance call that destroys an existing readable history on first run, which is not a default triage should pick silently.

**Grounding note:** the pipeline is running Swift-adapted for this repo — the acceptance gate is `swift build` + `swift test`; the web design and end-to-end stages do not apply. The trail, its redaction and its reader all exist today and this change sits behind them.

---

## Progress — 2026-08-14 (ship-feature runner, PRO-0013)

**Branch:** `ai/pro-0013` · **Worktree:** `.worktrees/PRO-0013` (from local HEAD `101511b`)
**Status:** In Review, ready to merge. STOPPED BEFORE MERGE per the fleet rule.
**Gate:** `swift build` clean; `swift test` **183 tests in 25 suites passed** (173/24 at HEAD, +10 tests, +1 suite).

Built: `ProctorCore/AuditSeal.swift` (pure, unit-tested) seals each line with a fresh
ephemeral X25519 pair, HKDF-SHA256 and AES-GCM, header AAD-bound, one JSON line out.
`ProctorAgent/Session/AuditKeyStore.swift` holds the private key in the login keychain
(`WhenUnlockedThisDeviceOnly`, non-synchronizable, no export path anywhere) and caches
the public half beside the log so writing never needs the keychain. `AuditLog` seals or
drops with no plaintext path, converts an existing readable trail in place once per run
(all-or-nothing, atomic replace, no backup copy, loud on stderr), and reports
`auditWritable` / `auditDropped` / `auditKeyId` / `auditKeyMismatch` / `auditConverted`.
The reader returns the same records in the same order, with a marked placeholder for an
entry it cannot open.

| Acceptance clause | Proof |
|---|---|
| Sealed on disk, unreadable without the key | `sealHidesTheRecordText`, `wrongKeyCannotOpen` |
| The same records come back | `sealRoundTripsTheLine`, `trailRoundTripsInOrder` |
| One bad entry costs one entry | `openReturnsNilOnGarbage`, `trailRoundTripsInOrder` |
| Tamper is detected, not decoded | `tamperingFailsToOpen` |
| Still one JSONL line, still append-only | `sealedLineIsSingleLineJSON`, `eachEntryIsSealedIndependently` |
| Which key sealed it is recorded | `keyIdIsStableAndDistinguishes` |
| A readable trail is recognised for conversion | `isSealedDiscriminatesPlaintextRecords` |
| A dropped entry never fails the action | all 7 `AuditLog.append` call sites still discard the result and none throws |
| Key store bound to this Mac, no recovery copy | build-verified; the spec records that automated checks cannot reach the keychain |

**Gates.** Plan review: grok lane FAILED twice (empty response, exit 0), logged downgrade
to in-family; verdict DEFECTS (6), all 6 accepted and fixed, recorded in the plan.
Completeness critic: grok answered, 5 items raised, all 5 verified as covered in code
(elisions in the critic's brief, not gaps); one, order preservation on read, gained a
test rather than an argument.

**Deferred / discovered.** `proctor_doctor` has no `policy` block, so the audit state is
visible through `proctor_policy status` only; PRO-0005's plan called for one and it is not
in the tree. Left alone as PRO-0005's scope. Entry authenticity (a forged append cannot be
detected, because sealing needs only the public key) is now stated as a non-goal in the
code and the plan; signing is a separate change.
