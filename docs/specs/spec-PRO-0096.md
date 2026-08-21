# PRO-0096 — Three registry findings, of which one was reported inside out

**Brief:** none. The three findings on `campaign.py check` are the specification.
**Status:** ready to verify
**Registry ranges:** CASE-0200..0209 · DEF-105..109 · REQ-065..066

Three findings, all against the registry and its instruments rather than any product surface.
Two turned out to be different from how they were reported, and the third turned out to have
been fixed already. What follows records each one against what was measured rather than against
what was expected, because two of the three expectations were wrong.

## Finding 1 — the analyzer and denominator are missing from one case, not four

**Reported:** CASE-0102..0105 (all REQ-048) carry no analyzer and no examined count, and the
gate's own count of "2 source-analysis claim(s)" against four such cases suggests the gate is
capping or miscounting in the shape of DEF-041.

**Measured:** the opposite. CASE-0102, 0103, 0104 and 0105 each carry `source.analyzer` and an
integer `source.examined` (45, 45, 45, 310), and the gate flags none of them. The one case that
is flagged is CASE-0139, which wrote `analyzer` and `examined` as siblings of `id` rather than
under `source`, with `examined` as a prose string. The guard at `campaign.py:772` reads
`case["source"]["analyzer"]` and requires `case["source"]["examined"]` to be an `int >= 1`, so
both fields were invisible to it. CASE-0102..0105 were written through the rung when PRO-0091
created it; CASE-0139 was hand-written at merge and put them where a reader would look rather
than where the guard does.

**The count is right, and there is no gate defect here.** "2 source-analysis claim(s)" is two
findings against one case, one per missing field, and the gate printed `showing 2 of 2` with the
full list beneath it. DEF-041's shape is a list truncated at twelve with no denominator printed
beside it; nothing is truncated here and the denominator is present. The word `claim(s)` reads
as cases to a person skimming, which is how the finding came to be raised against the wrong
four, but a wording that misleads is not a miscount. Recorded as DEF-108.

**The live run disagreed with the case.** The brief asked for both fields to come from running
the instrument rather than from an evidence file, because evidence files in this wave had gone
stale by a merge. Running it found that the claim had gone stale the same way, and worse: the
census now reports one offending assertion where the case records zero. That is finding 1's real
outcome and it is set out under DEF-106 below.

## Finding 2 — CASE-0114 measured a rate, and rates are not witnesses

**Reported:** CASE-0114 passes at `effect-witness` with an empty witness block — no recorder, no
effect class, no count — and is not a merge loss, since the case has no witness block on
`ai/pro-0087` either.

**Measured and agreed.** The case was written at that rung without the fields the rung requires.
Reading what it measured settles where it belongs: its `armedBy` is a control run on the
unmodified tree, which is evidence that the arm bites rather than a recorder watching the
product cross a boundary, and its note frames the measurement as a rate — the forging arm
answered on 10 of 10 runs on the fixed tree, where the unmodified tree managed one green run in
four and one hang killed after six minutes.

An invariance across ten runs is a relation between outputs rather than a value from one, which
is the rung `metamorphic` covers, and the registry already uses it that way: CASE-0015 files a
5-run determinism check there and CASE-0052 is filed there as "a relation across calls, not a
value". `outcome` was the other candidate and is the conservative floor; the rung question went
out of family and the two lanes split, which is recorded on the case.

**It is duplicative as a witness, and that is recorded rather than worked around.** REQ-035's
real external-effect witness is CASE-0080: three sealed records read back off the audit trail's
bytes with a fresh `FileHandle`, effect `ipc`, count 3, driven from three separate front ends.
A second witness block on CASE-0114 would have been a second name for that one measurement. The
external-effect total is unmoved at 21 of 25 after the change, so REQ-035 keeps its witness
through CASE-0080 alone. Recorded as DEF-107.

## Finding 3 — the gate already exempts an inconclusive case

**Reported:** CASE-0067 (REQ-007) and CASE-0087 (REQ-024) are flagged for a witness count of
zero while both are `inconclusive`, the gate may be over-strict, and if so the plugin should be
fixed and the difference from stock declared, since it is live for every project on this
machine.

**Measured: test-campaign 0.9.4 already behaves the way the finding asks for.** The guard is
`if c.get("oracle") in WITNESS_RUNGS and st == "pass"` at `campaign.py:751`, and `state_of` maps
CASE-0087's bare `inconclusive` and CASE-0067's `inconclusive: PersonInput.isAPerson requires
sourcePid == 0...` both off `pass`. A gate run on the unmodified registry names only CASE-0114
under "Effect witnesses that witnessed nothing", three times, and neither case the finding named
appears anywhere in the output.

A code reading alone would not settle whether the guard declines to fire or never reaches these
cases, so it was armed: flipping only CASE-0067's status to `pass`, with its count left at zero,
makes the gate flag it immediately and takes the count from 3 to 4. The guard can fire on that
case and declines to, on the status.

**No plugin change was made, so nothing on this machine differs from stock.** `campaign.py`
is byte-for-byte as installed, sha256 `a7d97822...`. The clarify referral the finding asked for
was not raised either: clarify's own gate drops a question whose answer cannot change the work,
and a two-way measurement had already answered this one in both directions. The two cases were
not touched, as instructed.

## What is deliberately unspecified

**The wall-clock offender is not fixed here.** `ProctorCoreTests.swift:232` violates REQ-056 and
is recorded as DEF-106 with CASE-0139 red against it. Fixing it is a change to the product's
test suite rather than to a registry or an instrument, and it carries a real call inside it: the
two other assertions in that test already carry the product claim, so deleting the wall-clock
line loses nothing, but `SocketClient` has no injectable clock, so the alternative is a small
production change. Whoever owns DEF-106 should make that call rather than inherit it.

**The four unbacked external-effect requirements are untouched.** REQ-007, REQ-024, REQ-055 and
REQ-063 are recorded `observed` with an external effect and no passing `effect-witness` case
behind them, and they hold the gate independently of all three findings above. REQ-055 and
REQ-063 both proved their claims by reading real bytes and modes off a real filesystem while
being recorded at `outcome`, so there may be a rung question there of the same family as
CASE-0114's — in the opposite direction, and promoting four cases onto `effect-witness` clears a
gate blocker, which is the move that needs its own arming evidence rather than a passing
judgement in a neighbouring item.

**The two inconclusive cases stay inconclusive.** They are a declared stop, not an oversight.
