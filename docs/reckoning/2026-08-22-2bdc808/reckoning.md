# Reckoning — proctor-mcp

134 piece(s) of work remain — 10 product, 36 evidence, 88 decision — across 620 ledger rows. This reckoning speaks for 99% of the campaign's designed cases and 70% of its stated requirements; the rest is not known to be done, it is simply not known. 80 brief(s) could not be tied to the registry at all; they are listed as `unjoined` and counted as decision work, rather than assumed unbuilt.

## What it can speak for

| Axis | Measured | Of | % | What the number means |
|---|---:|---:|---:|---|
| Cases adjudicated | 289 | 293 | 98.6% | an instrument returned a verdict on the product — pass or fail. A fail is knowledge; this is not a pass rate. |
| Cases ruled out by decision | 0 | 293 | 0.0% | somebody ruled the cell out of scope or not applicable. A decision, not a measurement, and it is kept out of the line above on purpose. |
| Requirements observed | 63 | 90 | 70.0% | somebody watched it happen, rather than the project reporting it of itself. |
| Surfaces spoken for | 23 | 23 | 100.0% | at least one case on this surface reached a verdict. |
| Briefs joined to evidence | 16 | 96 | 16.7% | the brief could be tied to something in the registry at all. |

_Each figure is a lower bound. Every `unnamed` row is a surface the documents never described, which means the true denominator is larger than the one the documents can supply._

## What remains

Two counts, because they answer different questions. **Rows** is every entity on both sides, and it is total by construction — that is what makes the gate meaningful. **Work** is what somebody would actually schedule: a failing case and the defect it evidences are one job, and blocked cases are counted as the blockers behind them rather than one by one.

| Class | Work | Rows | Kind | What it is |
|---|---:|---:|---|---|
| `unjoined` | 80 | 80 | decision-work | named in a brief; the join reached nothing, so its state is unknown either way |
| `broken` | 10 | 10 | product-work | measured, and the answer was no |
| `unmeasured` | 32 + 4 blockers | 36 | evidence-work | nobody found out — the work here is becoming able to tell |
| `undecided` | 8 | 8 | decision-work | the documents and the evidence disagree; needs a person |
| `verified-done` | 0 | 486 | none | not remaining; kept so the denominator is honest |

## What unblocks the most

Blocked cases cluster: a handful of causes usually account for most of them. Resolving these in order returns the most measurement per unit of work.

| Blocker | Cases it unblocks | Coverage returned | Cause |
|---|---:|---:|---|
| `BLOCK-0001` | 1 | +0.3 pts | INCONCLUSIVE, AND THE INSTRUMENT IS NAMED. REQ-024 declares effect `subprocess` and the census names Process() in Actuation/CuaClients.swift as its pr |
| `BLOCK-0002` | 1 | +0.3 pts | inconclusive: PersonInput.isAPerson requires sourcePid == 0, which only hardware carries and no second process can forge, so the human-input path REQ- |
| `BLOCK-0003` | 1 | +0.3 pts | inconclusive: Proctor never observes the driver's cursor, so no instrument on this lane can read whether that cursor is over a covered target. The rea |
| `BLOCK-0004` | 1 | +0.3 pts | inconclusive: the runs the report's first clause describes are driven by another automation stack entirely, so there is no Proctor run to instrument.  |

## Broken (10)

- **BRIEF-85-proctoragents-mutants-mostly-survive** — Nineteen of twenty-two ProctorAgent mutants survived
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-89-the-registry-says-open-and-the-code-says-fixed** — The registry says open where the code says fixed
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-90-the-four-nobody-owns** — Twenty-seven unwrapped tests, a fixed timer, and two witnesses the rung wants
  - the registry records a defect or a failing case against this brief's subject
- **DEF-033** — Nineteen of twenty-two trustworthy-scored ProctorAgent mutants survived, against half in ProctorCore
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-151** — Whether the userInput yield fires for a real hand on a real keyboard is still unproved
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-141** — REQ-055's original sentence certified reads, the whole run and every operator path; the witness watches writes, two calls and one root
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-200** — CASE-0392 records armed: false with a reason the verification disproved
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-201** — A quoted placeholder id is read as a citation at confidence 1.0
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-202** — Six status words that mean not-work are classified as remaining work
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-180** — A Screen Recording answer is frozen for the life of the agent process, so a revoked grant is reported as granted until it restarts
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it

## Unjoined (80)

- **BRIEF-00-WAVE-7-DIRECTION** — Wave 7 direction: Cua underneath, Proctor on top
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-055 (0.09), REQ-094 (0.09), REQ-085 (0.08)
- **BRIEF-01-cua-schema-facade** — Stock computer-use schema façade (Anthropic + OpenAI)
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-072 (0.06), DEF-115 (0.05), REQ-055 (0.05)
- **BRIEF-02-set-of-marks-captures** — Set-of-marks annotated captures
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-094 (0.04), REQ-083 (0.04), DEF-112 (0.04)
- **BRIEF-03-menu-bar-key-equivalents** — Menu-bar enumeration with key-equivalents
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-072 (0.05), REQ-026 (0.05), REQ-055 (0.04)
- **BRIEF-04-app-scripting-dictionary** — App scripting-dictionary introspection
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-098 (0.05), REQ-097 (0.05), REQ-072 (0.04)
- **BRIEF-05-audit-trail-policy-gate** — Redacting audit trail + policy / approval gate
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-055 (0.07), REQ-098 (0.06), REQ-083 (0.06)
- **BRIEF-06-vision-capture-normalisation** — Vision-capture normalisation + reported scale factor
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: DEF-025 (0.05), REQ-005 (0.04), REQ-055 (0.04)
- **BRIEF-07-zoom-region-crop** — Zoom native-resolution region crop
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-055 (0.06), DEF-025 (0.06), REQ-005 (0.06)
- **BRIEF-08-mcp-surface-modernization** — MCP surface modernization
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-055 (0.07), REQ-096 (0.06), REQ-001 (0.05)
- **BRIEF-09-process-kill-fs-jail** — Process kill + filesystem jail
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-055 (0.10), REQ-085 (0.07), REQ-082 (0.05)
- **BRIEF-10-pointer-overlay-captures** — Pointer / target overlay in captures
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: DEF-115 (0.06), REQ-072 (0.06), REQ-055 (0.05)
- **BRIEF-11-stability-per-step-pointer** — Pointer marker in proctor_stability per-step artifacts
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-055 (0.07), REQ-086 (0.06), REQ-085 (0.05)
- **BRIEF-12-gate-flow-replay-stability** — Gate recorded flow-replay and stability through the policy gate + audit
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-055 (0.07), DEF-068 (0.07), REQ-083 (0.07)
- **BRIEF-13-audit-log-encryption-at-rest** — Encryption-at-rest for the JSONL audit log
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-067 (0.06), REQ-085 (0.06), REQ-094 (0.06)
- **BRIEF-15-step-descriptions** — Human-readable step descriptions, derived not supplied
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-072 (0.06), REQ-085 (0.06), REQ-070 (0.06)
- **BRIEF-16-run-hud-panel** — Run HUD — the overlay shown while Proctor drives an app
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-055 (0.08), REQ-094 (0.07), REQ-072 (0.07)
- **BRIEF-17-multi-session-queue** — Multi-session scheduling — session identity, lanes, and the queue
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-085 (0.08), REQ-094 (0.08), REQ-055 (0.08)
- **BRIEF-18-hud-character-assets** — HUD character — sprite assets and state binding
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-055 (0.06), REQ-094 (0.06), DEF-050 (0.05)
- **BRIEF-19-yield-when-a-person-takes-the-machine** — Notice when a person is taking the machine back, and yield
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-085 (0.08), REQ-070 (0.08), REQ-098 (0.07)
- **BRIEF-20-foreground-run-is-obvious** — Make a foreground-only run obvious before it takes the machine
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-070 (0.11), REQ-055 (0.09), REQ-094 (0.08)
- **BRIEF-21-route-browser-work-to-obscura** — Route browser work to Obscura instead of driving a browser by hand
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-085 (0.07), REQ-072 (0.07), REQ-094 (0.06)
- **BRIEF-22-menu-bar-switch-and-character** — A menu bar switch for the panel, and a menu bar icon that is the same character
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-094 (0.10), REQ-085 (0.08), REQ-071 (0.07)
- **BRIEF-23-drawing-fault-must-not-kill-the-agent** — A drawing fault must not kill the agent
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-085 (0.09), REQ-094 (0.09), REQ-055 (0.07)
- **BRIEF-24-offer-to-install-obscura** — Offer to install Obscura when it is missing
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-094 (0.09), REQ-055 (0.08), REQ-088 (0.08)
- **BRIEF-25-second-browser-lane-for-obscuras-limits** — A second browser lane for what Obscura cannot do
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-085 (0.08), REQ-094 (0.07), REQ-055 (0.07)
- **BRIEF-26-prefer-background-and-pointer-in-plane** — Prefer the background, and draw the pointer where the work is happening
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-072 (0.09), REQ-055 (0.08), REQ-094 (0.08)
- **BRIEF-27-foreground-takeover-overlay** — When Proctor must take the front, take it visibly and hold it
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-055 (0.09), REQ-085 (0.08), REQ-094 (0.08)
- **BRIEF-28-menu-bar-character-when-idle** — The menu bar shows the character when idle, not a status symbol
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-055 (0.07), REQ-094 (0.07), REQ-082 (0.07)
- **BRIEF-29-re-check-now-says-what-it-checks** — "Re-check now" does not say what it checks
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-055 (0.09), REQ-085 (0.09), REQ-071 (0.08)
- **BRIEF-30-a-home-for-the-proctor-switches** — A home for the PROCTOR_* switches
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-094 (0.10), REQ-055 (0.09), REQ-082 (0.07)
- **BRIEF-31-the-build-says-which-build-it-is** — The build says which build it is
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-055 (0.08), REQ-096 (0.08), REQ-092 (0.08)
- **BRIEF-32-the-health-report-is-complete** — The health report is complete
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-094 (0.10), REQ-055 (0.09), REQ-085 (0.08)
- **BRIEF-33-the-audit-trail-is-signed** — The audit trail is signed, and it records what Proctor recommended
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-094 (0.07), REQ-072 (0.07), REQ-085 (0.07)
- **BRIEF-34-a-persons-click-reaches-stop** — A person's click reaches Stop
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-085 (0.11), REQ-072 (0.09), REQ-098 (0.08)
- **BRIEF-35-scroll-moves-by-what-was-asked** — Scroll moves by what was asked
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-072 (0.10), REQ-094 (0.09), REQ-055 (0.08)
- **BRIEF-36-the-browser-catalogue-stops-guessing** — The browser catalogue stops guessing, and the handoff is machine-readable
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-085 (0.08), REQ-098 (0.07), REQ-055 (0.07)
- **BRIEF-37-the-status-windows-checks-say-what-they-can-check** — The status window's checks say what they can check
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-096 (0.09), REQ-072 (0.09), REQ-055 (0.09)
- **BRIEF-38-a-hold-names-whose-run-it-is** — A hold names whose run it is
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-072 (0.11), REQ-085 (0.10), REQ-055 (0.10)
- **BRIEF-39-stability-knows-when-it-is-scoring-a-page** — Stability knows when it is scoring a page
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-085 (0.09), REQ-096 (0.08), REQ-094 (0.08)
- **BRIEF-40-page-scoped-refusal** — Page-scoped refusal
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-085 (0.11), REQ-094 (0.10), REQ-083 (0.08)
- _…and 40 more in ledger.json_

## Undecided (8)

- **BRIEF-70-effect-witnesses-off-glass** — Effect witnesses for the four effects that need no window server
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent; and the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-71-effect-witnesses-on-glass** — Effect witnesses for the eight effects that need a display server
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent; and the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-73-gates-nobody-has-watched-fail** — Two gates nobody has watched fail, and one record that drifted
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent; and the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-76-the-ten-the-capped-gate-hid** — The ten external effects a capped gate output hid
  - the requirement this brief maps to is contradicted or vacuous; the document and the build disagree
- **BRIEF-84-the-campaigns-own-instruments** — The campaign's own instruments, and what each of them could not see
  - the requirement this brief maps to is contradicted or vacuous; the document and the build disagree
- **BRIEF-86-a-dead-peer-holds-the-queue** — A dead peer holds the queue, and a swallowed event says nothing
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent; and the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-91-eight-more-operator-paths-with-no-seam** — Eight more operator paths with no seam
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent; and the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **REQ-024** — Automatic browser routing dispatches web URLs to Obscura or browser-use engines
  - requirement evidence 'vacuous' is a disagreement between the documents and the build; a person rules on it, an instrument cannot

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
- **REQ-072** (`inconclusive`) — Two limits on how far Proctor's plane disclosures can reach are recorded as ceilings rather than worked around: wave 9's covered-target rule
  - add observability — the instrument ran and could not read the answer
- **REQ-073** (`unknown`) — Every user-facing string a ProctorUI view draws has exactly one definition, in ProctorCore, named for what the string addresses rather than 
  - obtain any evidence at all
- **REQ-074** (`unknown`) — The status window draws no branch its own state machine cannot reach, and every state it can reach is drawn by the section that is actually 
  - obtain any evidence at all
- **REQ-075** (`unknown`) — Every key in the payload Proctor's window reads and Proctor's agent writes has one definition that both ends reach. This is not a style rule
  - obtain any evidence at all

