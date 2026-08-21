# PRO-0087: the signature cache is per-session and the work it caches is not

**ID:** PRO-0087 · **Status:** Ready to verify · **Created:** 2026-08-21
**Brief:** `docs/features-to-triage/80-the-signature-cache-is-per-session-and-the-work-is-not.md` (Wave 12)
**Branch:** `ai/pro-0087` off `ai/wave-9` · **Lane:** headless, `./scripts/test.sh`
**Defect:** DEF-044, recorded here as DEF-050
**Ledger id:** already allocated by the orchestrator. This item does not write `docs/feature-specs/LEDGER.md`.

## The problem

`SignatureVerdictCache` deduplicates a 0.32-0.39 s code-signature check per instance, and
`ToolProbes` built one instance per `Session`. The verdict is a pure function of a file's identity,
so every session on the machine holds a separate cache of the same answer and pays for it
separately. Fifteen sessions verifying one 82 MB binary at once is fifteen cooperative threads
inside `SecStaticCodeCheckValidity`, which leaves `Server.dispatchBlocking` no thread for its
`Task.detached` and a peer with a 10 s `SO_RCVTIMEO` unserved.

The file's own header argued the opposite: that two callers both verifying on a cold cache was
"wasted work and nothing else", and that single-flight "would buy one saved hash and a state
machine to get wrong". Both halves assumed there were two callers. Scope is what makes fifteen.

Reproduced in this worktree on 2026-08-21 before any change. Three full-suite runs with PRO-0083's
witness suites present: two green in 21 s and 23 s, the third hung. Two `sample` captures five
minutes apart found **15 of 22 threads inside `SecStaticCodeCheckValidity`**, each on
`com.apple.root.default-qos.cooperative`, each blocked in `Security::Dispatch::Group::wait()` for
the whole of a five-second sample. The run never produced a verdict line and was killed after six
minutes. Samples: `docs/test-campaign/evidence/PRO-0087/wedge-before.txt` and `-2.txt`.

## The behaviour

A verdict is asked for once per file identity per process, whether one caller asks or fifteen ask
at the same moment.

- **Scope.** `SignatureVerdictCache.shared` is the store `ToolProbes` takes by default. Every
  session in a process therefore reads and writes one store.
- **Single flight, without holding a thread.** A caller arriving on an identity another caller is
  already verifying joins that verification rather than starting a second one. Fifteen callers on a
  cold entry are one verification and fourteen waiters, and every one of those waiters is a
  suspended task rather than a blocked thread: `verdict(for:)` is `async`, a waiter leaves a
  continuation behind, and the verification runs on a `Thread` of its own, off the cooperative pool.
- **Keying.** By `FileIdentity` — device, inode, size, mtime, ctime — as before. `stat` follows
  symlinks, so `~/.local/bin/cua-driver` and the binary it points at are one entry rather than two.
- **Capacity.** Sixteen entries, oldest evicted first. The store outlives every session now, and a
  rebuilt binary is a new identity, so without a bound a long-lived agent accumulates one entry per
  rebuild.
- **The seam.** `init(identify:verify:)` still takes both halves and `ToolProbes` still takes the
  cache, so a caller that passes one gets an isolated store. A shared default, not a singleton.

### Edge cases

A file replaced mid-flight is a different identity, so the two verifications proceed independently
and neither returns the other's verdict; the later write wins the entry and the earlier identity is
re-verified on its next ask. A spurious wake or an eviction between broadcast and wake re-reads the
answer from the top rather than assuming it. An absent, empty or nil path is `.notChecked` without
touching the lock, as before.

### Failure modes

A slow verification costs the callers that asked for it and costs the rest of the process nothing.
That is the property being bought, and it is not what the obvious fix delivers.

Deduplicating fifteen verifications down to one and having the other fourteen block on a condition
variable was built first, and measured. It cut the work and left the wedge: a run hung with that
version, and the sample showed all sixteen cooperative threads blocked, fifteen of them in the
cache's own wait and one in `Security::Dispatch::Group::wait()`, with no non-cooperative
`com.apple.root.default-qos` worker thread anywhere in the process. The pool is capped at the core
count and does not replace a worker that blocks, so a blocked pool cannot lend Security's own
dispatch group the thread it is waiting for. Fifteen threads waiting on one verification starve it
exactly as fifteen threads running one did. Recorded in
`docs/test-campaign/evidence/PRO-0087/wedge-after-blocking.txt`, and guarded by a test that goes red
rather than hanging.

The Swift compiler agrees, and says so: `NSCondition.lock()` is unavailable from an asynchronous
context. The original cache escaped that check only by being a synchronous function called from
one.

What remains: a verification that never returns leaves its waiters suspended for as long as it
runs. Nothing else in the process is affected, and no thread is held, but those callers get no
verdict until it lands. There is no timeout on the check, deliberately — a signature check that
gave up early would report `unreadable` for a file it had not finished reading.

## What this does not change

The verification itself, its cost, and what `verifyCua` checks. The forged peer's 10 s timeout —
raising it would move the gate rather than close the defect. `Server.dispatchBlocking`'s
`Task.detached`, which is not what starved the pool.

## Acceptance

1. Fifteen concurrent callers on one cold identity produce exactly one verification, counted by
   `verificationCount`, which the production path increments.
2. Eight concurrent sessions calling `doctor` against one path produce one verification between
   them, through `Session.doctor` → `SessionDoctor` → `ToolProbes.cuaSignature`.
3. Two independently constructed `ToolProbes` hold the same cache, and one handed a cache holds
   that one.
4. With more callers than the cooperative pool is wide waiting on one verification, unrelated work
   still runs to completion while that verification is parked.
5. The verification itself runs off the cooperative pool: libdispatch reports the caller on
   `com.apple.root.default-qos.cooperative` and the verification on an overcommit root queue, so a
   substitution that puts it back on the width-capped pool is red. Clause 4 does not cover this —
   waiters suspend either way — and the two were treated as one until a reviewer measured the
   difference.
6. The full suite green across a stated run count with its denominator, with PRO-0083's witness
   suites present, and REQ-035's forging arm answering on every run that completes.
