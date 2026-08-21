# PRO-0096 — Implementation plan

**Spec:** `docs/specs/spec-PRO-0096.md`
**Worktree:** `.worktrees/PRO-0096` on `ai/pro-0096`, branched from `ai/wave-9`
**Change surface:** `docs/test-campaign/cases.json`, `docs/test-campaign/inventory.json`,
`docs/test-campaign/strict-ratchet.json`, `scripts/campaign/wall_clock_census.py`, and a new
evidence directory. No Swift file is touched, so the suite verdict is `ai/wave-9`'s unchanged.

## Goal

Clear the two registry findings that are real, record the third as measured-and-already-correct,
and leave the gate's remaining blockers declared rather than cleared. The two blockers this item
owns — "2 source-analysis claim(s)" and "3 effect-witness claim(s)" — are gone from the gate
output. The two it does not own remain, and CASE-0139 adds a truthful red.

## Steps

**1. Repair the census's arming before believing any reading from it.**
`wall_clock_census.py --arm` resolved its historical reference with
`git merge-base HEAD ai/wave-9`. Once PRO-0089's fix merged into `ai/wave-9`, that merge-base
became a tree in which both known offenders are already fixed, so the arm read two clean files
and reported `detector caught 0 of the 2 known offenders / ARMING FAILED`. Replace it with a
pinned sha.

*Acceptance:* `--arm` reports offenders at `[42]` and `[107]` as expected, `detector caught 2 of
the 2 known offenders / ARMED`, exit 0. Evidence: `census-arm-broken.txt`, `census-arm-pinned.txt`.

**2. Re-measure CASE-0139 from a live run and record what it finds.**
With the arm passing, run the census and take the analyzer and denominator from that run rather
than from the evidence file. Move both fields under `source`, with `examined` as an integer.

*Acceptance:* the gate no longer names CASE-0139 under "Source-analysis claims with no analyzer
or no denominator". Evidence: `census-live.txt`, `source-field-placement.txt`.

**3. Record the offender the live run found.**
The census reports one assertion comparing measured elapsed time to a literal, at
`ProctorCoreTests.swift:232`, introduced by `10285df` after the case was written. Set CASE-0139
`fail`, open DEF-106 against `ProctorCoreTests.swift:232`, and do not change the Swift.

*Acceptance:* `Cases:` shows `1 fail`; DEF-106 is `open` and names the file, line and commit.

**4. Move CASE-0114 to the rung it occupies.**
No witness block is manufactured. The rung question goes out of family before it is settled.

*Acceptance:* the gate no longer names CASE-0114 under "Effect witnesses that witnessed
nothing", and `External effects:` still reads `witnessed=21` of 25, so REQ-035 keeps its witness
through CASE-0080. Evidence: `gate-before.txt`, `gate-after.txt`.

**5. Arm finding 3 two ways rather than reading the guard's source.**
Flip only CASE-0067's status to `pass` on a scratch copy, count untouched, and check whether the
guard fires. Record the result as CASE-0200 against a new REQ-065.

*Acceptance:* the flip takes the flagged count from 3 to 4 and names CASE-0067; the unflipped
copy does not. Evidence: `gate-inconclusive-exemption.txt`, carrying the installed plugin's
sha256 so "unchanged from stock" is checkable rather than asserted.

**6. Raise the strict ratchet in the same commit.**
`strict-check.py` reports checked rising from 124 to 125 and asks for the ratchet to move with
it, so a later change cannot let it fall back silently.

*Acceptance:* `ratchet set to 125 (was 124)`, `strict-check.py` exit 0.

## Open decisions

**CASE-0114's rung was genuinely contested and the record says so.** `gemini-3.7-flash-high`
said `outcome`, reading the case as a terminating-execution check. `grok-4.6` at xhigh said
`metamorphic`, on the ground that a 10-run invariance is the relation that rung covers and that
`outcome` cannot catch "right once and wrong on the second run" — which is this case's whole
subject, since PRO-0083 recorded 3 of 5 runs failing. grok's reading carries the registry's own
precedent, so it was taken. Both rungs sit in `EFFECT_RUNGS`, so neither changes what the case
buys and the choice was settled on meaning rather than on score. The `codex`/`gpt-5.6-sol` lane
was tried first and produced no output file, which is that lane's real failure signal; it is
recorded here rather than retried.

**CASE-0139's status.** `fail` rather than `inconclusive`, because the instrument measured
successfully and returned a positive reading. `inconclusive` is for an instrument that could not
be pointed at the question, which is not what happened. The gemini lane agreed independently.

## Out of scope

`ProctorCoreTests.swift:232` itself (DEF-106, and it needs an owner who will decide between
deleting the assertion and giving `SocketClient` an injectable clock). The four external-effect
requirements recorded `observed` with no witness — REQ-007, REQ-024, REQ-055, REQ-063. The two
inconclusive cases, which the brief put off limits and which remain a declared stop.

## Verification

`./scripts/test.sh` is not run for this item, and the reason is the change surface rather than
cost: `git status --porcelain` lists four JSON files and one Python instrument, and `grep -c
'\.swift'` over it returns 0. The suite compiles and runs Swift, so its verdict here is
`ai/wave-9`'s and running it would re-measure that branch rather than this change. What does own
the verdict for this item is `campaign.py check`, `strict-check.py`, `vacuity-check.py` and the
census's own `--arm`, each captured with its exit code under
`docs/test-campaign/evidence/PRO-0096/`.
