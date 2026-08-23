# Reckoning cadence

The reckoning runs **when a wave closes**, and the wave closing is the trigger. Not a date, not
a release, not a reminder.

Four options were put to the reader on 2026-08-22 — at wave close, before a release, on a
clock, or retire the item — and the reasoning behind the answer is in
`docs/specs/spec-PRO-0103.md` under "The cadence, settled 2026-08-22". The short form: a clock
fires whether or not anything changed, and a reckoning nobody reads is one that gets skipped
and then dropped. A wave close is the moment the delta is largest and the context for reading
it is still in somebody's head.

## Running it

From the repository root, on a tree whose brief queue and campaign registry are committed:

```bash
python3 scripts/reckoning/reckoning.py take
```

That is the whole procedure. It resolves the reckoning tool, refuses one that is too old or
whose class vocabulary is not the current partition, names the commit it is reading, builds the
ledger, re-gates it, and then differences it against the most recent earlier reading on its own.

Where the tool lives somewhere other than
`~/Dev/fledgeling-plugins/plugins/reckon/skills/reckon/scripts/reckon.py`, pass `--reckon` or
set `RECKON_SCRIPT`. To difference two existing readings without taking a new one:

```bash
python3 scripts/reckoning/reckoning.py compare docs/reckoning/<earlier> docs/reckoning/<later>
```

## What a run leaves behind

Each run is a directory named `<date>-<commit>` under `docs/reckoning/`, holding four files:

| File | What it is for |
|---|---|
| `ledger.json` | Every entity on both sides in exactly one class. The machine-readable record. |
| `reckoning.md` | `reckon`'s own report on this run alone. |
| `run.json` | The provenance: the commit, the branch, the tool and its version, the gate exits, and any caveat this reading carries. |
| `delta.md` / `delta.json` | What moved since the previous reading, and where the movement came from. |
| `notes.md` | The human read of the run: what the movement means and what is worth doing first. Written by hand, and the only file in the directory that is. |

`run.json` is the file that makes the next run possible. A reading whose tree is not named by a
commit cannot be compared to anything, so `take` refuses to publish one: uncommitted inputs are
rejected outright, and `--allow-dirty` marks the reading unnamed, after which `compare` declines
it as a baseline.

## Reading the delta

`delta.md` opens with movement and puts totals last, because the single-run report already
answers "how much is there" and only two runs can answer "is it moving".

Where the two readings were taken with different versions of `reckon`, the two ledgers are not
directly comparable and the report says so: part of any difference is the tool learning to read
this registry. `compare` then rebuilds the earlier run's own inputs, at the earlier run's own
commit, with the current tool, and reports **tool movement** and **project movement** in
separate columns. Only the project column is progress. That decomposition is only possible
because the earlier run named its commit.

The 2026-08-22 pair shows why it matters: total work fell 218 → 134 between the two published
readings, and the tool being repaired accounts for -88 of that while the project moved +4 in the
other direction. A reader differencing the published numbers alone would record a day in which
this project shed 84 pieces of work.

## When a run fails

| Exit | Means |
|---|---|
| 0 | The reading was taken, the ledger gated clean, and the ratchet held. |
| 1 | `reckon`'s own gate rejected the ledger, or the command was used wrongly. |
| 2 | Refused before measuring: the tool, the tree, or the provenance was not good enough to publish. |
| 3 | The ratchet found an item that left `unmeasured` without being measured. |

Exit 3 is the one the second run exists to turn on. An item may leave `unmeasured` only by
being measured; a snapshot gate catches a bad run, and the ratchet catches the slow version,
where a row is quietly reclassified across runs until nothing remembers it was never checked.
The violation is written into `delta.md` as well as printed, so it survives the terminal.

## What every reading here carries

These are limits of the instrument rather than findings about the project, and they sit beside
the numbers rather than being worked around:

- **The join is mechanical and weak.** 16 of 96 briefs joined at the `2bdc808` reading. Below
  50% the tool withholds retirement claims and every brief stays in its documentary class, so
  `unjoined` is large by construction. The first reckoning's published figure of 78/91 was
  adjudicated by hand; the ledgers are mechanical on both sides, and the deltas are computed
  from the ledgers.
- **All four unmeasured cells share one remedy line.** Brief 96 records this as a grouping the
  tool still does. On this registry at `2bdc808` it presents differently: four blockers,
  `BLOCK-0001` to `BLOCK-0004`, one case each at +0.3 points of coverage. The 16.7% that brief
  quotes is the join percentage, which `reckon` prints as a warning on the same run.
- **`source` neither joins nor is refused as evidence** (brief 96, finding 2). A requirement
  whose only evidence is the document asserting it has not been measured.
- **DEF-201** — a quoted placeholder id in a brief reads as a citation at confidence 1.0. Zero
  occurrences across this repository's briefs, so latent here.
- **DEF-202** — six status words meaning *not* remaining work classify as work. This registry
  uses only `fixed` and `open`, confirmed at `2bdc808` over 118 defect rows, so it does not
  bite here.
- **The installed plugin cache lags the shared source.** On 2026-08-22 the cache held `reckon`
  1.0.0 while the source read 1.1.0, and 1.0.0 crashes on this registry's list-valued evidence
  rather than misreporting it. `take` reads the tool's manifest version and its class list
  before it measures anything, so a stale copy is refused rather than believed.

## Keeping it honest

`python3 scripts/reckoning/reckoning_selftest.py` proves every refusal above can fire, and that
the refusal came from the check rather than from the input. 45 checks; exit 0 means all armed.
Run it after changing `reckoning.py`. The last of the 28 reads the count this paragraph states
and compares it to the run, so this sentence cannot go stale unwatched.
