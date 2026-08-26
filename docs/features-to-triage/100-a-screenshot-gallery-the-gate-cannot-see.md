---
sources: [REQ-111, REQ-112, REQ-113, DEF-209]
status: retired
validated-by: REQ-046, REQ-111, REQ-112, REQ-113 via CASE-0072, CASE-0073, CASE-0152, CASE-0472, CASE-0473, CASE-0474
validated-rungs: metamorphic, outcome
validated-provider: none
validated-through-defect: REQ-046 via DEF-209
---
# Thirty-five pictures the gate cannot see

**Wave 17, brief 4.** DEF-209. Found by auditing gates rather than by reading their output, and it
corrects a claim this project made an hour earlier.

## The reading

```
published captures: 8  ·  distinct images: 8  ·  files in shots dir: 43
35 hard failure(s)     JUDGED 6 of 8 judgeable capture(s) (75%)     ratchet: 6 — held
```

Thirty-five images sit in `docs/test-campaign/evidence/shots/` that **no subject publishes and no
manifest entry names**. Most carry surface-shaped names — `surf-001-mcp-stdio.png` through
`surf-016-install-notarize.png` — so they are most likely real captures taken in earlier waves and
never published, which is the recoverable case rather than the worrying one.

## Why it is not tidiness

The gate's own words: **every finding it makes is derived from published captures, so a file nobody
publishes is a capture the gate cannot see.** It cites a campaign that read
`published captures: 0 · files in shots dir: 11` and exited 0 — a clean gate over nothing.

Thirty-five unpublished images are thirty-five pictures a reader will take as evidence and the
instrument cannot speak for. That is the failure this whole gate exists for, sitting inside the
repository that installed it.

## It is tool movement, and that was established rather than assumed

The same capture-lineage gives the identical reading — exit 2, judged 6 of 8, ratchet 6, 35 hard
failures — at three trees: `dd1a443` (now), `eed148f` (wave-16 close) and `3d6fb15` (the wave-15
merge, before any of this session's work). `ORCHESTRATOR.md` records this gate at **exit 0** with the
same judged figure and ratchet, and that was true of the version which ran it; `test-campaign` moved
to 0.9.6 mid-session and the gate got stricter. **The ratchet still holds at 6, so nothing has got
worse by the tool's own measure.**

That distinction is the one PRO-0103 built the vocabulary for, and this is its second use in a day:
a number moved because the instrument changed, not because the project did.

## What this asks for

1. A **per-file disposition** for all thirty-five: published into the manifest with the subject it
   shows, or given an `unpublishedReason` on its `docs/test-campaign/evidence/shots/captures.json` entry.
2. **Deletion is not the default**, even though the tool offers it. Discarding evidence to clear a gate
   is the move this campaign refuses, and a surface capture from wave 9 that nobody published is
   evidence somebody meant to keep.
3. Whatever the dispositions, the gate exits 0 afterwards **because the population is accounted for**,
   not because the population shrank.

## And the correction it forces

This session recorded "every gate on the merged tree now green" after wave 16 closed. That was wrong:
this gate was red then and had been red before the session started. It was not caught because the
sweep ran the gates it knew about, and this one was invoked against the wrong directory in an earlier
pass — where it exited 2 saying `no inventory at …/evidence/inventory.json`, an honest refusal that an
exit-code-only reading would have logged as a failing gate and a message-only reading as noise.
