# Reckoning — proctor-mcp

9 piece(s) of work remain — 4 product, 2 evidence, 3 decision — across 1032 ledger rows. This reckoning speaks for 511/514 (99%) of the campaign's designed cases and 139/141 (99%) of its stated requirements; the rest is not known to be done, it is simply not known.

## What it can speak for

| Axis | Measured | Of | % | What the number means |
|---|---:|---:|---:|---|
| Cases adjudicated | 511 | 514 | 99.4% | an instrument returned a verdict on the product — pass or fail. A fail is knowledge; this is not a pass rate. |
| Cases ruled out by decision | 3 | 514 | 0.6% | somebody ruled the cell out of scope or not applicable. A decision, not a measurement, and it is kept out of the line above on purpose. |
| Requirements observed | 139 | 141 | 98.6% | somebody watched it happen, rather than the project reporting it of itself. |
| Surfaces spoken for | 40 | 40 | 100.0% | at least one case on this surface reached a verdict. |
| Briefs joined to evidence | 164 | 164 | 100.0% | the brief could be tied to something in the registry at all. |

_Each figure is a lower bound. Every `unnamed` row is a surface the documents never described, which means the true denominator is larger than the one the documents can supply._

## What remains

Two counts, because they answer different questions. **Rows** is every entity on both sides, and it is total by construction — that is what makes the gate meaningful. **Work** is what somebody would actually schedule: a failing case and the defect it evidences are one job, and blocked cases are counted as the blockers behind them rather than one by one.

| Class | Work | Rows | Kind | What it is |
|---|---:|---:|---|---|
| `broken` | 4 | 4 | product-work | measured, and the answer was no |
| `unmeasured` | 2 | 2 | evidence-work | nobody found out — the work here is becoming able to tell |
| `undecided` | 3 | 3 | decision-work | the documents and the evidence disagree; needs a person |
| `waived` | 0 | 164 | exception | somebody decided not to — an exception, and it stays visible |
| `verified-done` | 0 | 859 | none | not remaining; kept so the denominator is honest |

## Broken (4)

- **DEF-341** — An arm whose command compiles perturbed the next arm's baseline, and the recorded reproduction no longer holds
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-221** — One image carries three captions across two unrelated sweeps, and two wedged timestamps share one frame
  - the registry records this defect as 'partially-fixed', which stays in the owing set. A half still broken owes a reproduction for that half, and retiring it here would make this tool under-report for the first time.
- **DEF-339** — The Maestro lane reaches the network on any invocation, and the disclosure read as a condition
  - the registry records this defect as 'partially-fixed', which stays in the owing set. A half still broken owes a reproduction for that half, and retiring it here would make this tool under-report for the first time.
- **DEF-340** — A fifth of the campaign carries no lane, and two declared lanes carry no case
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it

## Undecided (3)

- **BRIEF-152-thirty-eight-surfaces-that-declare-no-controls** — Thirty-eight surfaces that declare no controls
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-153-forty-one-cases-that-only-prove-something-rendered** — Forty-one cases that only prove something rendered
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-154-seven-durable-boundaries-nobody-cut** — Seven durable boundaries nobody cut
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring

## Decisions on the record (164)

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

## Assessment — 2026-08-26, at the close of wave 29

**The three `undecided` rows are the three ledger rows still open, and they are the same
three.** Briefs 152, 153 and 154 map to PRO-0160 (thirty-eight of forty surfaces declare no
controls), PRO-0161 (forty-one cases that only prove something rendered, of which seven cannot
be routed without a person) and PRO-0162 (seven of fifty durable boundaries uncut). Each is a
wave rather than a footnote, and none of the three can be closed by an instrument: they need
controls enumerated from each surface's own source of truth, cases raised to an effect rung one
at a time, and boundaries cut with a channel distinct from the one that performed the step.

**Eleven briefs left `undecided` this session and reckon reports them as `waived`, which
under-describes them.** `waived` means "somebody decided not to", and the decision here was a
measurement: `brief_validation.py` found, for each, a requirement the brief cites carrying a
passing case at or above the `outcome` floor whose provider resolves, and wrote the witnesses
into the brief's frontmatter. The distinction is legible per brief and invisible in the class
total, so the class total is the wrong number to read for those eleven.

**One thing that record now says and did not before.** It named whichever case ids sorted
earliest, which on a requirement carried by twenty-six cases meant the six oldest — work from
other waves that happens to cite the same requirement. Brief 163's first record named
CASE-0045, 0072, 0073, 0080, 0110 and 0111 while the three cases written for it appeared
nowhere. Witnesses are now ranked by whether the case names this brief or the spec that claims
it, then by rung, and the record prints "6 of 26 citing case(s)" so the list is visibly a
sample. It also exposed a join that is honest and loose: brief 162 is carried by REQ-045 and
REQ-046 while the case written for it cites REQ-130, so the witnesses named are about other
gates. That is recorded rather than repaired by editing the case, which would be fitting the
evidence to the join.

**Of the four `broken`, two are `partially-fixed` and two are recorded limits.** DEF-221 and
DEF-339 each owe a reproduction for the half that was not repaired. DEF-340 is 106 cases whose
lane nobody can name without inferring it, and DEF-341's recorded reproduction did not reproduce
when it was re-run twice on a clean tree — kept open owing a reproduction rather than closed on
a pass that was expected to fail and did not.
