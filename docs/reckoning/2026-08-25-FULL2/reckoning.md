# Reckoning — proctor-mcp

4 piece(s) of work remain — 2 product, 2 evidence, 0 decision — across 1001 ledger rows. This reckoning speaks for 497/500 (99%) of the campaign's designed cases and 139/141 (99%) of its stated requirements; the rest is not known to be done, it is simply not known.

## What it can speak for

| Axis | Measured | Of | % | What the number means |
|---|---:|---:|---:|---|
| Cases adjudicated | 497 | 500 | 99.4% | an instrument returned a verdict on the product — pass or fail. A fail is knowledge; this is not a pass rate. |
| Cases ruled out by decision | 3 | 500 | 0.6% | somebody ruled the cell out of scope or not applicable. A decision, not a measurement, and it is kept out of the line above on purpose. |
| Requirements observed | 139 | 141 | 98.6% | somebody watched it happen, rather than the project reporting it of itself. |
| Surfaces spoken for | 40 | 40 | 100.0% | at least one case on this surface reached a verdict. |
| Briefs joined to evidence | 150 | 150 | 100.0% | the brief could be tied to something in the registry at all. |

_Each figure is a lower bound. Every `unnamed` row is a surface the documents never described, which means the true denominator is larger than the one the documents can supply._

## What remains

Two counts, because they answer different questions. **Rows** is every entity on both sides, and it is total by construction — that is what makes the gate meaningful. **Work** is what somebody would actually schedule: a failing case and the defect it evidences are one job, and blocked cases are counted as the blockers behind them rather than one by one.

| Class | Work | Rows | Kind | What it is |
|---|---:|---:|---|---|
| `broken` | 2 | 2 | product-work | measured, and the answer was no |
| `unmeasured` | 2 | 2 | evidence-work | nobody found out — the work here is becoming able to tell |
| `waived` | 0 | 153 | exception | somebody decided not to — an exception, and it stays visible |
| `verified-done` | 0 | 844 | none | not remaining; kept so the denominator is honest |

## Broken (2)

- **DEF-339** — The Maestro lane reaches the network on any invocation, and the disclosure read as a condition
  - the registry records this defect as 'partially-fixed', which stays in the owing set. A half still broken owes a reproduction for that half, and retiring it here would make this tool under-report for the first time.
- **DEF-340** — A fifth of the campaign carries no lane, and two declared lanes carry no case
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it

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

## What this reckoning cannot speak for

Four pieces of work remain, and the honest headline is that number beside what it
does not cover. This reckoning speaks for **497 of 500** designed cases (99%) and
**139 of 141** stated requirements (99%). It does not speak for the rest, and the
rest is not known to be done — it is simply not known.

Five denominators, each disagreeing with the others, none blended:

| Axis | Reading |
|---|---|
| Cases adjudicated | 497 pass · 3 n/a of 500 |
| Cases CHECKED under *unchecked is failed* | **438 of 500 (88%)** — 41 only prove something rendered, 16 were never watched to fail |
| Requirements observed | 139 of 141 |
| Surfaces spoken for | 40 of 40, with 0 `unnamed` |
| Briefs joined | 150 of 150, every edge a citation and none by token overlap |
| Controls actuated | **4 of 34**, across the 2 surfaces of 40 that declare any |
| Journey boundaries cut | 43 of 50, 6 journeys critical |
| Blind pass | 85 blind of 616 mutating, over 2,224 examined |

**Every denominator here is a floor.** `unnamed` is zero, which says the campaign
found no surface the documents failed to describe — it does not say the intent
space is only 40 surfaces wide. And the control census is the sharpest floor in
the table: 38 of 40 surfaces declare no controls at all, so *4 of 34* is a
fraction of the two that were enumerated, not of the product.

## The two adjudications this run owed

**The join needed no cutting.** All 441 edges are `cited` and none is token
overlap, so there was nothing to confirm or reject. The join did not move this
run — 150 of 150 before and after — which is the reading the skill asks for
before believing a join percentage. The six briefs raised this session carry
`reckon-sources` written at intake, and those are routing citations rather than
retirement claims; the guard added in Wave 27 holds them as requests, and reckon
classed them `undecided` rather than retiring them until their specs merged.

**There were no blocker clusters to adjudicate.** 0 blocked, 0 inconclusive, 0
unoracled. That is a fact about this campaign rather than a step skipped.

## The two or three worth doing first

**DEF-340 is the highest-leverage row, and it is not the largest.** 106 of 500
cases carry no lane, so a fifth of the campaign sits in a single `unassigned`
row. The per-lane ledger exists precisely so a lane cannot hide, and this is that
failure at scale: the campaign cannot presently say which harness ran a fifth of
its own evidence. Only 9 of the 106 name a lane readably in their own row, so
closing it is real work rather than a sweep — and filling it by inference is the
failure rather than the fix.

**The control census is the honest weak point of the product side.** 4 of 34
actuated is the number a reader should carry away, and 38 of 40 surfaces
declaring none is why. `references/inert-ui.md` exists because a campaign scored
32 of 32 over an application whose every button ran an empty closure; this
campaign has the denominator that one lacked, and it is small.

**The two `unmeasured` requirements are correctly unmeasured and should stay
there.** REQ-025 is deferred against an upstream Apple bug and REQ-072 is a
recorded ceiling. `campaign.py`'s evidence vocabulary has no word for either, so
they read as the project talking about itself — which is what they are. Promoting
them would be the re-label this tool's ratchet exists to refuse.
