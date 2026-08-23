---
sources: [REQ-055, REQ-056, DEF-029, DEF-042, DEF-051]
---
# A test that writes the operator's real policy, and tests that assert a wall clock

**Wave 13, brief 2 of 6.** DEF-042 and DEF-029/DEF-051. Two unrelated defects sharing one property:
both are the suite doing something to the machine it runs on rather than to the product.

## DEF-042 — a test configures the operator's real policy file

`PolicyStore` has no test seam, so a test that configures the policy **writes the operator's actual
policy**. Anyone running `./scripts/test.sh` on their own Mac has their Proctor policy mutated by
the suite.

This is the sharpest item in this wave. A test suite that edits the machine's real configuration is
a hazard rather than an inconvenience: it can change what the agent is allowed to do, it does so
silently, and the person running the suite has no reason to expect it. Treat it as the first thing
to fix in this brief.

The shape of the fix is already in this repo twice. `SignatureVerdictCache` takes
`init(identify:verify:)` so a test can supply both halves, and `GuestProvider` takes
`init(executable:timeoutMs:run:)` beside a convenience initialiser binding the live implementation.
`PolicyStore` needs the same: a root it is told rather than one it assumes, with the production call
site supplying the real path and every test supplying a temporary one.

Do not fix this by having tests write and then restore the real file. A restore that does not run —
because the process was killed, because an assertion threw — leaves the operator's policy changed,
and the failure mode is invisible.

## DEF-029 and DEF-051 — an oracle that is a wall clock

`ScreenRecordingProbeWiringTests.swift:42` asserts `elapsed < 5.0` against real elapsed time.
Measured failing at **5.6s, 6.1s, 6.58s, 8.13s, 10.25s and 14.73s** across this wave, on a machine
whose load ranged 11 to 900. The same test passes in 1.8s alone.

The test's own comment reads: *"The bound is a bound, not a hope. Generous headroom so this does not
flake on a loaded machine."* The measurements falsify the comment. Six recorded failures is not a
flake, it is an oracle that measures the machine rather than the product.

**Raising the bound is not the fix and is explicitly out of scope.** A bigger number fails less
often on this machine and says nothing more about the product; that is the gate moving. What the
test means to prove is that *a platform call that never answers returns `unconfirmed` within its
bound* — a claim about the bound mechanism, which can be tested by injecting a clock or a
never-answering probe and asserting the mechanism fired, with no dependence on how busy the machine
is.

Two other tests in this repo already assert wall-clock elapsed. Find them with a grep for `elapsed`
against a numeric literal and convert them together, or record why one genuinely needs real time.

## The conversion contract

- `PolicyStore` takes its root by injection; the production call site supplies the real path; a test
  proves that with the seam pointed at a temporary directory the operator's real policy file is not
  touched — asserted by reading its mtime and bytes before and after, not by trusting the seam.
- The bounded-probe test asserts the bound mechanism fired rather than how long it took, and runs
  green under load. Prove it by running the suite while the machine is deliberately busy and stating
  the run count.
- Every remaining wall-clock assertion converted or individually justified in the report.

## What this brief does not do

It does not touch `SignatureVerdictCache` or the cooperative-pool starvation; PRO-0087 owns that.
It does not raise any timeout.
