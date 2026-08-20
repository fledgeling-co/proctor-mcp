# Plan — PRO-0079: measure the blind pass before anyone gates on it

**Spec:** `docs/specs/spec-PRO-0079.md` · **Tier:** Small — measurement and documentation, no
production source, and no test edits unless the sample produces a genuine finding.
**Branch:** `ai/pro-0079` off `ai/wave-9`.

## Why this is a measurement task and not a fixing task

The 78 findings are the output of a name-matching pass over Swift written by a tool whose defaults
are Rust/RPC shaped. Before any of them can be called a defect, the pass has to be understood as a
program. Reading `vacuity-check.py:pass_blind` first is what makes the classification defensible,
because four of the six shapes the sample turned out to contain are properties of the matcher
rather than of the tests:

- `fn_re` is `^\s*(?:async\s+)?(?:fn|def|func|function)\s+(\w+)\s*\(`. It does not match
  `private func`, `static func` or a computed property's `set` block, so a test's extracted body
  runs on into whatever follows until the next bare `func`.
- The helper filter excludes a name called more than once in the same file. A test double's method
  called once is therefore counted as a test.
- A mutator matches `(?<![A-Za-z0-9_])verb\w*\s*\(` — a prefix. `stop` matches `stopRun(`,
  `raise` matches `raisesSheet(`, `set` matches `settling(`, and a verb matches the test's own
  name in the `func` line that opens the body.
- A reader matches `reader\w*` anywhere in the tail, prefix-anchored, so a suffix idiom
  (`armCount`) cannot be expressed as a reader at all.

None of that is a criticism the item is asked to act on. It is the reason a finding needs reading
rather than believing.

## Steps

1. **Reproduce.** Run the installed script unmodified and confirm
   `examined=1857 mutating=516 re-read-after=438 blind=78`. Anything else means the tree moved and
   the brief's arithmetic does not apply.
2. **Get all 78.** The display caps at 20. Take a copy with `blind_findings[:20]` widened, run it
   into `evidence/PRO-0079/blind-findings-before.txt`, and confirm 78 lines. The installed script
   is not edited.
3. **Draw the sample.** 5 per large bucket at seed 20260821 plus a census of the tail. Record the
   draw so it reproduces.
4. **Extract the bodies the way the check sees them** — same regex, same last-mutator position,
   with the position marked. Reading the file by eye would miss the body-bleed shape entirely,
   because the bleed is invisible in the source and only exists in the extraction.
5. **Class each finding** with the read that acquits it, or the reason it is not a test. Shapes are
   closed and counted.
6. **Arm the pass** on a `/tmp` copy of `Tests/`: delete one read-back line from a test currently in
   the re-read set and require the count to rise and name it. Do this before trusting a zero.
7. **Decide the vocabulary on measurement.** For each candidate reader: how many files use it, and
   what one addition does to the blind count. Add only what a sampled finding proves and generality
   supports; record the refusals with their numbers.
8. **Fix genuine findings** by adding the read, then `./scripts/test.sh`.
9. **Write it up** — `REPORT.md` section, one requirement row and one case row, evidence paths.
10. **Gate:** `./scripts/test.sh` for the verdict, the vacuity pass re-run for the after-count, and
    an out-of-family review of the classification judgment on grok.

## Test strategy

The suite is the control, not the subject. This item changes no production source, so the whole of
`./scripts/test.sh` is a regression check on whatever reads get added, and the expected result is
the wave's existing count unchanged plus any tests touched.

The measurement itself is guarded by two things rather than by tests:

- **The arming control (step 6)** is this campaign's own rule turned on the instrument. A pass that
  cannot report a genuine finding cannot be believed when it reports none.
- **The confidence bound** stands in for the 21 findings nobody read. With 25 drawn from a stratum
  of 46 and no genuine among them, a hypergeometric bound refutes K≥4 at 95%, so the honest claim
  is "at most 3 genuine in 78", not "zero".

What is deliberately not tested: the check script itself. It belongs to the installed skill, this
item may not edit it, and characterising somebody else's instrument is not what the brief asks for.

## Risks

- **Tuning to zero.** The strongest pressure in this item is to add readers until the count looks
  good. The counter is step 7's two-way measurement and the standing rule that the remaining
  findings stay in the output.
- **Calling a weak read a read.** The 15 vocabulary-shape findings are the judgment calls. Each
  row records the exact expression, so the verdict is arguable rather than asserted, and the
  classification goes to an out-of-family reviewer.
- **Shared registries.** `campaign.json` and `inventory.json` are written by three items this wave.
  Append own rows only; never reformat or re-sort.
