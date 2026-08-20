# Seventy-eight tests that change state and never look at it

**Wave 11, brief 3 of 4.** Independent of `70` and `71`. Sequence it before `73`, because the
false-positive rate this brief measures is what tells `73` whether the blind pass is an instrument
worth gating on.

## The measurement

`vacuity-check.py`'s third pass looks for a test that calls a mutating verb and never reads the
state back afterwards. Against Proctor's suite:

```
blind: examined=1857 mutating=516 re-read-after=438 blind=78
```

Seventy-eight of 516 mutating tests, spread across 30 files:

```
10  YieldWiringTests        7  RunQueueWiringTests       6  TakeoverWiringTests
 6  GrantProbeTests         5  ProctorCoreTests          4  GuestPoolWiringTests
 3  StopReachabilityWiring  3  RunHUDMenuBarWiring       3  HoldAttributionWiring
 3  DelegatedSupervision    3  ContentionTests           3  ConsentSurfaceTests
 2  SessionIsolationWiring  2  ObscuraPresenceWiring     2  ForegroundWiringTests
 2  BackgroundRouteTests    1 each across 14 more files
```

By trailing verb: `act` 13, `unlock` 12, `release` 9, `set` 6, `claim` 6, `yield` 4, `stop` 4,
`cancel` 4, `begin` 4, `seal` 3, `raise` 3, `pause` 3, `attach` 2, and one each of `rotate`,
`restart`, `handle`, `clone`, `apply`.

## What is already known about the number

It is not 78 real gaps, and treating it as 78 would be the misconfiguration the tool warns about:
*a wrong vocabulary produces more findings, so it reads as a thorough pass rather than a
misconfigured one.* Three shapes have been identified by inspection and none of them is a defect:

**Read-then-teardown.** A test that reads its observable and then calls `release()` or `unlock()`
to clean up trips the check, because the check looks at the *last* mutator rather than at whether
any read followed any mutation. Thirty-six of the 78 were sampled and found to have this shape.
The `release` (9) and `unlock` (12) buckets are where it concentrates.

**Return-value-is-the-observable.** A test whose mutator is the subject under test and whose read
is a subscript on the value it returned. Three tests written this session — `aGuestSayingHostIsRestamped`,
`noMachineFieldIsLeftAlone`, `everyAdvertisedActionIsRouted` — are exactly this, and all three are
false positives. The `handle` and `apply` buckets are this shape.

**Vocabulary drift.** The Swift reader list is declared in `campaign.json` as `blindVocabulary`
(33 mutators, 60 readers) because the tool's defaults are Rust/RPC shaped and gave
`examined=1857 mutating=1 blind=1` against Swift. The first Swift vocabulary reported 121 findings
and named three tests that read their latch on the very next line; adding Swift's parenless
computed properties as dot-prefixed readers (`.is`, `.count`, `.waiting`, `.result`) took it to 78.
More reader idioms almost certainly remain.

Two additions are already ruled out and should stay out. `#expect`/`#require` as readers suppress
every finding, because every swift-testing assertion wraps one — that turns the pass into a dead
predicate. And bare `is` as a reader matches inside `thisIsATest` and `Requires`, which is why the
declared form is dot-prefixed.

## What to do

**Sample rather than chase.** Take a stratified sample across the six largest buckets — say five
from each of `act`, `unlock`, `release`, `set`, `claim`, and all of the small tails — read each
one, and class it: false positive by teardown, false positive by return value, vocabulary gap, or
genuine. Record the rate. A number with a denominator and a sampled error rate is worth more than
78 individually litigated verdicts, and the campaign's own rule is to characterise rather than
assert-correct.

**Fix the genuine ones by adding the read, never by deleting the test.** A test that arms a latch
and never checks it is a test that would pass if the latch never armed. The fix is one line: read
the observable the test is named after. `YieldWiringTests` at 10 findings is the densest file and
the right place to start, and its trailing verbs (`act` ×5, `unlock` ×4, `yield` ×1) suggest the
teardown shape dominates there too.

**Extend `blindVocabulary` where the sample shows a reader idiom missing**, and record in its `why`
field what was added and why — the field already carries the note that `#expect`/`#require` are
deliberately absent, and that note is the reason nobody re-adds them.

## The conversion contract

- A sampled false-positive rate with its denominator, written into `REPORT.md`.
- Every finding classed genuine gets its read added and the test re-run; every finding classed
  false positive names its shape.
- `blindVocabulary` updated only where a sampled finding proves a missing idiom, with the reason
  recorded beside it.
- The remaining findings stay in the tool's output rather than being suppressed. A blind pass that
  reports zero because its vocabulary was tuned until it did is worth nothing.

## What this brief does not do

It does not raise the campaign's score. Adding a read to a test that lacked one makes the suite
know more and changes no count. If a genuine finding turns out to be a product defect rather than a
test defect, it gets a surgical fix and its own defect record; a styling inconsistency noticed in
passing gets flagged, not changed.
