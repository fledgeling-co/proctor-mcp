# Reckoning — proctor-mcp

138 piece(s) of work remain — 8 product, 41 evidence, 89 decision — across 873 ledger rows. This reckoning speaks for 438/442 (99%) of the campaign's designed cases and 107/134 (80%) of its stated requirements; the rest is not known to be done, it is simply not known.

## What it can speak for

| Axis | Measured | Of | % | What the number means |
|---|---:|---:|---:|---|
| Cases adjudicated | 438 | 442 | 99.1% | an instrument returned a verdict on the product — pass or fail. A fail is knowledge; this is not a pass rate. |
| Cases ruled out by decision | 0 | 442 | 0.0% | somebody ruled the cell out of scope or not applicable. A decision, not a measurement, and it is kept out of the line above on purpose. |
| Requirements observed | 107 | 134 | 79.9% | somebody watched it happen, rather than the project reporting it of itself. |
| Surfaces spoken for | 33 | 33 | 100.0% | at least one case on this surface reached a verdict. |
| Briefs joined to evidence | 105 | 105 | 100.0% | the brief could be tied to something in the registry at all. |

_Each figure is a lower bound. Every `unnamed` row is a surface the documents never described, which means the true denominator is larger than the one the documents can supply._

## What remains

Two counts, because they answer different questions. **Rows** is every entity on both sides, and it is total by construction — that is what makes the gate meaningful. **Work** is what somebody would actually schedule: a failing case and the defect it evidences are one job, and blocked cases are counted as the blockers behind them rather than one by one.

| Class | Work | Rows | Kind | What it is |
|---|---:|---:|---|---|
| `broken` | 8 | 8 | product-work | measured, and the answer was no |
| `unmeasured` | 37 + 4 blockers | 41 | evidence-work | nobody found out — the work here is becoming able to tell |
| `undecided` | 89 | 89 | decision-work | the documents and the evidence disagree; needs a person |
| `verified-done` | 0 | 735 | none | not remaining; kept so the denominator is honest |

## What unblocks the most

Blocked cases cluster: a handful of causes usually account for most of them. Resolving these in order returns the most measurement per unit of work.

| Blocker | Cases it unblocks | Coverage returned | Cause |
|---|---:|---:|---|
| `BLOCK-0001` | 1 | +1/442 (+0.2 pts) | INCONCLUSIVE, AND THE INSTRUMENT IS NAMED. REQ-024 declares effect `subprocess` and the census names Process() in Actuation/CuaClients.swift as its pr |
| `BLOCK-0002` | 1 | +1/442 (+0.2 pts) | inconclusive: PersonInput.isAPerson requires sourcePid == 0, which only hardware carries and no second process can forge, so the human-input path REQ- |
| `BLOCK-0003` | 1 | +1/442 (+0.2 pts) | inconclusive: Proctor never observes the driver's cursor, so no instrument on this lane can read whether that cursor is over a covered target. The rea |
| `BLOCK-0004` | 1 | +1/442 (+0.2 pts) | inconclusive: the runs the report's first clause describes are driven by another automation stack entirely, so there is no Proctor run to instrument.  |

## Broken (8)

- **BRIEF-23-drawing-fault-must-not-kill-the-agent** — A drawing fault must not kill the agent
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-40-page-scoped-refusal** — Page-scoped refusal
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-85-proctoragents-mutants-mostly-survive** — Nineteen of twenty-two ProctorAgent mutants survived
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-89-the-registry-says-open-and-the-code-says-fixed** — The registry says open where the code says fixed
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-90-the-four-nobody-owns** — Twenty-seven unwrapped tests, a fixed timer, and two witnesses the rung wants
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-99-instruments-that-do-not-prove-their-own-step** — Instruments that do not prove their own step
  - the registry records a defect or a failing case against this brief's subject
- **DEF-033** — Nineteen of twenty-two trustworthy-scored ProctorAgent mutants survived, against half in ProctorCore
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-215** — Four ledger rows have no spec file, so two briefs have no artifact that could cite them
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it

## Undecided (89)

- **BRIEF-00-WAVE-7-DIRECTION** — Wave 7 direction: Cua underneath, Proctor on top
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-01-cua-schema-facade** — Stock computer-use schema façade (Anthropic + OpenAI)
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-02-set-of-marks-captures** — Set-of-marks annotated captures
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-03-menu-bar-key-equivalents** — Menu-bar enumeration with key-equivalents
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-04-app-scripting-dictionary** — App scripting-dictionary introspection
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-05-audit-trail-policy-gate** — Redacting audit trail + policy / approval gate
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-06-vision-capture-normalisation** — Vision-capture normalisation + reported scale factor
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-07-zoom-region-crop** — Zoom native-resolution region crop
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-08-mcp-surface-modernization** — MCP surface modernization
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-09-process-kill-fs-jail** — Process kill + filesystem jail
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-10-pointer-overlay-captures** — Pointer / target overlay in captures
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-100-a-screenshot-gallery-the-gate-cannot-see** — Thirty-five pictures the gate cannot see
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-102-standing-checks-for-the-unread-registers** — Standing checks for the registers nothing reads
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-103-the-three-recorded-limits-audit** — Audit of the three recorded limits: filesystem certification, hardware keyboard yield, and dynamic TCC grant re-probe
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-104-warrant-charter-and-release-integrity** — Formalize warrant charter and release gate integration
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-105-brief-join-rate-and-retirement-ladder** — Brief join rate optimization and retirement ladder
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-11-stability-per-step-pointer** — Pointer marker in proctor_stability per-step artifacts
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-12-gate-flow-replay-stability** — Gate recorded flow-replay and stability through the policy gate + audit
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-13-audit-log-encryption-at-rest** — Encryption-at-rest for the JSONL audit log
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-15-step-descriptions** — Human-readable step descriptions, derived not supplied
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-16-run-hud-panel** — Run HUD — the overlay shown while Proctor drives an app
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-18-hud-character-assets** — HUD character — sprite assets and state binding
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-19-yield-when-a-person-takes-the-machine** — Notice when a person is taking the machine back, and yield
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-20-foreground-run-is-obvious** — Make a foreground-only run obvious before it takes the machine
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-21-route-browser-work-to-obscura** — Route browser work to Obscura instead of driving a browser by hand
  - the requirement this brief maps to is contradicted or vacuous; the document and the build disagree
- **BRIEF-22-menu-bar-switch-and-character** — A menu bar switch for the panel, and a menu bar icon that is the same character
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-24-offer-to-install-obscura** — Offer to install Obscura when it is missing
  - the requirement this brief maps to is contradicted or vacuous; the document and the build disagree
- **BRIEF-25-second-browser-lane-for-obscuras-limits** — A second browser lane for what Obscura cannot do
  - the requirement this brief maps to is contradicted or vacuous; the document and the build disagree
- **BRIEF-26-prefer-background-and-pointer-in-plane** — Prefer the background, and draw the pointer where the work is happening
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-27-foreground-takeover-overlay** — When Proctor must take the front, take it visibly and hold it
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-28-menu-bar-character-when-idle** — The menu bar shows the character when idle, not a status symbol
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-29-re-check-now-says-what-it-checks** — "Re-check now" does not say what it checks
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-31-the-build-says-which-build-it-is** — The build says which build it is
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-32-the-health-report-is-complete** — The health report is complete
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-33-the-audit-trail-is-signed** — The audit trail is signed, and it records what Proctor recommended
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-34-a-persons-click-reaches-stop** — A person's click reaches Stop
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-35-scroll-moves-by-what-was-asked** — Scroll moves by what was asked
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-36-the-browser-catalogue-stops-guessing** — The browser catalogue stops guessing, and the handoff is machine-readable
  - the requirement this brief maps to is contradicted or vacuous; the document and the build disagree
- **BRIEF-37-the-status-windows-checks-say-what-they-can-check** — The status window's checks say what they can check
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- **BRIEF-39-stability-knows-when-it-is-scoring-a-page** — Stability knows when it is scoring a page
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent — route to spec-validation before retiring
- _…and 49 more in ledger.json_

## Requirements standing on the project's own word (26)

These are not failures. Each is a claim the project makes about itself that nothing independent has confirmed, which is a different thing from a claim that has been checked and held.

- **REQ-025** (`reported`) — Tahoe guest window rendering workaround
  - obtain independent evidence — this is the project's own account of itself
- **REQ-030** (`unknown`) — The supervision surface draws what the design compiled, at 100x30 and at the 80x24 floor
  - obtain any evidence at all
- **REQ-031** (`unknown`) — Every command the catalogue declares for the menu bar is actually rendered in it
  - obtain any evidence at all
- **REQ-032** (`unknown`) — The status window lists every permission macOS holds about Proctor, including the one whose absence is silent
  - obtain any evidence at all
- **REQ-033** (`unknown`) — A supervision client can read the machine's readiness, switches and history, not only its run and queue
  - obtain any evidence at all
- **REQ-034** (`unknown`) — An operator drives and checks this Mac from a shell: 21 verbs derived from the tool catalogue, six exit codes, and shell completion generate
  - obtain any evidence at all
- **REQ-035** (`unknown`) — A CLI call is not a privilege bypass: same socket, same policy gate, same queue lane, same audit trail, and the trail records which front en
  - obtain any evidence at all
- **REQ-036** (`unknown`) — Exit code 1 (a check failed) and exit code 3 (the agent is not answering) are never confused, because CI reads an exit code rather than pros
  - obtain any evidence at all
- **REQ-037** (`unknown`) — A session attaches to a macOS guest and executes its steps inside that guest; the host agent routes calls over the forwarded socket and actu
  - obtain any evidence at all
- **REQ-038** (`unknown`) — Guest attachments are held against a counted lane whose capacity is a parameter: macOS at two, one session per named guest, and a run that w
  - obtain any evidence at all
- **REQ-039** (`unknown`) — The pool never evicts: a guest a person started, or one another session holds, is waited for and never stopped to free a slot, and every sto
  - obtain any evidence at all
- **REQ-040** (`unknown`) — A guest's witness tier is derived from the platform its provider reports, so a provider saying darwin yields macOS and the native tier rathe
  - obtain any evidence at all
- **REQ-041** (`unknown`) — Only the agent draws on this Mac: a switch says what an operator asked for and cannot say who is asking, so every live surface also requires
  - obtain any evidence at all
- **REQ-042** (`unknown`) — The takeover statement holds for a minimum duration once raised, and a request arriving while it is up extends it rather than raising it aga
  - obtain any evidence at all
- **REQ-043** (`unknown`) — No drawn pointer over a window the person cannot see: where the pointer's plane cannot be confirmed and something covers the target, nothing
  - obtain any evidence at all
- **REQ-044** (`unknown`) — The takeover statement names a control reachable from the screen reading it: the run panel on the panel's own display, Proctor's menu bar on
  - obtain any evidence at all
- **REQ-045** (`unknown`) — A campaign instrument carries a measured false-positive rate with its denominator before anything is gated on its count: the blind-mutation 
  - obtain any evidence at all
- **REQ-046** (`unknown`) — Every campaign gate is proved able to go red before its passing state is read as evidence, and the proof covers each of the gate's passes se
  - obtain any evidence at all
- **REQ-047** (`unknown`) — Mutation survival for the agent package is measured with its denominator, its seed and its unrun count rather than inferred from the core pa
  - obtain any evidence at all
- **REQ-053** (`unknown`) — One process verifies a given binary's code signature once per file identity, however many sessions ask about it and however many ask at the 
  - obtain any evidence at all
- **REQ-054** (`unknown`) — The shared signature store is a default rather than a singleton: a ToolProbes handed a cache uses that one, so a test gets an isolated store
  - obtain any evidence at all
- **REQ-072** (`unknown`) — Two limits on how far Proctor's plane disclosures can reach are recorded as ceilings rather than worked around: wave 9's covered-target rule
  - obtain any evidence at all
- **REQ-073** (`unknown`) — Every user-facing string a ProctorUI view draws has exactly one definition, in ProctorCore, named for what the string addresses rather than 
  - obtain any evidence at all
- **REQ-074** (`unknown`) — The status window draws no branch its own state machine cannot reach, and every state it can reach is drawn by the section that is actually 
  - obtain any evidence at all
- **REQ-075** (`unknown`) — Every key in the payload Proctor's window reads and Proctor's agent writes has one definition that both ends reach. This is not a style rule
  - obtain any evidence at all

