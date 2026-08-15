# Plan — PRO-0036: The status window's checks say what they can check

**Spec:** `docs/specs/spec-PRO-0036.md`
**Plan size:** Standard
**Branch / worktree:** `ai/pro-0036` in `.worktrees/PRO-0036`
**Baseline:** `main` at `0ea6f88` (PRO-0050). Last recorded suite: **1158 tests in 128 suites**.

## Shape

The window is a renderer and everything it decides moves out of it. That is not a
preference: `Package.swift` declares two test targets, `ProctorCoreTests` and
`ProctorAgentTests`, and **none for `ProctorUI`** — so a rule written inside a SwiftUI view
body is a rule this repo cannot prove. Three shipped precedents already do it this way and
this follows them exactly: `AgentRecovery.decide` (PRO-0041, rendered by the menu),
`BrowserUseTool.statusSummary` (PRO-0035), `Toolchain.row` (PRO-0050).

So: one new pure file in Core carrying every decision, one new Core test file, one view file
substantially edited, two small accessors moved in the view's model, two tripwire tests, a
changelog line. **Nothing under `Sources/ProctorAgent/` changes and neither does
`Sources/ProctorCore/Wire.swift`** — spec clause 13, and it is what keeps this rebaseable beside PRO-0045 and
PRO-0046.

The one shape decision worth stating up front: **an unrecognised check name renders under
Tools and says nothing about what moves it.** The three permission names are a closed set
fixed by macOS; tools are the half that grows, so an unknown name is far likelier to be a new
tool, and defaulting it into Permissions would re-create the exact defect this item exists to
fix. It is close to unreachable anyway: the tripwire in step 6 turns the build red the moment
the agent emits a name Core does not carry, so the fallback is a safety net under a closed
door rather than a routine path.

## Steps

### 1. `Sources/ProctorCore/StatusChecks.swift` (new) — what kind of thing a check is

The file the whole item hangs on. Pure, no AppKit, no SwiftUI.

```swift
public enum StatusCheckKind: Sendable, Equatable, CaseIterable {
    case permissionReadLive          // macOS re-reads it every time Proctor asks
    case permissionSettledAtLaunch   // macOS answers once per agent process, then repeats itself
    case permissionPerApplication    // only the target application's own prompt settles it
    case tool                        // not a permission: a file on this machine
}
```

`StatusChecks` carries the four names the agent emits as constants — `Accessibility`,
`Screen Recording`, `Automation`, `Shortcuts CLI` — a `known: [String: StatusCheckKind]` map,
and:

- `kind(ofCheckNamed:) -> StatusCheckKind?` — `nil` for a name Core does not know.
- `permissions(in: [DoctorReport.Grant]) -> [DoctorReport.Grant]` — the entries whose kind is a
  permission. An **unknown name is not one**: it falls to the tools side, per the shape note.
- `misfiledTools(in: [DoctorReport.Grant]) -> [DoctorReport.Grant]` — the `tool` entries the
  report puts in its grants list, plus any unknown name. Today that is the Shortcuts CLI and
  only when it is absent.
- `statusText(for: DoctorReport.Grant) -> String` — the subtitle, lifted verbatim from
  `MainWindow.GrantRow.statusText` so behaviour is unchanged: `Granted`, `Not established —
  macOS did not answer`, `Required — not granted yet`, `Optional — asked for per app`. Moving
  it here is what makes spec clause 3 a rule instead of an accident of who is left in the list.
- `mobility(of: DoctorReport.Grant) -> String?` — the sentence saying what would move this
  answer, or `nil` for silence. **Keyed on the check's kind and its state together**, never on
  the permission alone; the review's finding 1 was that flattening the two is a defect.

  | Kind and state | Returns |
  |---|---|
  | any, `granted` | `nil` — including Screen Recording, see the spec's asymmetry note |
  | `permissionReadLive`, denied | Proctor notices this on its own, within a couple of seconds of you granting it |
  | `permissionSettledAtLaunch`, denied | macOS settled this answer when the agent started and will not revisit it. Granting it in Settings will not change this row until the agent restarts |
  | `permissionSettledAtLaunch`, unconfirmed | macOS did not answer in time. Proctor asks again on its own, and this is not a refusal |
  | `permissionPerApplication`, any | `nil` — the existing subtitle and its How text already say it |
  | `tool` or unknown | `nil` |

  The unconfirmed sentence must name **neither a restart nor System Settings** — spec clause 4,
  and PRO-0041's rule at this surface.
- `reportFreshness(at: String) -> String` — `"Asked the agent \(time)"`. The whole string is
  returned so the test can assert it, rather than the view composing a claim nobody checks.

### 2. `Sources/ProctorCore/StatusChecks.swift` — the tool rows

Same file, second half.

```swift
public struct ToolRow: Sendable, Equatable {
    public var tool: String
    public var status: String        // short, derived
    public var tone: Tone            // good / bad / unknown
    public var version: String?
    public var detail: String?       // the report's own sentence, PASSED THROUGH UNEDITED
    public var path: String?
    public var searched: [String]
    public enum Tone: Sendable, Equatable { case good, bad, unknown }
}
```

`StatusChecks.toolRows(tools: [ToolPresence], shortcutsCLIAvailable: Bool) -> [ToolRow]`:

- One row per entry of `tools`, **in the report's order** (`Toolchain.entries` order:
  `obscura`, `browser-use` when named, `simctl`, `cua-driver`, `maestro`).
- Then one row for the Shortcuts CLI, last, built from the boolean — it is an OS component at a
  fixed absolute path, which is exactly why PRO-0050 kept it out of `tools` and why it is
  appended here rather than faked into a `ToolPresence`.
- `tone` from `usability`: `usable` → good, `unusable` → bad, `unconfirmed` or `nil` → unknown.
- `status` derived from `usability` and `evidence` **only** (spec clause 8) — e.g. `Usable —
  found`, `Usable — version from the install layout`, `Found, but its signature is not the one
  its documentation names`, `Found, nothing has established whether it works`, `Not found`.
- `detail`, `version`, `path`, `searched` copied straight from the row. The window never
  re-decides a tool's verdict, and `obscuraSummary` dies in step 3.

**Spec clause 9 falls out of this rather than being enforced:** the agent already omits
`browser-use` from `tools` when the operator has not named the lane, so `toolRows` produces no
row and the view has nothing to render. The test asserts the string appears in **no field of
any row**, not merely that no row is named it.

**The empty and the absent report are real states and both are decided here.** With no report
at all the window has nothing to draw and the section is not rendered; with a report whose
tools array is empty — an older agent, or one that found nothing — `toolRows` still returns the
Shortcuts CLI row, so the section is never a heading over nothing. Both are Core-testable and
neither is left to a view to improvise.

### 3. `Sources/ProctorUI/MainWindow.swift` — the renderer

**Everything in this step is code-complete and reasoned about, not machine-witnessed.** Nothing
renders under `swift test`. The tripwires in step 6 catch the two changes worth pinning; the
rest is verified by a person at the end. Saying so here is what stops a green suite being read
as proof the window is right.

Body order becomes: `Header`, `ReadinessSection`, **`ToolsSection`**, `ActivitySection`,
`ConnectSection`, `AgentSection`, `FooterSection`.

- **`ReadinessSection`** — retitle to `Permissions` with a subtitle naming what a permission is
  (a decision macOS holds about Proctor). In the `.reachable` branch, after the grant rows, add
  the recovery block: when `model.recovery` is a `.restartAgent` offer, `Text(offer.reason)` and
  `Button(offer.action) { model.take(offer) }` **together**, reason immediately above button —
  the same shape `ProctorUIApp.swift:198-201` already uses, and the review's finding 3 is why
  they are adjacent rather than separated by a paragraph. Nothing is computed here;
  `AgentRecovery.decide` already ran in `AgentModel.recomputeRecovery`.
- **`GrantRow`** — `statusText` now calls `StatusChecks.statusText(for:)`. Add a line under the
  subtitle from `StatusChecks.mobility(of:)` when it is non-nil, in the existing `.tertiary`
  11pt register. The `Open Settings` gate (`!granted && !unconfirmed`) and the `How` toggle are
  **unchanged** — PRO-0041 already got those right.
- **`ToolsSection`** (new) — a `Card` titled `Tools`, subtitled so it describes tools (programs
  on this Mac that Proctor uses but does not ship). One `ToolRow`-driven row each: name in
  monospaced 13pt, `status` beneath in 11pt secondary, `version` trailing when present, and a
  `Details`/`Hide` toggle reusing `GrantRow`'s `@State private var show` idiom that reveals
  `detail` and the searched paths. The searched paths earn their place: an agent started by
  launchd inherits no login shell's `PATH`, so "but it *is* installed" is only diagnosable by
  comparing where each side looked.
- **`ObscuraOffer`** moves under `ToolsSection`, **internally unchanged** — including its own
  `Re-check`, which is button B and stays byte-for-byte.
- **`AgentSection`** — delete the `Shortcuts CLI`, `Obscura` and `browser-use` rows, the
  `obscuraSummary` and `secondLaneSummary` helpers, and the `ObscuraOffer` call. **Move the
  browser-use disclosure paragraph** ("an autonomous agent driving a real browser with real
  credentials, and nothing it does reaches Proctor's audit trail") into `ToolsSection` beside
  that tool's row — it is a safety disclosure and must not be lost in the reshuffle. Keep
  Version, This window, macOS, Socket, Attached apps, Live observers, Signature, and the Secure
  Event Input callout.
- **`FooterSection`** — **delete `Button("Re-check") { model.refresh() }`**. Keep `Open log` and
  `Restart agent`. The timestamp renders `StatusChecks.reportFreshness(at:)`.

Buttons A (line ~88, beside `Start the agent`) and B (inside `ObscuraOffer`) are not touched at
all — not their labels, not their actions.

### 4. `Sources/ProctorUI/AgentModel.swift` — two accessors, no new decision

`requiredGrants` and `optionalGrants` filter through `StatusChecks.permissions(in:)` before
partitioning on `required`, so a tool can never reach the permissions list. Nothing else moves.
`recovery` already exists and is already recomputed on every doctor tick and every HUD tick;
**do not add a second decision** — spec clause 6 is that the window's offer is whatever
`AgentRecovery.decide` returned.

### 5. `Tests/ProctorCoreTests/StatusChecksTests.swift` (new) — the deciding half

Covers spec clauses 1 through 10.

| Clause | Tests |
|---|---|
| 1 | every constant name classifies; an unknown name returns `nil`; every `StatusCheckKind` case is reachable from some known name |
| 2 | a report whose grants carry the Shortcuts CLI: `permissions` excludes it, `misfiledTools` returns it, `toolRows` includes it |
| 3 | across **every known name × every `GrantState`**, `Optional — asked for per app` is produced for Automation and for nothing else; and it *is* produced for Automation |
| 4 | the mobility sentence per kind and state, per the step-1 table; the unconfirmed sentence contains neither `restart` nor `Settings`; the settled-at-launch denied sentence contains both `restarts` and `Settings` |
| 5 | no string any function returns for an unconfirmed grant claims a refusal or names a switch |
| 7 | `toolRows` over a constructed report: one row per entry, same order, `usability`/`evidence`/`version`/`detail` preserved; `detail` byte-identical to the report's |
| 8 | `status` is a function of `usability` and `evidence` alone — two rows differing only in `path` or `version` produce the same `status` |
| 9 | with `browser-use` absent from `tools`, its binary name appears in no field of any returned row |
| 10 | `reportFreshness` contains `Asked` and does not contain `Checked` |
| — | `toolRows(tools: [], …)` still returns the Shortcuts CLI row, so the section is never a heading over nothing |
| — | an unknown check name lands on the tools side and produces no mobility sentence |

Clause 6's machine-witnessable half is that **no second decision exists**: the view calls
`AgentRecovery.decide`'s already-computed result and `MainWindow.swift` gains no new
conditional on grant state. That the offer then draws in the right place is (eye).

### 6. Two tripwires, in the repo's own idiom

Both follow `ToolchainDoctorTests.doctorPathSpawnsNothing` — a source scan reached through
`URL(fileURLWithPath: #filePath)` walked up three components to the repository root, with its
`mentions(_:in:)` whole-token helper. A tripwire rather than a proof, and that is the honest
claim for both.

- **`Tests/ProctorCoreTests/StatusChecksTests.swift` — the drift guard (clause 1).** Scan
  `Sources/ProctorAgent/Session/SessionDoctor.swift` for every `name:` string literal in its
  grants construction and assert **the set of literals equals the set of names Core carries**.
  Set equality, not "each classifies to something": a non-nil check would pass a newly added
  tool that Core happened to map to a permission, which is the defect wearing a green test. An
  added name on either side turns the build red and a person has to classify it deliberately.
  This is the reliable half; the wiring route cannot see all four names, because
  `shortcutsAvailable` reads `/usr/bin/shortcuts` off the real filesystem, is not injected, and
  the fourth grant is appended only when it is **absent** — so on a Mac that has it the name
  never appears at runtime. Add the wiring assertion as well, and rely on the scan.
- **`Tests/ProctorCoreTests/StatusChecksTests.swift` — the verdict pin (clause 11).** Scan
  `Sources/ProctorUI/MainWindow.swift` and assert **which** `Re-check` went, not merely how
  many are left: slice the source at `struct FooterSection` and assert that region contains no
  `Re-check` and does still contain `Open log` and `Restart agent`; assert the whole file
  carries exactly two `Re-check` literals; assert `obscuraSummary` is gone. A bare count would
  pass a change that deleted one of the two honest buttons and left the footer's. The failure
  message names the spec's verdict table, so a later change argues with a recorded finding.

A source scan needs no target dependency — it reads a file — so both live in
`ProctorCoreTests` even though one reads agent source and one reads UI source.

### 7. `CHANGELOG.md` — `## [Unreleased]` only

Prose written through `/create-luke-content`, format `marketing`. It hard-fails on an em dash
and on AI-cliché phrasing. Do not touch a released section.

## Verification

1. `swift build` clean, with no warnings beyond the three that pre-exist in `ProctorUI`
   (`ProctorUIApp.swift:69` twice, `Walkthrough.swift:303`).
2. **`./scripts/test.sh`** — never a bare `swift test`, never piped. Three measured ways a red
   suite reads green here are in the fleet contract and the script refuses all three. Read back
   the `with N tests` count against the 1158 baseline.
3. Any `--filter` run matches the **Swift function name**, not the `@Test` display string — a
   filter on a display string runs zero tests and reports green. Read back `with N tests`.
4. Prove the two headline clauses red before green: delete the mobility line and watch clause 4
   fail; restore the footer button and watch the clause 11 pin fail.

### Then a person looks — clauses 14, 15 and 16 are not machine-witnessable

There is no test target for `ProctorUI` and no window server under `swift test`. Build, install
and look, as PRO-0040 did, and record in the progress note **what was actually seen** rather
than implying the suite covered it. Specifically:

- The window opens and shows Permissions, Tools and Background agent as three sections whose
  headings describe themselves, with no tool among the permissions.
- The Tools section lists the tools this machine actually has, a `Details` toggle opens on one
  of them, and the rows are legible at the window's real width.
- The footer has `Open log` and `Restart agent`, no `Re-check`, and a timestamp that still
  advances on its own — the poll is unconditional and nothing was stranded by the deletion.
- The Obscura callout's own `Re-check` still works if Obscura is absent on the test machine;
  if it is installed, say so rather than claiming the path was exercised.
- Clause 15 end to end — deny Screen Recording, read the row's sentence, grant it in Settings,
  return, and see the restart offer — needs a real permission change and an agent restart.
  Attempt it; if the window's own read is itself cached and the offer does not appear, that is
  the limitation `AgentRecovery` already records, and the row's sentence standing alone is what
  covers it. Report which of the two happened.

## Plan review — grok-4.6, `high`, read-only, 2026-08-15

Codex is off for this repo, so the gate ran out of family on grok. The mechanical path check
ran first and passed: every backtick path in this file exists except the two marked `(new)`.
The review returned four findings; **three changed the plan.**

| # | Finding | Disposition |
|---|---|---|
| 1a | The drift tripwire asserts each doctor name classifies to *something*, not to the *right* thing, so a newly added tool that Core happened to map to a permission passes green | **Accepted, step 6 rewritten.** It is now set equality between the agent's literals and Core's map, so either side growing turns the build red. |
| 1b | The verdict pin counts `Re-check` tokens and cannot tell *which* one went; deleting one of the two honest buttons and keeping the footer's would pass | **Accepted, step 6 rewritten.** The scan now slices at `struct FooterSection` and asserts that region specifically. |
| 2 | The fail-safe re-creates the bug: the three permission names are a closed set and tools are the growing half, so an unknown name defaulting into Permissions is exactly the defect being fixed | **Accepted, and it reversed the shape note.** Unknown now falls to the tools side. The draft had the direction backwards. |
| 4c | First-paint, agent-down and empty-tools states have no Core function, so a rewrite could drop them with every test still green | **Accepted.** Step 2 now decides the empty and absent report explicitly, with two tests. |
| 3 | The plan never schedules unit tests for `kind`, `permissions`, `statusText`, `mobility`, `reportFreshness` or `toolRows` | **Refuted — my prompt's fault, not the plan's.** Step 5 is exactly that table; the prompt summarised the plan as four steps and omitted it. |
| 4b | The restart offer is placed in Permissions only, so a reason about a tool would be in the wrong place | **Rejected on the type.** `AgentRecovery.Offer` has two kinds, `.startAgent` and `.restartAgent`, both about the agent process and Screen Recording. Neither can be about a tool. |
| 4a | Deleting the footer button leaves tools and grants with no manual nudge | **Noted, not reversed.** It is the previous gate's decision and the measurement behind it stands: the poll is unconditional, the clock advances without a press, and the one tool with an install flow keeps its own button. What a person loses is up to two seconds. |
| 1c | The view rules in step 3 are untestable as stated | **Accepted as framing.** Step 3 now says so at the top, and clause 6's machine-witnessable half is pinned to "no second decision exists". |

## Out of scope, and nothing here narrows the spec

The spec's non-goals are carried unchanged: no new probe or call, the lanes and policy blocks
stay unrendered, the walkthrough is untouched, a stale *granted* row carries no caveat, buttons
A and B are not deleted, and the window's look is not redesigned. No requirement of the spec
and no triage assumption is dropped by this plan.
