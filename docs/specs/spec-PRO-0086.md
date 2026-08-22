# PRO-0086 — The walkthrough will not advance without its grants

**Status:** To Do → Ready for AI · **Brief:**
`docs/features-to-triage/79-the-walkthrough-will-not-advance-without-its-grants.md`
· **Defects:** DEF-160, DEF-161, DEF-162 · **Lane:** headless `./scripts/test.sh`, with a glass
attempt for the rendered half · **Branch:** `ai/pro-0086` off `ai/wave-9`
· **Ids:** CASE-0310..0329, DEF-160..169, REQ-082..084.

## Measured before any change

`./scripts/test.sh` at `4fc77da`: **1,977 tests in 242 suites, exit 0.**

Read from source at the same commit:

| Fact | Where |
|---|---|
| The primary is `.disabled(!WalkthroughFlow.primaryEnabled(…))` | `Sources/ProctorUI/Walkthrough.swift:91-94` |
| It refuses in 3 of 16 input combinations, all on `permissions` | `WalkthroughFlow.primaryEnabled`, `WalkthroughFlowTests:121-124` |
| Nothing on any step states why it refuses | grep for `reason`, `disabledReason`, `Copy.restart` in `Sources/ProctorUI` returns nothing |
| `Copy.restartNote` exists and is rendered nowhere | defined `WalkthroughFlow.swift:237`; the only other references are its own A5 test |
| The design of record draws that note under the grant rows | `design/surfaces/proctor-surfaces.html`, walkthrough `data-state="permissions"` |
| `Skip setup` is drawn on every step but `connect`, never disabled | `Walkthrough.swift:77-81` |

## The two things this item is answering, and why they are separate

The behaviour — a primary that refuses while a grant is missing — already shipped on
`ai/pro-0081` and is merged. This item does not re-litigate it. It carries the two things
that behaviour was built without.

**A stated reason.** PRO-0081 built the refusal and gave the person no way to see it. The
argument the brief makes against a bare disabled control is the one this item answers: a
person who cannot see why a button is dead concludes the app is broken. Three states refuse
and none of them say so.

**A3's provenance stays recorded.** CASE-0100 already carries the sentence — *THE CLAUSE HAD
NO POPULATION UNTIL THIS ITEM* — and it stays exactly as written. This item does not edit that
row and does not reword it. What it adds is a case of its own that witnesses the clause over
the population as it now stands and names where the population came from, so a reader six
months out can tell the two apart without reading the branch history.

## Behaviour

### A — the disabled primary states its reason (DEF-160)

A new Core rule beside the two that already decide this footer:

    WalkthroughFlow.primaryDisabledReason(on:accessibility:screenRecording:) -> String?

Non-nil **exactly** where `primaryEnabled` is false — that biconditional is the clause worth
asserting, because a reason that can go missing in a refusing state is the defect this item
exists to remove, and a reason that appears in an enabled state is a second bug wearing the
first one's clothes.

What it says, composed from the grant titles rather than written out per state:

| State | Reason |
|---|---|
| Neither grant | `Allow Accessibility and Screen Recording above to continue. Start with Accessibility.` |
| Accessibility only | `Allow Screen Recording above to continue.` |
| Screen Recording only | `Allow Accessibility above to continue.` |

`Allow` is the row button's own label, so the sentence names a control the person can see. The
second sentence appears only when both are missing and it names
`prominentGrant(…)` — the same grant PRO-0090 draws filled. **That is the coherence clause**:
the caption and the prominent Allow button must never nominate different first moves, and a
test asserts they agree in every refusing state rather than asserting each separately.

**Where it is drawn.** A caption on its own row directly above the footer buttons,
trailing-aligned over the primary. Referred out of family: grok returned
`402 Payment Required` (balance exhausted) and gemini-3.7-flash-high took the call — the
footer, on the reasoning that a person stuck on a disabled control is looking at the control,
not 200px up the sheet, and that the hero sheet already carries the restart note and the
Settings link and would become a stack of three grey lines. Its wording for the both-missing
state named no grant, and is sharpened here to name both, because the brief's clause is that
the walkthrough says *which* grant is missing.

The same string is the disabled button's accessibility hint, attached through a `String?`
modifier rather than an empty-string fallback, because `Walkthrough.swift` may hold no string
literal of its own (DEF-039).

### B — the restart requirement is stated again (DEF-161)

`Copy.restartNote` is rendered under the two grant rows while Screen Recording is not granted,
which is where and when the design of record draws it. PRO-0067's A5 has been true at the
value level and false on the glass since the constant was written: the test asserted the
constant contained the word `restart` and nothing asserted the window drew it.

Visibility is a Core rule (`statesRestartNote(screenRecording:)`) for the same reason the other
two are: a decision made in a view body is one this repo cannot prove.

### C — skip is not closed, and a revocation is not a lockout

No code change is expected here — `Skip setup` carries no `.disabled` modifier and
`completes(.skipped)` is true. What is missing is the guard. Three clauses:

- Skip is present and ungated in every state where the primary refuses.
- The source carries no `.disabled` modifier anywhere in the footer other than the primary's,
  asserted by counting rather than by reading.
- Revoking a grant from the both-granted state returns `primaryEnabled` false **with** a
  non-nil reason and an unchanged skip, so the door out is open and labelled.

Whether the agent re-probes a revoked grant at all is `75`'s question and is not touched.

### D — what the campaign records (DEF-162 and the A3 case)

CASE-0100 stands unedited. A new case witnesses the clause over the current population and
records that PRO-0081 created that population. DEF-162 records a divergence found while
reading the design of record for this item and **not fixed here**: the design's permissions
pane draws `Back` and a disabled primary with no `Skip setup`, while the build draws Skip on
every step but `connect`. The build is the one the brief protects, so the design of record is
the record that is wrong; which to change is a reader's call and the row says so.

## Acceptance

- **A1** `primaryDisabledReason` is non-nil exactly where `primaryEnabled` is false, at all
  sixteen combinations, with the refusing set printed as a set rather than implied.
- **A2** In every refusing state the reason names every grant still missing, and names the
  same grant `prominentGrant` nominates.
- **A3** The footer draws the reason: the view is bound to the Core rule at the drawing site,
  and the disabled button carries it as an accessibility hint.
- **A4** `Skip setup` is present and carries no `.disabled` modifier in every refusing state,
  and `completes(.skipped)` still holds.
- **A5** Revocation is not a lockout: from both-granted, dropping either grant refuses the
  primary, produces a reason, and leaves skip untouched.
- **A6** The permissions surface states the restart requirement while Screen Recording is
  missing, bound to `Copy.restartNote` at the drawing site.
- **A7** `Walkthrough.swift` still holds zero string literals outside comments (DEF-039 does
  not regress), and every new identifier is unique and namespaced.
- **A8** `./scripts/test.sh` green, suite count before and after, exit code read off the
  script rather than off a pipe.
- **A9** Every new source guard is armed — the assertion is watched to fail against a tree
  with the behaviour removed, in the same session as the clean run.

## What this does not do

- **It does not revisit whether the primary should refuse.** That behaviour is merged and the
  reader kept it.
- **It does not edit CASE-0100**, or any registry row this item did not write.
- **It does not decide whether the agent re-probes a revoked permission.** `75`'s question.
- **It does not change what the status window draws**, and revisits no wave-9 composition.
- **`/Applications/Proctor.app` is untouched**; any glass measurement runs against
  `.build/Proctor.app` on a private socket.
- **No gate, bound or threshold is edited to make anything green.**
