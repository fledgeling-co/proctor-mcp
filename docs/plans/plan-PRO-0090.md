# Plan — PRO-0090

**Tier:** Large. Five source conversions, three defect fixes, one instrument arming per file.
**Spec:** `docs/specs/spec-PRO-0090.md`. **Gate:** `./scripts/test.sh`, exit read off the script.

## Order, and why

Conversion first and one file at a time, because a conversion that breaks a window is
cheapest to find against a suite that was green one file ago. Within the conversion,
`Walkthrough` first: it is the smallest, it is the one DEF-056 also touches, and its Core
type (`WalkthroughFlow`) already holds half the strings so it is the file that tests the
"two values, one name" handling before four larger files depend on it.

| Step | Work | Gate |
|---|---|---|
| 0 | Baseline: gate, and `status_literals.py` over all eight UI files, committed as evidence | run |
| 1 | `Walkthrough.swift` → `WalkthroughFlow.Copy` (+ DEF-056 in the same file) | run |
| 2 | `HistoryModel.swift` → `HistorySurface.Wire` + `.Copy`; agent's writer to the same keys | run |
| 3 | `HistoryWindow.swift` → `HistorySurface.Copy` | run |
| 4 | `ProctorUIApp.swift` → `CommandSurface.CommandID`, `StatusSurface.Copy`, `Wire` | run |
| 5 | `AgentModel.swift` → `Wire` keys, `StatusSurface.Copy` | run |
| 6 | DEF-037: remove the dead branch, relocate the applying treatment | run |
| 7 | Guards + arming: source-binding tests, per-file arming runs, registry rows | run |

## Seams

**`status_literals.py` is the instrument and is not touched.** Its five buckets are the
contract. Where a literal cannot be moved to `Copy` honestly — a wire key, a command id — it
moves to the Core type that owns the value, which is what makes the classifier's default-deny
answer correct rather than worked around.

**Wire keys get a Core home used by both ends.** `HistorySurface.Wire` is read by
`HistoryModel` and written by `Sources/ProctorAgent/Session/SessionHistory.swift`. That
second edit is a string move, not a behaviour change, and existing `SessionHistory` tests
cover the payload shape; without it the constant would have one user and the contract would
still have two sources, which is the defect this item closes one layer up.

**The gate owns every new check.** `Tests/ProctorCoreTests/` already reads
`Sources/ProctorUI/*.swift` from disk via `#filePath` (`MenuBarFallbackTests`,
`CampaignInstrumentTests`), so the source guards are `swift test` cases rather than a script
nobody runs.

## Test strategy

Per file, three readings from one session: the classifier clean with its examined count, the
same file mutated one line to put a sentence back into a rendering construct reporting a
violation with exit 1, and the file as written reporting exit 0 again. That is PRO-0081's
arming shape and it is what stops a green run over an instrument that cannot bite.

New Core tests: `prominentGrant` at four combinations; `HistorySurface.Wire` keys pinned to
their on-the-wire spellings so a rename is caught rather than shipped; the source guards for
DEF-037 and DEF-035, each armed by making the guarded condition false and watching the test
fail.

**Every zero is confirmed able to be non-zero before it is believed.** Five dead predicates
have been found in this wave, all by arming. A guard that greps for a construct is the
easiest kind to write dead — a typo in the pattern reports absence forever — so each grep
guard is run against a copy of the file with the construct present.

## Registry

Ids allocated: CASE-0250..0269, DEF-130..139, REQ-073..075. Rows are appended; nothing
existing is reformatted, re-sorted or rewritten. A same-id row corrected is called out in the
report, because the orchestrator's merge keeps ours by default.

`campaign.py check` reports findings, not cases; case counts are computed with `len()` over
the registry.

## Risks

**A wording drifts in the move.** PRO-0081 had one. Mitigated by committing each file's
pre-conversion text and diffing every moved literal for a verbatim match.

**A denominator falls.** Moving machinery out of a file shrinks what the classifier examines
and looks like progress. Each file's examined count is recorded before and after and the
change is accounted for.

**The conversion widens into decisions.** One decision is moved deliberately (DEF-056's
`prominentGrant`, which did not exist before) and is named in the spec and the report. Any
other is a finding against this item.
