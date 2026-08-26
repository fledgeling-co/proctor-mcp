# Reckoning — proctor-mcp

19 piece(s) of work remain — 5 product, 2 evidence, 12 decision — across 1017 ledger rows. This reckoning speaks for 499/502 (99%) of the campaign's designed cases and 139/141 (99%) of its stated requirements; the rest is not known to be done, it is simply not known.

## What it can speak for

| Axis | Measured | Of | % | What the number means |
|---|---:|---:|---:|---|
| Cases adjudicated | 499 | 502 | 99.4% | an instrument returned a verdict on the product — pass or fail. A fail is knowledge; this is not a pass rate. |
| Cases ruled out by decision | 3 | 502 | 0.6% | somebody ruled the cell out of scope or not applicable. A decision, not a measurement, and it is kept out of the line above on purpose. |
| Requirements observed | 139 | 141 | 98.6% | somebody watched it happen, rather than the project reporting it of itself. |
| Surfaces spoken for | 40 | 40 | 100.0% | at least one case on this surface reached a verdict. |
| Briefs joined to evidence | 162 | 162 | 100.0% | the brief could be tied to something in the registry at all. |

_Each figure is a lower bound. Every `unnamed` row is a surface the documents never described, which means the true denominator is larger than the one the documents can supply._

## What remains

Two counts, because they answer different questions. **Rows** is every entity on both sides, and it is total by construction — that is what makes the gate meaningful. **Work** is what somebody would actually schedule: a failing case and the defect it evidences are one job, and blocked cases are counted as the blockers behind them rather than one by one.

| Class | Work | Rows | Kind | What it is |
|---|---:|---:|---|---|
| `broken` | 5 | 5 | product-work | measured, and the answer was no |
| `unmeasured` | 2 | 2 | evidence-work | nobody found out — the work here is becoming able to tell |
| `undecided` | 12 | 12 | decision-work | the documents and the evidence disagree; needs a person |
| `waived` | 0 | 153 | exception | somebody decided not to — an exception, and it stays visible |
| `verified-done` | 0 | 845 | none | not remaining; kept so the denominator is honest |

## Broken (5)

- **DEF-342** — SO_NOSIGPIPE reaches one of four accepted sockets, so three writers can still be killed by signal
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-341** — An arm whose command compiles perturbed the next arm's baseline, and the recorded reproduction no longer holds
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-221** — One image carries three captions across two unrelated sweeps, and two wedged timestamps share one frame
  - the registry records this defect as 'partially-fixed', which stays in the owing set. A half still broken owes a reproduction for that half, and retiring it here would make this tool under-report for the first time.
- **DEF-339** — The Maestro lane reaches the network on any invocation, and the disclosure read as a condition
  - the registry records this defect as 'partially-fixed', which stays in the owing set. A half still broken owes a reproduction for that half, and retiring it here would make this tool under-report for the first time.
- **DEF-340** — A fifth of the campaign carries no lane, and two declared lanes carry no case
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it

## Undecided (12)

- **BRIEF-151-a-declared-pass-that-never-ran** — A declared pass that never ran
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-152-thirty-eight-surfaces-that-declare-no-controls** — Thirty-eight surfaces that declare no controls
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-153-forty-one-cases-that-only-prove-something-rendered** — Forty-one cases that only prove something rendered
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-154-seven-durable-boundaries-nobody-cut** — Seven durable boundaries nobody cut
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-155-the-figure-sourcing-that-did-not-close-its-classes** — The figure sourcing that did not close its classes
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-156-two-captures-nobody-judged** — Two captures nobody judged
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-157-non-zero-class-partition-breakdown-reporter** — Non-Zero Class Partition Breakdown Reporter
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-158-unsuppressed-gate-execution-and-exit-verification** — Unsuppressed Gate Execution and Exit Verification
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-159-repository-relative-path-citation-resolver** — Repository-Relative Path Citation Resolver
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-160-release-stub-and-no-op-verification-attestation** — Release Stub and No-Op Verification Attestation
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-161-polling-loop-suppression-and-notification-monitor** — Polling Loop Suppression and Notification Monitor
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-162-autonomous-audit-worklist-continuous-verifier** — Autonomous Audit Worklist Continuous Verifier
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring

## Decisions on the record (153)

Not remaining work, and not done either. Each of these was ruled out by somebody, and the reason it was ruled out can stop being true — a state that had no hook may get one, an account that could not be reached may become reachable. They stay on the ledger so that when the reason expires, the item is still there.

- **CASE-0067** — SURF-005 · ?
  - n/a: PersonInput.isAPerson requires sourcePid == 0, which only hardware carries and no second process can forge, so the human-input path REQ-007 names cannot be driven by any instrument available on this lane. The instru
- **CASE-0245** — SURF-004 · ?
  - n/a: Proctor never observes the driver's cursor, so no instrument on this lane can read whether that cursor is over a covered target. The reachable half was measured and agreed: CASE-0242 shows a non-suppressible driver 
- **CASE-0246** — SURF-004 · ?
  - n/a: the runs the report's first clause describes are driven by another automation stack entirely, so there is no Proctor run to instrument. What WAS measured is the attribution, and it is exact.
- **BRIEF-00-WAVE-7-DIRECTION** — Wave 7 direction: Cua underneath, Proctor on top
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-01-cua-schema-facade** — Stock computer-use schema façade (Anthropic + OpenAI)
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-02-set-of-marks-captures** — Set-of-marks annotated captures
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-03-menu-bar-key-equivalents** — Menu-bar enumeration with key-equivalents
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-04-app-scripting-dictionary** — App scripting-dictionary introspection
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-05-audit-trail-policy-gate** — Redacting audit trail + policy / approval gate
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-06-vision-capture-normalisation** — Vision-capture normalisation + reported scale factor
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-07-zoom-region-crop** — Zoom native-resolution region crop
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-08-mcp-surface-modernization** — MCP surface modernization
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-09-process-kill-fs-jail** — Process kill + filesystem jail
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-10-pointer-overlay-captures** — Pointer / target overlay in captures
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-100-a-screenshot-gallery-the-gate-cannot-see** — Thirty-five pictures the gate cannot see
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-101-reconcile-captures-with-cases** — Reconcile thirty-five captures with their cases and manifest
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-102-standing-checks-for-the-unread-registers** — Standing checks for the registers nothing reads
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-103-the-three-recorded-limits-audit** — Audit of the three recorded limits: filesystem certification, hardware keyboard yield, and dynamic TCC grant re-probe
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-104-warrant-charter-and-release-integrity** — Formalize warrant charter and release gate integration
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-105-brief-join-rate-and-retirement-ladder** — Brief join rate optimization and retirement ladder
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-106-supervision-tui-and-menu-bar-glass-witness** — Supervision TUI and Menu Bar Status Extra On-Glass Witness
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-107-subprocess-actuation-witness-for-cua-driver** — Subprocess Actuation Witness for Cua Driver
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-108-native-ocr-and-high-dpi-zoom-inspector** — Native OCR and High-DPI Visual Region Inspector for Zoom Assertions
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-109-guest-vm-lifecycle-and-attachment-oracle** — Guest VM Lifecycle and Multi-Session Attachment Oracle
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-11-stability-per-step-pointer** — Pointer marker in proctor_stability per-step artifacts
  - the brief declares status 'retired' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.

## Requirements standing on the project's own word (2)

These are not failures. Each is a claim the project makes about itself that nothing independent has confirmed, which is a different thing from a claim that has been checked and held.

- **REQ-025** (`reported`) — Tahoe guest window rendering workaround
  - obtain independent evidence — this is the project's own account of itself
- **REQ-072** (`unknown`) — Two limits on how far Proctor's plane disclosures can reach are recorded as ceilings rather than worked around: wave 9's covered-target rule
  - obtain any evidence at all


---

## Assessment — 2026-08-26

**Fix DEF-342 first, because it is the only row here where the product can be killed by
something a peer does.** The other four `broken` rows are about the campaign's own
bookkeeping; this one is a live signal path. `SO_NOSIGPIPE` reaches one of the four accepted
sockets in the package, and the three that miss it all write to the client they accepted —
`ProctorReflector/SocketServer.swift` through `writeAll`, `Unlock/UnlockBroker.swift` through
`send(client, …, 0)` with flags `0` rather than `MSG_NOSIGNAL`, and `ProctorShim/RemoteServer.swift`
through a raw `write`. The Reflector case is the worst, because it is embedded in another
application and the process a `SIGPIPE` terminates is the host's. What is measured is the
absence of the suppression, by exhaustive grep over the four files; what is not measured is
that the signal fires, so the fix owes a test that writes twice after the FIN lands.

**The twelve `undecided` rows are one wave, not twelve.** They are the ten `Ready for AI`
ledger rows plus briefs 151 and 155, whose specs merged while nothing measured them above the
`none` rung. That second pair is the more interesting half: PRO-0159 and PRO-0163 are both
recorded `Merged`, and the reckoning declines to retire their briefs because the evidence
behind them never reached the `outcome` floor. Building the ten will not move those two; they
need a case that measures the mechanism rather than a spec that describes it.

**Two of the five `broken` rows are `partially-fixed`, and that is the honest reading rather
than a backlog.** DEF-339 stops the half of Maestro's network traffic Proctor controls and
discloses the half it cannot; DEF-221 re-took one of its two shared captures and recorded the
other. Both owe a reproduction for their remaining half, and neither is a fix that failed.
DEF-340 and DEF-341 are recorded limits: 106 cases whose lane nobody can name without
inferring it, and an ordering dependency whose reproduction did not reproduce at this commit
when it was re-run twice.

**The two `unmeasured` requirements should stay unmeasured.** REQ-025 is deferred against an
upstream Apple bug and REQ-072 is a ceiling somebody recorded on purpose. Asking either to
move is asking for the re-label the ratchet exists to refuse.
