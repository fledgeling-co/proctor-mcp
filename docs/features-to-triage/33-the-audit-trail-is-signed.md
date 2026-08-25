---
sources: [REQ-015]
status: retired
validated-by: REQ-015 via CASE-0017, CASE-0061
validated-rungs: effect-witness, outcome
validated-provider: data.write(to:options:.atomic) in Sources/ProctorAgent/Session/PolicyStore.swift; key material in Sources/ProctorAgent/Session/AuditKeyStore.swift
---
# The audit trail is signed, and it records what Proctor recommended

## The problem

Two gaps in the audit trail, from two features.

**Sealed is not signed.** PRO-0013 encrypted the audit log at rest with X25519 +
HKDF + AES-GCM. Sealing needs only the public key, so anybody who can read the
file can also append a well-formed entry that decrypts correctly. The spec, the
plan and the changelog all now state this as a non-goal rather than implying a
guarantee, which was the right immediate answer. It is still a trail that cannot
detect a forged append.

**The lane recommendation is not recorded.** PRO-0020 and PRO-0024 hand a browser
page to Obscura or to browser-use. Nothing either tool then does reaches the audit
trail, which those specs disclose on the wire. But the recommendation itself is
Proctor's own act: it is the moment Proctor told a model to go and drive something
outside its own accounting, and there is no record that it happened.

## What it should do

Make an appended entry detectably forged, and record the recommendation as an
auditable act.

## The hard parts, named

- **Signing needs a private key in the agent, which sealing deliberately avoided.**
  PRO-0013 chose sealing precisely because the write path needs only a public key.
  Adding a signing key changes what an attacker who compromises the agent gets.
  Say what the key protects against and what it does not: an agent that can sign
  can also sign a lie it was told to write.
- **Per-entry signature or a chain.** A signature per entry detects a forged entry
  and not a deleted one. A hash chain detects deletion and truncation but has to
  survive rotation and the existing plaintext-to-sealed conversion, which PRO-0013
  performs in place. Choose and defend.
- **The recovery decision from PRO-0013 stands and must not be softened.** A lost
  key means a permanently unreadable history, chosen deliberately over an export
  path. Do not add a second secret, an export, or a plaintext fallback here: those
  are exactly what that decision refused.
- **The recommendation entry must not become a second copy of the handoff object.**
  Record that Proctor recommended a lane, which lane, and which rule drove it.
  A URL in an audit entry is a person's browsing history in a file Proctor keeps.
  Decide what is recorded about the target, and default to less.
