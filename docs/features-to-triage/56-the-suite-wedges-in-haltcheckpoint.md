# The suite wedges in `haltCheckpoint`, and the singleton is why

**Read `00-WAVE-7-DIRECTION.md` first.** Third gate-reliability item, and the first one where
the whole process hangs rather than a test failing. It blocks PRO-0054's merge and it blocks
any honest full-suite gate, so sequence it before anything that needs one.

## The measurement

`./scripts/test.sh` on unmodified `main` at `7fc32d9`, load average 6, **zero** stuck test
helpers, after a `replayd` restart:

```
1571 started, 1520 passed, 24 to 59 never report, no verdict line ever printed
```

It is not load: the earlier deaths at load 146 looked the same but this reproduces on a quiet
machine. It is not `replayd`: PRO-0041's wedge was restarted away and this survived. It is not
`BrowserLaneWiringTests`: skipping it changes nothing (1557 started, 1506 passed). And it is
not any one suite: `DelegatedSupervisionWiringTests` alone passes **28 tests in 0.644s**, and
every suite in the unfinished list passes alone.

## Where it is parked, from a sample of the wedged process

Six threads, identical stack:

```
Session.scheduled(lanes:summary:_:)        SessionQueue.swift:96
  → Session.runSteps(...)                   SessionAct.swift:360
    → Session.haltCheckpoint(probe:)        SessionHUD.swift:210
      → RunControl.checkpoint(run:probe:)   RunControl.swift:252
```

`checkpoint` is an unbounded poll:

```swift
while true {
    await probe?()
    if let halt = look(run: run) { return halt }
    if !isParked(run: run) { return nil }
    try? await Task.sleep(nanoseconds: pollNanoseconds)
}
```

It returns only on a halt or on becoming un-parked. A run parked with neither spins forever,
holding its lane, and `Session.scheduled` above it holds the queue. Six of them do.

## The cause is already written down in the tree

`Tests/ProctorAgentTests/YieldWiringTests.swift:121` carries this comment, from the fix to its
own instance of this:

> `Session.runControl` defaults to `RunControl.shared`, so a harness that only injected when a
> test asked for it handed every other test the production singleton. One test yielding it
> left the next one's checkpoint waiting out a 900-second backstop, which is why every test
> here passed alone and the suite hung as a whole; serialized execution stops them
> overlapping, not from leaving state behind.

That suite injects its own latch now. **Every other suite still gets the singleton**, because
the default on `Session.runControl` was never changed. So the same defect is live wherever a
second suite parks it, and the 900-second backstop is longer than any patience.

## What it should do

Make a test process unable to inherit a parked `RunControl` from another suite, and make the
wedge legible when it happens anyway.

## The hard parts, named

- **Find the suite that parks it before changing the default.** The mechanism is established;
  the leaker is not. `ContentionMonitor.shared` drives an automatic yield and is the other
  singleton the contract names, so a suite setting contention rather than calling `pause()`
  directly would produce the same park. Name it, rather than fixing the symptom.
- **Do not fix this by shortening the backstop.** 900 seconds is a product decision about how
  long a person's pause may hold a run. A test process that inherits a park should not be
  parked at all, and a shorter backstop would turn a hang into a wrong result.
- **A process-wide default is the real defect.** PRO-0046 converted a process-wide `static var`
  seam into a constructor parameter for exactly this reason, and PRO-0047 added
  `TrailIsolation.swift` for the trail's equivalent. Consider whether `Session` should refuse
  to default to a shared latch under test at all, rather than every suite remembering.
- **The wedge is silent, and that is half its cost.** `scripts/test.sh` refuses to score a run
  with no verdict, which is the only reason this was ever seen. Consider whether `checkpoint`
  should log or bound its wait so a parked run says which run parked it and why.

## Not in scope

Changing what pause, yield or the backstop mean. PRO-0018, PRO-0033 and PRO-0037 settled
those; this is about a test process not inheriting one run's park into every later run.
