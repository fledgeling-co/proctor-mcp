# What this reading says

The comparison is on and both ratchets held, and the first thing it does is take a number away.
Differencing the two published reckonings says this project shed 84 pieces of work in a day.
Holding the tool constant says the tool being repaired accounts for -88 of that and the project
moved +4 in the other direction. The 218 in the first report was never the size of this backlog;
it was `reckon` 1.0.0 classing 108 fixed defects as broken and 75 briefs as unbuilt for failing
to join.

**The unmeasured share did not fall.** Evidence work is flat at 36 items across the two trees,
and `unmeasured` is flat at 36 rows with nothing entering and nothing leaving. That is the number
this whole exercise exists to move, and one wave did not move it.

**What did improve is requirements observed: 49/76 to 63/90, +5.5 points.** The denominator grew
by 14 and the observed count grew by 14, which is the shape of a campaign widening without
falling behind itself.

**One axis moved the wrong way, and it is the weakest one.** Briefs joined fell 17.6% to 16.7%:
the queue gained five briefs and the join gained none. The join is mechanical, it stands at 16 of
96, and below 50% the tool withholds retirement claims outright — so 80 of the 88 decision-work
items are `unjoined` briefs whose state is unknown rather than known-bad. PRO-0101 writes the
brief citation at the point the id is allocated, which is the fix for exactly this, and it was
at Developer Review when this was read.

**The blocker table is not where the evidence work is.** Four blockers, one case each, +0.3
points of coverage apiece. The 36 evidence-work items are really 26 requirements — 24 of them
carrying the remedy "obtain any evidence at all" — plus four inconclusive cases and one
requirement standing on the project's own word. Reading the blocker table as the schedule would
buy 1.2 points of coverage and leave the 26 untouched.

## What is worth doing first

1. **Merge PRO-0101.** It is the only thing on this list that moves the axis going backwards, and
   the join gates every retirement claim the tool is currently refusing to make.
2. **Take the next reading at wave 16's actual close**, once PRO-0101 and this item have merged.
   That run has the same tool on both sides, so its delta is project movement with no
   decomposition needed, and it is the first one where the ratchet is guarding a like-for-like
   pair.
3. **Leave the 24 unevidenced requirements as one piece of work rather than 24.** They share a
   remedy, and a wave that closes five of them at random buys less than a wave that decides which
   surface they cluster on.

## What this reading cannot speak for

It was taken mid-wave, not at wave 16's close: PRO-0101 had not merged, so its REQ-100/101,
CASE-0430-0440, DEF-215 and SURF-024 are absent, and PRO-0103's own campaign rows land two
commits after this and are absent too. Both sets will appear as movement in the next delta rather
than being missing from it.

The join caveat in `CADENCE.md` applies to every figure above: the first reckoning's published
78/91 was adjudicated by hand, the ledgers are mechanical on both sides, and these deltas are
computed from the ledgers.
