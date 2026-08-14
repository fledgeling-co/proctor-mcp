# plan-PRO-0014 — Human-readable step descriptions, derived not supplied

**Spec:** `docs/specs/spec-PRO-0014.md`
**Size tier:** Small (one new pure file in ProctorCore + one new test file; no call-site rewiring)
**Gate:** `swift build` + `swift test`

## What is being built

One new file, `Sources/ProctorCore/StepDescription.swift`, holding a pure enum that turns an
`ActionStep` (plus the `AXNode` it resolved to, when there is one) into a single line of English.
Nothing else changes: no existing type gains a field, no call site is rewired. The consumers named
in the brief — the run HUD (PRO-0015), the audit trail, flow reports — each adopt it in their own
change; this delivers the shared derivation they adopt.

It sits in `ProctorCore`, not `ProctorAgent`, because `ActionStep` and `AXNode` both already live in
`ProctorCore/Wire.swift`, and because that is where the other pure, window-free, grant-free logic is
kept and tested (`PointerMarker`, `SetOfMarks`, `Canonical`, `Policy`).

## API

```swift
public enum StepDescription {
    public enum Timing: Sendable { case prospective, present }
    public enum Outcome: String, Sendable { case refused, failed }

    public static let objectLimit = 48

    /// The live line: "About to press Send invoice" / "Pressing Send invoice".
    public static func line(for step: ActionStep, node: AXNode?, timing: Timing) -> String

    /// The after-the-fact line: "Hover refused", "Press Send invoice failed".
    public static func line(for step: ActionStep, node: AXNode?, outcome: Outcome) -> String

    /// Single line, no control characters, no markup, trimmed, hard-cut at
    /// `objectLimit` with no ellipsis. Nil when nothing survives.
    public static func sanitised(_ raw: String?) -> String?
}
```

`node` is optional because a step's target is not always an element (a menu path, a keystroke, a
shortcut name, a script) and because a refused step may never have resolved one.

## Wording table — all 22 kinds, both timings, plus the outcome noun

The verb is Proctor's, always. `X` is the resolved object; where a kind has no object the line is the
action alone, never a dangling phrase.

| kind | present | prospective | outcome noun |
|---|---|---|---|
| `press` | Pressing X | About to press X | Press |
| `setValue` | Setting X | About to set X | Set value |
| `focus` | Focusing X | About to focus X | Focus |
| `menu` | Choosing X | About to choose X | Menu choice |
| `type` | Typing into X | About to type into X | Typing |
| `key` | Sending the keystroke X | About to send the keystroke X | Keystroke |
| `scroll` | Scrolling X | About to scroll X | Scroll |
| `increment` | Incrementing X | About to increment X | Increment |
| `decrement` | Decrementing X | About to decrement X | Decrement |
| `pick` | Picking X | About to pick X | Pick |
| `confirm` | Confirming X | About to confirm X | Confirm |
| `cancel` | Cancelling X | About to cancel X | Cancel |
| `raise` | Raising X | About to raise X | Raise |
| `close` | Closing X | About to close X | Close |
| `resize` | Resizing X | About to resize X | Resize |
| `move` | Moving X | About to move X | Move |
| `dragPath` | Dragging X | About to drag X | Drag |
| `hover` | Hovering over X | About to hover over X | Hover |
| `click` | Clicking X | About to click X | Click |
| `shortcut` | Running the shortcut X | About to run the shortcut X | Shortcut |
| `appleScript` | Running a script | About to run a script | Script |
| `waitFor` | Waiting for X | About to wait for X | Wait |

Objectless forms (used when the object resolves to nothing): "Pressing", "Typing", "Scrolling",
"Dragging", "Hovering", "Clicking", "Waiting", "Sending a keystroke", "Choosing a menu item",
"Running a shortcut", "Running a script". British spelling throughout (`Cancelling`).

`appleScript` never takes an object: the script body is redacted in the audit record and a
description that reprinted it would defeat that. `type` takes the *target* as its object, never the
typed text, for the same reason. `setValue` likewise takes the target, not the value.

## Object resolution

In order, first non-empty wins, and **every** candidate goes through `sanitised` — an app's own
accessibility title can be as long, as multi-line and as markup-laden as anything a caller sends.

1. `step.label` — the caller's override. Replaces only the object, never the verb or the timing word.
2. **Carried text, for the three kinds whose object is not the element they act through** — these come
   *ahead* of the element's name, because the element a keystroke lands in is not what the keystroke
   *is*:
   - `menu` → `step.menuPath.last`
   - `key` → `MenuKeyEquivalent.shortcutString(modifiers:key:)`, so the HUD prints the same
     `cmd+shift+n` form `proctor_menu` reports
   - `shortcut` → `step.text ?? step.value?.stringValue`, mirroring `Actuator.shortcut`'s own
     resolution so the line names the shortcut that actually runs
3. The resolved element's own readable name: `node.title`, then `node.label` (AXDescription), then
   `node.identifier`. (The order already used elsewhere in the agent.)
4. The element's kind, in descending readability: `node.roleDescription`, `node.subrole`, `node.role`.
5. `node.id`.
6. Nothing — the objectless form of the verb.

`dragPath` stops after step 3: a freehand drag through a generic container reads better as the action
alone than as "Dragging AXGroup". `appleScript` stops after step 1: a script has no nameable target,
and its body is redacted in the audit record, so only an explicit caller-supplied name can name it.

**A caller-supplied object is quoted; a derived one is not** — `Pressing "Send invoice"` when the
line came from `step.label`, `Pressing Send invoice` when Proctor derived it. This is the brief's
own reason for deriving in the first place ("text the running client controls does not belong there
*unqualified*"): a person reading the kill switch can see which half of the line Proctor vouches
for. Sanitising maps every double-quote character to a single quote, so a supplied name cannot close
the quotation and append a clause of its own.

## Sanitising

One function, applied to every object candidate:

1. Remove the angle-bracket characters `<` and `>` themselves — never the text between them. A tag
   cannot survive (there is no `<` left to open one) and no legitimate name is destroyed: an app's
   own `<Untitled>` window comes through as `Untitled`, where deleting the whole `<…>` run would
   have deleted the name and fallen through to a role.
2. Remove the emphasis characters the consuming surfaces could interpret: `*`, `_`, `` ` ``. Map
   every double-quote character (`"`, `"`, `"`) to `'`, so a supplied name cannot close the
   quotation the line puts around it. Brackets, hashes and ordinary punctuation stay — they appear
   in legitimate accessibility titles.
3. Remove Unicode control and format characters; map every whitespace run (newline, tab, NBSP) to a
   single space.
4. Trim.
5. Hard-cut at 48 **characters** (grapheme clusters, so a truncation cannot split an emoji), with no
   trailing ellipsis — the HUD's live line is designed never to ellipse.
6. Trim again, so a cut landing mid-space leaves no trailing space.
7. Empty result → nil, and the caller falls back to the next candidate.

## Outcome lines

`"<noun> <object> refused"` / `"<noun> <object> failed"`, and `"<noun> refused"` when there is no
object. The object is kept where there is one so a turned-down `confirm` reads as "Confirm Delete
refused" rather than as a person's own confirmation being denied. The reason is left to the surface
that shows it.

## Tests — `Tests/ProctorCoreTests/StepDescriptionTests.swift`

A new file rather than an addition to `ProctorCoreTests.swift`, because that file is a shared
read-modify-write while sibling fleet runners are live.

| # | Test | Acceptance clause |
|---|---|---|
| T1 | every one of the 22 kinds, present timing, with a titled node | "Every kind produces a sensible line with no caller input" |
| T2 | every one of the 22 kinds, prospective timing | prospective/present distinction from one step object |
| T3 | no line contains a raw kind rawValue ("setValue", "dragPath", "appleScript", "waitFor") | assumption: none rendered by printing the internal name |
| T4 | a 400-character label comes out ≤48 chars, single line | cap at the source |
| T5 | a label with newlines/tabs/control chars comes out single-line | safe single line |
| T6 | a label with `<b>`/`**`/backticks comes out with no markup | no markup |
| T7 | a label of only whitespace/markup falls back to the derived object | "cleans down to nothing falls back" |
| T8 | the label replaces the object but never the verb or "About to" | caller cannot change the verb |
| T9 | a 400-char / multi-line **node title** is capped and flattened too | cleaning runs on derived names, not just the caller's |
| T10 | fallback chain: title → label → identifier → roleDescription → subrole → role → id | never empty, always points at something |
| T11 | a node with none of those still yields the node id | never empty |
| T12 | `type` never prints `step.text`; `appleScript` never prints the body; `setValue` never prints the value | redacted fields never re-derived |
| T13 | `menu` with no node names the last path component | nameless-target degradation |
| T14 | `key` with no node prints `cmd+shift+n` | nameless-target degradation |
| T15 | `shortcut` with no node names the shortcut, matching the actuator's own order | nameless-target degradation |
| T16 | `dragPath` / `appleScript` / `waitFor` with nothing carried read as the action alone, no dangling preposition | no dangling phrase |
| T17 | `waitFor` reads as "Waiting for X", not "Waiting X" | waiting reads as waiting *for* |
| T18 | outcome lines: refused and failed, with and without an object | outcome form |
| T19 | truncation at 48 does not split a grapheme cluster | cap is safe |
| T20 | a `key`/`shortcut`/`menu` step that also carries a node names the keystroke/shortcut/menu item, not the element | review finding 1 |
| T21 | a supplied object is quoted, a derived one is not, and a supplied name containing `"` cannot close the quotation | review finding 4 |
| T22 | `<Untitled>` survives sanitising as `Untitled`; `<b>Send</b>` comes through with no angle brackets | review finding 8 |

## Out-of-family plan review — grok `grok-4.6` (xhigh, read-only), 2026-08-14

Two attempts returned nothing inside the deadline (the known failure mode); the third completed with
10 findings. **5 accepted:**

1. *(High)* `key` / `shortcut` / `menu` resolved the element's name ahead of their carried text, so a
   step that also carried a node read as "Sending the keystroke Search field". Carried text now
   precedes the element's name for those three kinds.
2. *(High)* `appleScript` was declared objectless but still admitted node-derived names. It now
   resolves `step.label` only.
3. *(High)* Nothing stopped a supplied `label` appending a second clause — "Pressing OK. About to
   press Delete" on a kill-switch surface. Supplied objects are now quoted and double quotes inside
   any object are normalised, so client text is qualified rather than passed off as Proctor's.
4. *(Medium)* Deleting whole `<…>` runs destroyed legitimate names such as `<Untitled>`. Sanitising
   now removes the bracket characters, never the text between them.
5. *(Medium)* Objectless forms must not keep a dangling preposition ("Typing into", "Waiting for").
   Already planned; now pinned by T16.

**3 rejected with reason:** splitting the presenter so the HUD can preview typed text, script bodies
and `setValue` values (the spec forbids exactly this, and the audit record redacts them — reopening
it would defeat the redaction); adding an ellipsis and a disambiguator on truncation (the brief
chose a hard cut with no ellipsis because the overlay never ellipses); freezing the object at
enqueue time (the function is pure — a caller wanting a stable line passes the same node twice).

**2 non-defects:** it read the short prompt as defining "About to" and the outcome nouns for `press`
only; the table defines both for all 22 kinds.

## Out-of-family completeness critic — DOWNGRADED to in-family, 2026-08-14

Grok failed the lane four consecutive times on this artifact (exit 142, the 200–220s alarm, no
output; one attempt returned "the inlined source is truncated, so I'll load the full prompt first"
before dying). It answers a ~40-line prompt and not a ~200-line one, which is what the source plus
tests costs. Per ORCHESTRATOR.md the gate fell back **in-family with this logged downgrade**:
`claude --model claude-fable-5 --effort high`, read-only, prompt inlined. Never to Codex, which is
off for this repo. Carry the downgrade into the pre-merge evidence: the completeness critic on this
item is Claude reviewing Claude.

It returned 7 findings. **4 accepted:**

1. *(High)* `menuPath`, `key`/`modifiers` and a shortcut name all arrive in the client's own tool
   call, not from the accessibility tree, yet they rendered unquoted as though Proctor had read them
   off the screen. They are now `supplied` and quoted, which makes the quoting mean one thing.
2. *(Medium)* The whole input was scanned and copied before the 48-character cut, so a
   multi-megabyte accessibility title cost megabytes of work to produce 48 characters. The scan now
   stops once no surviving scalar could still fall inside the cut.
3. *(Low)* `sanitised(step.text ?? step.value?.stringValue)` let a present-but-empty `text` block the
   `value` fallback. The candidates are sanitised separately now, matching the actuator.
4. *(Low)* Dropping an angle bracket with no replacement welded its neighbours — `5<10` read as
   `510`. A stripped bracket is a word break.

**2 rejected with reason:** dropping `step.value` from the shortcut name (the actuator resolves the
shortcut it runs from exactly that field, and triage already rejected the claim that a shortcut step
carries no name — a line naming a different shortcut than the one that runs is the worse failure);
extending the strip set to `[ ] ( ) # | ~` (these appear constantly in legitimate accessibility
titles — "Item [1]", "Track #3", "Save (Copy)" — and the produced string is documented as plain
text, so stripping them damages real names far more often than it protects a surface that chose to
render markdown).

**1 non-defect:** U+2028/2029 are `properties.isWhitespace`, and whitespace is tested before the
control strip, so they become a space rather than vanishing.

## Out of scope, stated

- Localisation; multi-line or rich descriptions (brief).
- Adding a description field to `AuditRecord`, or emitting the line from `SessionAct` — the audit
  record's shape is being changed concurrently by PRO-0013, and the HUD that consumes the live line
  is PRO-0015. This delivers the derivation those two adopt.
