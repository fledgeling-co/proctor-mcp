# PRO-0032: The audit trail is signed, and it records what Proctor recommended

**ID:** PRO-0032
**Status:** Ready for Work
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Plan:** docs/plans/plan-PRO-0032.md
**Branch:** ai/pro-0032 (worktree `.worktrees/PRO-0032`)

## Feature description

Verbatim brief: `docs/features-to-triage/33-the-audit-trail-is-signed.md`.

Two gaps in the audit trail, from two features. **Sealed is not signed:** PRO-0013
encrypted the trail at rest, but sealing needs only the public key, so anybody who can
read the file can also append a well-formed entry that decrypts correctly. **The lane
recommendation is not recorded:** PRO-0020 and PRO-0024 hand a browser page to Obscura or
to browser-use; that recommendation is Proctor's own act, and there is no record it
happened. The brief names four hard parts and asks for each to be chosen and defended:
what a signing key protects against and what it does not; per-entry signature versus a
hash chain; that PRO-0013's recovery decision must not be softened; and that the
recommendation entry must not become a second copy of the handoff object, because a URL in
an audit entry is a person's browsing history in a file Proctor keeps.

---

## Triage — 2026-08-15

**Sentinel review:** S2 — Ready for Implementation Plan. Governance-adjacent (this is the
audit trail itself, and it adds a second key to the machine), so the verdict, the
assumptions and their review all ran on the strong model, and the out-of-family gate below
was kept to the design question with no key-handling code transmitted.

**No Essential Questions.** Two candidates reached the bar and were resolved rather than
asked, because the fleet runs unattended and both are answerable from the repo and from
measurement. Each is marked ***the exit*** below, so a reader who disagrees can reverse it
in one named place.

### The four hard parts, answered

**1. A chain and a signature are one construction, not a choice between two.** The brief
offers a per-entry signature (catches a forged entry, misses a deleted one) or a hash chain
(catches deletion and truncation, but anyone who can read the file can recompute a
consistent chain, so it catches an accident rather than an attacker). Each fails where the
other works, so this builds both as one thing: **each entry carries a fingerprint of the
entry before it, and a signature over that link, made by a key that physically cannot leave
this Mac.** The chain supplies position; the signature supplies authorship. An inserted
entry has no valid signature; a deleted one breaks a link; a reordered pair breaks two; an
edited one fails both.

**The signing key is held in the Mac's secure element**, which is what makes the claim in
decision 2 literally true rather than nearly true. Measured on this machine while writing
this spec: the stored form of the key is a 284-byte sealed blob that is meaningless on any
other Mac, it re-creates and signs in a later process without a prompt, a signature costs
4.6 ms, and a signature verifies with the public half alone. A Mac with no secure element
falls back to an ordinary key in the same protected store, and **each entry records which
of the two signed it**, so a clean verdict always says what it is worth rather than
quietly meaning less on some machines.

**Entries removed from the end** are the case a chain alone cannot see, because what
remains is a valid prefix. That needs a mark of how far the trail had got, kept somewhere
an attacker with file access cannot reach — so it lives **in the protected key store beside
the key**, not in a file next to the trail. A file-side marker was the first design and the
out-of-family review killed it in one line: restore the trail and its marker together from
a snapshot and the pair verifies perfectly, which is a rollback for free. The mark costs a
measured 12.9 ms per entry, against a step whose settle already costs hundreds. ***The
exit,*** if that ever bites: write the mark on a short timer instead of every entry, which
narrows the guarantee to "nothing older than the last few seconds can be removed" and needs
no new reporting, because a trail running ahead of its mark is already the ordinary
after-a-crash state.

**2. What the signature protects against, stated as narrowly as it is true.** The trail
already lives in a directory only this account can open, so today's forger is already this
user or an administrator. What the signature adds is that **a trail edited anywhere other
than on this Mac is detected, and cannot be repaired by anyone who once read the machine's
secrets** — because there is no secret to read. An edited backup, a copied file, a doctored
disk image, a trail altered while nobody is logged in, or a well-formed entry appended by
anything that got hold of the sealing key: each is reported, and none can be made to pass.

What it does not protect against, and this is the brief's own point: **an agent that can
sign can sign a lie it was told to write.** Anything running as this user, while this
machine is on, can ask the secure element to sign exactly as Proctor does — including
Proctor itself, if something takes it over. What it cannot do is take that ability away with
it. The trail is evidence of what was recorded and now of *where* it was recorded, never
proof that what it says is true.

**The guarantee runs one way, and that is the honest shape of tamper-evidence.** A clean
verdict cannot be manufactured off this machine. A fault verdict can always be forced by
destruction: anyone who can delete the key store entry can reduce the whole history to
unverifiable. Detection is the claim; prevention is not.

**What it costs.** Writing an entry now needs the key store, which is the one thing PRO-0013
deliberately kept off the write path so an unattended run would not go dark. Two facts
bound the cost. The agent is a per-user login agent: its process does not exist before
somebody has logged in, so the "restart before first unlock" window PRO-0013 wrote about
cannot contain a running Proctor. And the key is held in the most available device-bound
class the Mac offers — reachable after the first unlock following a boot, rather than only
while unlocked — so it is strictly easier to reach than the key that reads the trail, and
it is fetched once per run and kept for the run.

**An entry that cannot be signed is dropped. There is no unsigned fallback.** An unsigned
entry would be a downgrade: a forger who cannot sign would write unsigned entries, and a
reader could no longer tell those from entries written honestly while the key store
happened to be shut. Refusing them is what makes "unsigned" mean forged. The review pushed
back that this leaves a hole — delete the key and logging stops — and the answer is that
PRO-0013 already settled the direction (a dropped entry never fails the action it was
recording) and already surfaces the state; what this adds is that a stopped trail is now
loud in the verdict as well. ***The exit,*** if the reader would rather keep recording than
keep the guarantee crisp: write unsigned entries marked as such, which weakens clause 2 to
"unsigned or forged" and is one branch.

**3. PRO-0013's recovery decision stands and is not touched.** The signing key is created on
this Mac, cannot be exported by construction, is never synced, and has no recovery copy,
escrow file or export command — the same terms as the key that reads the trail, for the same
reason. Losing it does not make the history unreadable; it makes it unverifiable, and that
is accepted on the same argument. **Nothing here adds a second secret for the operator to
protect, an export path, or a plaintext copy.** The one new key is the signing key itself,
which is the feature, and it is stored under exactly the terms the reader already chose —
more strictly, in fact, since this one cannot be exported even by the operator.

**4. What the recommendation records: the inputs to the decision, and nothing about where
the person was.** The recorded fact set is deliberately the same set the decision was made
on — the scheme of the address and nothing else, because PRO-0024 routes on the scheme
alone. An entry says: which tool call carried the advice, which browser application, which
lane was named, which rule named it, and the address's scheme (`https`, `chrome`, `file`).
**No address, host, path, query or fragment is recorded, at any detail level.** An auditor
can reconstruct why Proctor said what it said without the trail becoming a browsing history.

Two things were considered and rejected:

- **A redacted address**, in the length-plus-fingerprint form PRO-0005 uses for typed
  values. It does not transfer: that form is safe for a password because a password cannot
  be guessed, and an address can — anyone with a list of candidate addresses can match the
  fingerprint, so it would store browsing history in a form that only looks redacted.
- **Recording a handoff that names no lane.** No lane means no recommendation, so there is
  no act to record; and the case where Proctor most conspicuously decided — declining to
  point any lane at the browser's own password surface — is exactly the entry that would say
  where the person was. Silence records less and loses nothing about Proctor's own conduct.

**A repeat of the same advice is not a new act.** The advisory rides every listing, attach,
snapshot, find and step batch, so recording each would make the trail mostly recommendations
and would time-stamp somebody's browsing minute by minute. One entry per distinct
(application, lane, rule, scheme) per run; a change in any of them records again. This
follows the precedent PRO-0024 set for the full advisory form, emitted once at attach for
the same reason.

### UI & logic preview *(rough sanity check — is this the surface area you expected?)*

- **Where it shows up:** the permission-and-trail tool an operator or agent calls. No new
  screen, no new tool, no new command. The Mac's secure key store gains one more key and one
  small record of how far the trail has got.
- **What users will see:** nothing on screen. Reading the trail returns the same entries in
  the same shape and order, with a verdict beside them: whether the trail checks out, how
  many entries predate this change, and — if something is wrong — which entry is the first
  bad one and what is wrong with it.
- **Behaviour changes:**
  - An entry added by anything other than Proctor on this Mac is reported as forged rather
    than read as genuine, and cannot be made to pass by anyone who copied the machine.
  - An entry removed, moved or edited is reported, with its position; so are entries removed
    from the end, and a trail rolled back to an older copy of itself.
  - Entries written before this change are reported as predating it — neither clean nor
    forged, because nothing could have proved them at the time. The first new entry pins
    them as they stood, so an edit to that older history after today is detected.
  - The trail records, once per run per browser, that Proctor named a browsing tool, which
    one, and which rule chose it — without recording the page.
  - If the key store cannot be reached, nothing is written and the trail's status says so,
    exactly as it already does when an entry cannot be sealed.

### Assumptions

- `[Compliance]` The signature covers the entry as it sits on disk, its link to the previous
  entry, which key signed it, which key class signed it, and an identifier for this trail —
  so entries cannot be spliced from one trail into another. *(the review's point: without a
  per-trail identifier, a line lifted from another machine's trail verifies where it lands)*
- `[Compliance]` An entry that cannot be signed is dropped; there is never an unsigned entry.
  *(an unsigned entry could not be told from a forged one)*
- `[Compliance]` The signing key is created on this Mac, cannot be exported, is not synced,
  and has no recovery copy — the terms of PRO-0013's answer (a), unchanged.
- `[Compliance]` Verification never needs the key that reads the trail and never reveals an
  entry's contents. *(checking and reading are different privileges and stay so)*
- `[Compliance]` A verdict of clean requires the verifying key to be confirmed against the
  key this Mac holds. Verification against an unconfirmed on-disk key is reported as
  internally consistent but unconfirmed, never as clean. *(otherwise a forger supplies both
  the trail and the key that checks it)*
- `[Data & scope]` The recommendation entry records the tool, the browser, the lane, the rule
  and the address's scheme, and no address, host, path, query or fragment.
- `[Data & scope]` Only a recommendation that names a lane is recorded, once per distinct
  application, lane, rule and scheme per run.
- `[Operations]` A dropped or unrecordable recommendation never fails the call that carried
  the advisory. *(the trail is best-effort in one direction only, as it already is)*
- `[Operations]` The verdict separates *stamped by a key this Mac no longer holds* from
  *signature invalid*: a reset key store is not an accusation of forgery. *(the review's
  point; the two collapse into one useless state otherwise)*
- `[Operations]` Entries predating the chain are counted as their own state, beside clean and
  forged. *(two states would either accuse honest history or excuse a forgery)*
- `[Operations]` The trail running ahead of its end-mark is normal growth after a crash; the
  trail running behind it is entries missing from the end; exactly one unparseable fragment
  at the very end is a torn final write, and anything else unparseable is a fault. *(a crash
  between the entry and the mark must not read as tampering, and the review was right that
  one state cannot carry all three cases)*
- `[Behaviour]` Two agents appending at once produce one chain, not a fork: the link is taken
  from the file under the same exclusive lock the append already holds, never from memory,
  and a repeated link is itself reported as a fault. *(the review's point that a lock only
  binds those who take it — so the verifier, not the lock, is what makes a fork visible)*
- `[Behaviour]` The trail stays one sealed record per line, appended with a single write.
  *(PRO-0013's shape is load-bearing for concurrent appends and is not reopened)*
- `[Behaviour]` A Mac with no secure element signs with an ordinary protected key, and the
  entry records which class signed it. *(the alternative is a dark trail on those machines;
  a visible downgrade beats a silent one and beats no trail)*
- `[Scope]` The one-time conversion of a readable trail is not re-run, re-opened or extended.
  *(it is irreversible and has already happened on the reader's machine)*
- `[Scope]` PRO-0024's wire text is unchanged, including its line that nothing the second
  lane does reaches the audit trail — still true, since what is recorded is Proctor's own
  recommendation and not the lane's actions.
- `[Cost]` A signed, marked entry costs a measured 4.6 ms to sign and 12.9 ms to mark,
  against actions whose settling already costs hundreds of milliseconds.
- `[Cost]` Reaching the key store is proved by running the agent, not by the automated
  checks, which run with no live key store and must never touch the operator's own trail.

### Acceptance clauses

1. A trail written by this build verifies clean end to end: every link checks out, every
   signature checks out, and the clean count equals the entry count.
2. **A forged append is detected.** An entry correctly sealed but unsigned, or signed by a
   different key, is reported as forged with its position; entries before it still verify.
3. **A deleted entry is detected.** Removing an entry from the middle breaks the link there
   and is reported with its position; so is a reordered pair; so is a fork, where two entries
   claim the same predecessor.
4. **An edited entry is detected as forged rather than merely unreadable**, including one
   flipped byte inside the sealed part.
5. **Truncation and rollback are detected.** Against the end-mark, a trail cut short reports
   how many entries are missing from the end, and a trail rolled back to an older copy of
   itself reports the same; a trail ahead of its mark whose links check out reports an
   unanchored tail and no fault; a trail behind it by exactly one entry reports a lost final
   entry, which is the ordinary after-a-crash state and not an accusation; a missing mark
   reports that completeness cannot be proved, and never reports clean.
5a. **A key class cannot be claimed.** An entry claiming the secure element on a machine
   whose key is an ordinary one is a fault, and a signature that is not the expected size is
   a fault rather than an unreadable entry. *(added by the plan review, which found the class
   was self-reported)*
6. **Pre-chain history is neither accused nor excused.** Entries written before this change
   verify as predating it and are counted separately; the first chained entry pins them, so
   an edit to one of them after that point is detected.
7. **Verification does not need the reading key.** A trail whose entries cannot be opened —
   sealed to a key this Mac no longer holds — still returns a full verification verdict.
8. **A verifying key that is not this Mac's does not yield a clean verdict**: a trail signed
   by another key, presented with its own matching public key, verifies as internally
   consistent and unconfirmed, never as clean.
9. **An entry cannot be spliced between trails**: an entry taken from a trail with a
   different identifier fails where it lands, even though it was genuinely signed.
10. **There is no unsigned entry.** With the key store unreachable nothing is appended, the
    call carrying the entry still succeeds, and the status reports the trail as not being
    written, with a reason.
11. A key change is reported as *stamped by a key this Mac no longer holds*, distinct from
    an invalid signature, with the position where the key changed.
12. Two writers appending under the lock produce a single chain that verifies, with no fork
    and no repeated link.
13. The verdict is reachable from the operator-facing trail surfaces: clean count, pre-chain
    count, and the first fault with its position and kind.
14. **The recommendation is recorded.** A handoff that names a lane writes one entry carrying
    the tool, the browser's bundle id, the lane, the rule and the address's scheme.
15. **It records no browsing history.** No entry produced by a handoff contains the address,
    its host, path, query or fragment — for an `https` page, a `chrome://` page, a `file:`
    page and a page with no address at all — asserted against the entry's whole serialised
    form rather than field by field.
16. **A handoff that names no lane records nothing**, including the deny-list case and the
    tool-absent case.
17. **A repeat is not a new act.** The same lane, rule, scheme and application in one run
    records once however many advisories carry it; a change in any of the four records again.
18. The recommendation entry is distinguishable from an actuation, does not claim the lane
    ran, and carries no sentence copied from the handoff object.
19. A recommendation that cannot be recorded never fails the call that carried the advisory.
20. The recommendation goes through the same path as every other entry — sealed, chained and
    signed like the rest — so a chain from a run that made recommendations verifies.
21. The trail's documented output shape covers the verdict, and the advertised tool surface
    gains no verb.

### Child work found, not built here

- **`proctor_doctor` still has no policy or trail block.** PRO-0013 logged this; the verdict
  is another thing an operator would look for there, and it is still PRO-0005's scope.
- **Key rotation and re-signing an existing trail.** Each entry records which key signed it,
  so the door is open; walking through it is a separate change, as it is for the seal.
- **The verdict has no surface in the status window**, which would need the app to reach a
  verdict it currently cannot.
- **`why` on the handoff is still prose.** PRO-0024 logged the wire-side half; this feature
  needed the rule as a token and built one for the trail alone, which makes that item
  cheaper without closing it.
- **A trail on a synced or network home directory** is copyable in ways the local case is
  not, and nothing checks where it lives.

### What a test cannot reach here

Machine-witnessable from `swift test`: every clause above, against keys created inside the
test process, an injected trail location and an injected clock. The chain, the signature,
the verdict and the recommendation record are pure and testable in isolation, which is why
they live away from the key store.

**Not witnessable, and reported as code-complete rather than proven:** that the signing key
is created in and retrieved from the Mac's secure element under the terms stated, and that
it is reachable during a locked, unattended run. The automated checks run with no live key
store and are forbidden from touching the operator's own trail — the interlock that
redirects a test process away from the live trail was verified firing under the test host,
against the live trail's checksum, before any suite in this feature was run. The secure
element's behaviour was measured directly with a throwaway key outside the suite, and the
numbers quoted above come from that.

### Out-of-family review

Spec design reviewed on **grok-4.6** (`--effort xhigh --sandbox read-only`), 2026-08-15, no
downgrade. The first attempt returned preamble and hit the deadline while reading repo
files; the retry forbade file reads and answered. The prompt carried the design only — no
key-handling code was transmitted, per the egress rule. Ten defects, **six changed the
design**:

1. **A file-side end-marker is worthless.** Restore the trail and its marker together from a
   snapshot and the pair verifies. The marker moved into the protected key store, which is
   also what now catches a rollback, and it removed a whole file, a second MAC and the
   "marker missing" downgrade path in one move.
2. **A copyable secret voids the headline claim.** A 32-byte key fetched into process memory
   can leave the Mac, so "detects a trail edited anywhere other than here" would have been
   false against anyone who read it once. This reversed the central choice from a symmetric
   stamp to a secure-element signature, and the round trip was measured before adopting it.
3. **Deleting the key silently stops logging.** Answered rather than adopted: PRO-0013
   settled that a dropped entry never fails the action it was recording, and the state is
   already surfaced. What changed is that a stopped trail is now loud in the verdict too.
4. **Stripping the chain back to legacy lines would have looked like "never migrated".** The
   end-mark in the key store records that chaining started, so an all-legacy trail after that
   point is a fault rather than an ordinary old trail.
5. **A lock only binds those who take it,** so two writers can fork the chain. The verifier
   now reports a repeated link as a fault in its own right, rather than trusting the lock.
6. **Entries could be spliced between trails.** A per-trail identifier is inside the signed
   material, so a genuinely signed entry fails where it does not belong.
7. **Key loss and forgery collapsed into one verdict.** They are now separate states, and the
   key identifier is inside the signed material rather than beside it.
8. **A crash, a torn write and trailing junk shared one state.** Three states now, with
   exactly one trailing fragment treated as a torn final write.

Answered rather than adopted: that the key store item should be reachable by one designated
writer only (a Developer ID signed build already partitions the item to its own signature,
but this spec does not claim that as a boundary, because PRO-0013's review specifically
found over-claiming here); and that the trail should be pinned to a non-synced volume, which
is recorded as child work rather than built, since nothing today checks where the trail
lives.

## Plan — 2026-08-15

Implementation plan: `docs/plans/plan-PRO-0032.md` (Plan size: Standard). Its out-of-family
review found ten implementation defects in the construction this spec settled — the exact
bytes that get hashed and signed were the bulk of them — and eight changed the plan before
any code was written. Clause 5 was widened and clause 5a added as a result.
