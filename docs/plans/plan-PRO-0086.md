# PRO-0086 — implementation plan

**Spec:** `docs/specs/spec-PRO-0086.md` · **Tier:** Small · **Branch:** `ai/pro-0086` off
`ai/wave-9` · **Lane:** headless `./scripts/test.sh`, glass attempted for the rendered half.

Three files change. Everything decidable is decided in `ProctorCore` and asserted there,
because there is no `ProctorUI` test target and no window server inside `swift test` — the
same footing `primaryEnabled` and `prominentGrant` already stand on.

## 1 · `Sources/ProctorCore/WalkthroughFlow.swift`

- `primaryDisabledReason(on:accessibility:screenRecording:) -> String?` — guards on
  `primaryEnabled` so the biconditional cannot drift, collects the missing grants in
  `Grant.allCases` order, and composes `Allow <names> above to continue.` plus, only when both
  are missing, ` Start with <prominentGrant>.`
- `statesRestartNote(screenRecording:) -> Bool` — `!screenRecording`.
- `Copy.reasonLead`, `Copy.reasonTail`, `Copy.reasonJoin`, `Copy.reasonStart` — the fragments,
  so the sentence is assembled from named constants rather than inline literals and a test can
  bind the rendered text to them.
- `ID.reason` and `ID.restartNote`, added to `ID.all`.

Named `ID.reason` rather than `ID.primaryReason` deliberately: `WalkthroughFlowTests:153`
locates the primary button by the substring `WalkthroughFlow.ID.primary`, and a symbol with
that prefix appearing earlier in the file would move that test's window without anyone
touching it.

## 2 · `Sources/ProctorUI/Walkthrough.swift`

- The footer `HStack` moves inside a `VStack(alignment: .trailing, spacing: 6)`; the reason
  `Text` sits above it under `if let`, at size 11 secondary, `.fixedSize(vertical:)`,
  carrying `ID.reason`.
- The primary takes `.hint(disabledReason)` — a private `View` extension taking `String?`, so
  no empty-string literal is needed and DEF-039 does not regress.
- `HeroPermissions` draws `Copy.restartNote` under the rows when
  `WalkthroughFlow.statesRestartNote(screenRecording:)`, above the Settings link, carrying
  `ID.restartNote`.

No wording anywhere else changes. No literal is introduced.

## 3 · `Tests/ProctorCoreTests/WalkthroughFlowTests.swift`

A `// MARK: - PRO-0086` section, appended:

| Clause | Test | Rung |
|---|---|---|
| A1 | reason non-nil ⇔ `!primaryEnabled`, 16 combinations, refusing set printed | outcome |
| A2 | reason names every missing grant and agrees with `prominentGrant` | outcome |
| A3 | the footer's drawing site references `primaryDisabledReason` and `ID.reason`, and the primary carries `.hint(` | source-analysis |
| A4 | skip is drawn in the footer with no `.disabled` on it; the footer holds exactly one `.disabled(` | source-analysis |
| A5 | revocation from both-granted refuses, explains, and leaves `completes(.skipped)` true | outcome |
| A6 | `statesRestartNote` at both values, and the view's drawing site references `Copy.restartNote` | outcome + source-analysis |
| A7 | the existing DEF-039 quote count and `ID` uniqueness tests carry this unchanged | source-analysis |

## 4 · Arming (A9)

Each source guard is watched to fail before it is trusted, in one session, against a scratch
copy of the tree with the construct removed — not against the working tree. Recorded per case
in `armedBy`. The value-level clauses are armed by the biconditional itself: a reason that
returns a constant string would fail A1's enabled half, and a reason ignoring
`prominentGrant` would fail A2.

## 5 · Registries

`docs/test-campaign/inventory.json` gains REQ-082..084 and DEF-160..162; `cases.json` gains
CASE-0310 upward. Rows are appended, nothing is re-sorted, and no row this item did not write
is edited. `scripts/campaign/defect_gate.py claims` and `dropped` both run before the report.

## Order

Core → view → tests → `./scripts/test.sh` → arm each guard → registries → gates → glass
attempt. The gate runs between the view change and the test additions as well, so a broken
window is distinguishable from a wrong assertion.
