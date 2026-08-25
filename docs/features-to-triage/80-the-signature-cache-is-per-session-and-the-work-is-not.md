---
sources: [REQ-035, DEF-044]
status: retired
---
# The signature cache is per-session and the work it caches is not

**Wave 12.** DEF-044. Sequence it before PRO-0083's remaining gap-fix, which cannot close its
security clause reproducibly until this is fixed.

## Why this stopped being a flake

PRO-0083 recorded this as a pre-existing suite wedge and correctly declined to fix it — a
tests-only item does not go changing the actuation path. Its verifier then found the wedge is not
cosmetic: it **prevents REQ-035's guarantee from being exercised at all**.

REQ-035 is the claim that a CLI call cannot claim to be something else — the audit trail records
the caller read from the peer process rather than from the request. Its witness drives a forged
peer that hand-frames a request carrying `"via":"cli"` and asserts the trail row still reads `nil`.
Measured across five verdict-returning runs: **three reported `ForgedCall(answered: false, ok: false)`**.
The forged peer never reached the server, so the guarantee was never tested on those runs.

The assertion fails honestly rather than passing vacuously — `[] != [nil]` — which is the correct
shape and the reason this was caught rather than shipped. But a security guarantee that can only be
verified on two runs in five is not verified.

## The mechanism, read from source

`Sources/ProctorAgent/Session/SignatureVerdictCache.swift` documents its own trade-off at lines
23-25, and the documented decision is sound:

> **The verification runs outside the lock.** Holding it across a 0.39 s hash […] means that two
> callers arriving together on a cold cache may both verify; that is [accepted].

Two callers duplicating a 0.39 s verification is a fine price. The defect is that there are not two.

`ToolProbe.swift:273` default-constructs a `SignatureVerdictCache()` per probe, and a probe is
built per `Session`. So the cache is **per-instance while the work it caches is process-wide**: the
same binary at the same path yields the same verdict for every session on the machine, and fifteen
sessions verify it fifteen times concurrently. A `sample` during a wedge found **15 of 16
cooperative threads parked in `SecStaticCodeCheckValidity` → `Dispatch::Group::wait()`**, none of
them belonging to the test that was hung.

The per-instance single-flight the lock already provides cannot help, because the fifteen callers
are in fifteen different caches. `Server.dispatchBlocking` (`Server.swift:259-270`) hands each
request to `Task.detached`, which then cannot get a thread — and the forged peer's 10 s
`SO_RCVTIMEO` expires before it is served.

The measured cost is real and is why the cache exists at all: verifying an 82 MB binary costs
0.32-0.39 s, recorded 2026-08-15. Fifteen of those at once is five seconds of the cooperative pool.

## What to build

**Make the dedupe process-wide rather than per-instance.** The verdict is a pure function of the
file identity, which the cache already reads through `FileIdentity.read`, so two sessions asking
about the same unchanged binary must share one verification. Keep the existing shape — verification
outside the lock, no `await` in the critical section, so it still cannot deadlock against the
reentrant actor — and change what the cache is keyed and scoped by, not how it locks.

An in-flight table matters as much as a result cache: fifteen callers arriving on a cold entry
should produce one verification and fourteen waiters, not fifteen verifications. That is the whole
of the fix, and a result cache alone does not deliver it.

**Keep injection working.** `init(identify:verify:)` exists so tests can supply both halves, and
`ToolProbe` takes the cache as a parameter. A process-wide store must not make the seam
untestable — a shared default with an injectable override is the shape, not a hard singleton.

## How to know it worked

- A test that drives N sessions concurrently against one path and asserts `verify` ran **once**,
  with the recorder being a counter the production path increments rather than a value the test
  wrote.
- The full suite green across a run count with its denominator stated. PRO-0083 measured 2 green of
  4 with its suites present and 2 of 2 without; the fix should move the first number and the report
  should say what it moved to.
- PRO-0083's REQ-035 forging arm reporting `answered: true` across repeated runs. That is the
  reason this item exists, so it is the acceptance evidence rather than a side effect.

## What this brief does not do

It does not change the verification itself, the 0.39 s cost, or what `verifyCua` checks. It does not
relax the forged peer's 10 s timeout — raising a timeout to hide a starvation is the gate moving
rather than the defect closing. And it does not touch `Server.dispatchBlocking`'s use of
`Task.detached`, which is correct; the pool is starved by the fifteen verifications, not by the
dispatch.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-035
- surface: SURF-012, SURF-018
- cases: CASE-0017, CASE-0018, CASE-0044, CASE-0045, CASE-0046, CASE-0057
- rungs reached: effect-witness, metamorphic, outcome
- provider: LOCAL_PEERPID getsockopt in Sources/ProctorAgent/SessionIdentity.swift
