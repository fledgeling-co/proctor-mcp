---
sources: [REQ-063, REQ-064, DEF-043, DEF-068, DEF-075]
---
# The policy file's mode, a control that lies twice, and a sibling already fixed

**Wave 13, brief 8.** DEF-068, DEF-075, DEF-043. Three open defects the earlier grouping did not
reach. Small, and one of them closes by inspection.

## DEF-068 — `policy.json` is world-readable where its neighbours are 0600

`PolicyStore.save` creates its directory with `.posixPermissions: 0o700`, then writes the file with
`Data.write(to:options:.atomic)`, which takes the umask default. Measured on this Mac:
`-rw-r--r-- policy.json` inside `drwx------ policy/`.

`AuditLog`, in the same file, opens `audit.jsonl`, `audit.lock` and `audit.pub` with an explicit
`0o600` and sets `0o600` on its temporaries. Measured: `-rw------- audit.jsonl`.

**Do not overstate this.** The `0700` directory carries the protection — another user cannot
traverse it to reach the file — so it is an inconsistency rather than an exposure today. It becomes
one the moment the file is copied, backed up, or the directory's mode is loosened by anything, and
the file records which applications an agent is allowed to drive. The neighbouring code already
shows the intended standard, so matching it costs one options argument.

Fix it at the write, not by chmod afterwards: a file that exists world-readable for an instant has
been world-readable. `Data.write` takes no mode, so this needs the same explicit `open` the audit
path already uses, or a mode set on the temporary before the atomic replace.

## DEF-075 — the control reports success from a state where it proved nothing

`vacuity-check.py --seed-strengthen` prints **"The gate bites"** from `before=red after=red`.

The control exists to prove a gate can go from clear to red. A run that starts red and ends red has
demonstrated nothing about the seeding, and reporting it as a pass is the control lying in the one
direction a control must not. PRO-0091 found this in its own work and recorded it rather than
quietly fixing it, which is why it is here rather than lost.

The fix is a precondition: refuse unless `before` is clear, and say which state it found. A control
that cannot tell "the gate bit" from "the gate was already red" is not a control.

This compounds with DEF-030, already briefed in `84`: that control arms one of the gate's two
passes. Between them the census's arming story is weaker than its output suggests, and both belong
to whoever takes `84`.

## DEF-043 — check before building anything

`Session.doctor` blocks a cooperative thread inside `SecStaticCodeCheckValidity`, and fourteen such
calls saturate the pool. That is DEF-044's sibling and was recorded separately.

PRO-0087 merged and made `verdict(for:)` async: waiters leave a continuation and give the thread
back, and the verification runs on a dedicated `Thread`. CASE-0116 guards the execution context by
reading the root queue libdispatch reports. Measured after the merge: three consecutive green suite
runs at load average 875, where the pre-fix tree deadlocked at 465 with sixteen doctor-family tests
parked on that exact stack.

So the first job here is to **check whether DEF-043 is already closed** rather than to fix it.
`SessionDoctor.swift:237` is the only production call site of `verdict(for:)`. If the path no longer
blocks, close the record with the evidence; if some other part of `doctor` still blocks, that is a
separate finding and it gets its own detail rather than inheriting DEF-044's.

## The conversion contract

- `policy.json` written `0600` at creation, with a test reading the mode off disk rather than
  trusting the call, and a sabotage showing the test fails against the umask default.
- `--seed-strengthen` refuses a run whose `before` is not clear, naming the state it found, with the
  refusal watched firing.
- DEF-043 closed with evidence or re-detailed as its own defect.
- `./scripts/test.sh` green, suite count before and after.

## What this brief does not do

It does not change what the policy file contains or who may write it, and it does not touch the
audit path, which already does the right thing and is the reference here.
