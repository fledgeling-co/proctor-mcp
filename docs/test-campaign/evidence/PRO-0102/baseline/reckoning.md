# Reckoning — proctor-mcp

232 piece(s) of work remain — 197 product, 31 evidence, 4 decision — across 569 ledger rows. This reckoning speaks for 98% of the campaign's designed cases and 68% of its stated requirements; the rest is not known to be done, it is simply not known.

## What it can speak for

| Axis | Measured | Of | % | What the number means |
|---|---:|---:|---:|---|
| Cases adjudicated | 258 | 262 | 98.5% | an instrument returned a verdict on the product — pass or fail. A fail is knowledge; this is not a pass rate. |
| Cases ruled out by decision | 0 | 262 | 0.0% | somebody ruled the cell out of scope or not applicable. A decision, not a measurement, and it is kept out of the line above on purpose. |
| Requirements observed | 57 | 84 | 67.9% | somebody watched it happen, rather than the project reporting it of itself. |
| Surfaces spoken for | 22 | 22 | 100.0% | at least one case on this surface reached a verdict. |
| Briefs joined to evidence | 16 | 91 | 17.6% | the brief could be tied to something in the registry at all. |

_Each figure is a lower bound. Every `unnamed` row is a surface the documents never described, which means the true denominator is larger than the one the documents can supply._

## What remains

Two counts, because they answer different questions. **Rows** is every entity on both sides, and it is total by construction — that is what makes the gate meaningful. **Work** is what somebody would actually schedule: a failing case and the defect it evidences are one job, and blocked cases are counted as the blockers behind them rather than one by one.

| Class | Work | Rows | Kind | What it is |
|---|---:|---:|---|---|
| `unbuilt` | 75 | 75 | product-work | named in a brief; nothing in the registry answers to it |
| `broken` | 122 | 122 | product-work | measured, and the answer was no |
| `unmeasured` | 27 + 4 blockers | 31 | evidence-work | nobody found out — the work here is becoming able to tell |
| `undecided` | 4 | 4 | decision-work | the documents and the evidence disagree; needs a person |
| `verified-done` | 0 | 337 | none | not remaining; kept so the denominator is honest |

## What unblocks the most

Blocked cases cluster: a handful of causes usually account for most of them. Resolving these in order returns the most measurement per unit of work.

| Blocker | Cases it unblocks | Coverage returned | Cause |
|---|---:|---:|---|
| `BLOCK-0001` | 1 | +0.4 pts | INCONCLUSIVE, AND THE INSTRUMENT IS NAMED. REQ-024 declares effect `subprocess` and the census names Process() in Actuation/CuaClients.swift as its pr |
| `BLOCK-0002` | 1 | +0.4 pts | inconclusive: PersonInput.isAPerson requires sourcePid == 0, which only hardware carries and no second process can forge, so the human-input path REQ- |
| `BLOCK-0003` | 1 | +0.4 pts | inconclusive: Proctor never observes the driver's cursor, so no instrument on this lane can read whether that cursor is over a covered target. The rea |
| `BLOCK-0004` | 1 | +0.4 pts | inconclusive: the runs the report's first clause describes are driven by another automation stack entirely, so there is no Proctor run to instrument.  |

## Broken (122)

- **BRIEF-73-gates-nobody-has-watched-fail** — Two gates nobody has watched fail, and one record that drifted
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-80-the-signature-cache-is-per-session-and-the-work-is-not** — The signature cache is per-session and the work it caches is not
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-81-the-capture-path-reports-frames-it-did-not-get** — The capture path reports a frame it did not get, and a window it does not know about
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-82-tests-that-touch-the-real-machine-and-tests-that-time-themselves** — A test that writes the operator's real policy, and tests that assert a wall clock
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-83-what-the-surfaces-say-and-what-they-draw** — What the surfaces say, what they draw, and the branch that cannot be reached
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-84-the-campaigns-own-instruments** — The campaign's own instruments, and what each of them could not see
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-85-proctoragents-mutants-mostly-survive** — Nineteen of twenty-two ProctorAgent mutants survived
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-86-a-dead-peer-holds-the-queue** — A dead peer holds the queue, and a swallowed event says nothing
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-88-three-that-slipped-the-grouping** — The policy file's mode, a control that lies twice, and a sibling already fixed
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-89-the-registry-says-open-and-the-code-says-fixed** — The registry says open where the code says fixed
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-90-the-four-nobody-owns** — Twenty-seven unwrapped tests, a fixed timer, and two witnesses the rung wants
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-91-eight-more-operator-paths-with-no-seam** — Eight more operator paths with no seam
  - the registry records a defect or a failing case against this brief's subject
- **DEF-006** — Three commands declared for the menu bar were never rendered in it
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-007** — The permissions list omitted the one permission whose absence is silent
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-008** — Three of the supervision TUI's five panes had no data source
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-009** — A halted caller was told which surface stopped it, and it was the wrong one
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-010** — The permissions pane clipped its fourth row off the bottom
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-011** — The fix reached the CLI and the TUI and was filtered out of the window
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-012** — The status window's chrome diverges from its design of record
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-013** — The walkthrough's first slide diverges from its design of record
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-014** — The suite carried an assertion that could not fail, and five tests it was not counting
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-015** — The live Maestro lane could not run on this machine, and its two tests fought over one simulator
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-016** — TUISurface.Model's equality could not tell two models apart, and nothing noticed
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-017** — Eight of the CLI's twenty-one verbs could not be given their main argument
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-018** — Half of ProctorCore's sampled mutants survived, and the second hand-written equality was one of them
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-019** — The operator CLI exits 0 when a check fails, and its test passes because it invents the reply shape
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-020** — The `lume` adapter asked for `--json`, which lume 0.5.3 rejects by name
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-021** — A second copy of the guest-action list in the dispatcher refused `attach` and `detach`
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-022** — `Bundle.module` traps in a shipped `.app` instead of returning nil, and crash-looped the guest agent
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-023** — A relayed guest reply carried the host's `machine`, so a guest result could read as a host one
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-024** — A bounded-probe test asserts wall-clock elapsed and fails on a loaded machine
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-025** — proctor_capture reports a fully transparent frame as status complete and trustworthy true
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-026** — A run whose MCP peer dies keeps the agent queue past the 900-second pause backstop
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-027** — Forty events swallowed by the takeover block produced no yield and no held reason
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-028** — An agent window reports sharingState 1 where CASE-0032 records all three overlays at 0
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-029** — A bounded-probe test asserts wall-clock elapsed and fails on a loaded machine
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-030** — The census control exercises one of the gate's two passes, so unclassed stayed an unwatched zero after it ran green
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-031** — REPORT.md's defect table held 18 of the inventory's 28 records, and every open defect was among the missing
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-032** — The mutation runner's integer-literal operator mutates closure shorthand $0, spending a sampled slot on an edit the compiler must reject
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-033** — Nineteen of twenty-two trustworthy-scored ProctorAgent mutants survived, against half in ProctorCore
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- _…and 82 more in ledger.json_

## Unbuilt (75)

- **BRIEF-00-WAVE-7-DIRECTION** — Wave 7 direction: Cua underneath, Proctor on top
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-01-cua-schema-facade** — Stock computer-use schema façade (Anthropic + OpenAI)
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-02-set-of-marks-captures** — Set-of-marks annotated captures
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-03-menu-bar-key-equivalents** — Menu-bar enumeration with key-equivalents
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-04-app-scripting-dictionary** — App scripting-dictionary introspection
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-05-audit-trail-policy-gate** — Redacting audit trail + policy / approval gate
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-06-vision-capture-normalisation** — Vision-capture normalisation + reported scale factor
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-07-zoom-region-crop** — Zoom native-resolution region crop
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-08-mcp-surface-modernization** — MCP surface modernization
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-09-process-kill-fs-jail** — Process kill + filesystem jail
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-10-pointer-overlay-captures** — Pointer / target overlay in captures
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-11-stability-per-step-pointer** — Pointer marker in proctor_stability per-step artifacts
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-12-gate-flow-replay-stability** — Gate recorded flow-replay and stability through the policy gate + audit
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-13-audit-log-encryption-at-rest** — Encryption-at-rest for the JSONL audit log
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-15-step-descriptions** — Human-readable step descriptions, derived not supplied
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-16-run-hud-panel** — Run HUD — the overlay shown while Proctor drives an app
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-17-multi-session-queue** — Multi-session scheduling — session identity, lanes, and the queue
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-18-hud-character-assets** — HUD character — sprite assets and state binding
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-19-yield-when-a-person-takes-the-machine** — Notice when a person is taking the machine back, and yield
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-20-foreground-run-is-obvious** — Make a foreground-only run obvious before it takes the machine
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-21-route-browser-work-to-obscura** — Route browser work to Obscura instead of driving a browser by hand
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-22-menu-bar-switch-and-character** — A menu bar switch for the panel, and a menu bar icon that is the same character
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-23-drawing-fault-must-not-kill-the-agent** — A drawing fault must not kill the agent
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-24-offer-to-install-obscura** — Offer to install Obscura when it is missing
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-25-second-browser-lane-for-obscuras-limits** — A second browser lane for what Obscura cannot do
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-26-prefer-background-and-pointer-in-plane** — Prefer the background, and draw the pointer where the work is happening
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-27-foreground-takeover-overlay** — When Proctor must take the front, take it visibly and hold it
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-28-menu-bar-character-when-idle** — The menu bar shows the character when idle, not a status symbol
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-29-re-check-now-says-what-it-checks** — "Re-check now" does not say what it checks
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-30-a-home-for-the-proctor-switches** — A home for the PROCTOR_* switches
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-31-the-build-says-which-build-it-is** — The build says which build it is
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-32-the-health-report-is-complete** — The health report is complete
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-33-the-audit-trail-is-signed** — The audit trail is signed, and it records what Proctor recommended
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-34-a-persons-click-reaches-stop** — A person's click reaches Stop
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-35-scroll-moves-by-what-was-asked** — Scroll moves by what was asked
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-36-the-browser-catalogue-stops-guessing** — The browser catalogue stops guessing, and the handoff is machine-readable
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-37-the-status-windows-checks-say-what-they-can-check** — The status window's checks say what they can check
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-38-a-hold-names-whose-run-it-is** — A hold names whose run it is
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-39-stability-knows-when-it-is-scoring-a-page** — Stability knows when it is scoring a page
  - no requirement, defect or case in the registry answers to this brief
- **BRIEF-40-page-scoped-refusal** — Page-scoped refusal
  - no requirement, defect or case in the registry answers to this brief
- _…and 35 more in ledger.json_

## Undecided (4)

- **BRIEF-70-effect-witnesses-off-glass** — Effect witnesses for the four effects that need no window server
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent; and the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-71-effect-witnesses-on-glass** — Effect witnesses for the eight effects that need a display server
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent; and the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-76-the-ten-the-capped-gate-hid** — The ten external effects a capped gate output hid
  - the requirement this brief maps to is contradicted or vacuous; the document and the build disagree
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

