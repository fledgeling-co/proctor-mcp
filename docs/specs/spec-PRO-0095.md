# PRO-0095 — The policy file's mode, a control that scores a red it did not cause, and a sibling to check

**Brief:** `docs/features-to-triage/88-three-that-slipped-the-grouping.md`
**Status:** ready to verify
**Registry ranges:** CASE-0190..0199 · DEF-100..104 · REQ-063..064

Three open defects the wave-13 grouping did not reach. They share no mechanism: one is a file
mode, one is a control that reports a pass from a state it never established, and one is a
record that may already be closed. The brief is explicit that the third is a check before it is
a fix, and that the first is an inconsistency rather than an exposure.

## DEF-068 — the policy file's mode

`PolicyStore.save` creates its directory with `.posixPermissions: 0o700` and then writes the
file with `Data.write(to:options:.atomic)`, which takes the umask default. Measured on this Mac
before the change: `-rw-r--r-- policy.json` inside `drwx------ policy/`. `AuditLog`, forty lines
below in the same file, opens `audit.jsonl`, `audit.lock` and `audit.pub` with an explicit
`0o600` and sets `0o600` on its temporaries.

**What this is not.** The `0700` directory carries the protection today: another user cannot
traverse it to reach the file. So this is an inconsistency with the neighbouring code rather
than an exposure, and it becomes one only when the file is copied, backed up, or the directory's
mode is loosened. The file records which applications an agent may drive, which is why the
inconsistency is worth closing rather than annotating.

**Where the fix goes.** At the write. A file that exists world-readable for an instant has been
world-readable, so a `chmod` after the fact closes a window rather than the defect. `Data.write`
takes no mode argument, so `save` opens its own temporary with `Darwin.open(..., O_CREAT|O_EXCL,
0o600)`, writes it, `fsync`s it, and hands it to `FileManager.replaceItemAt` — the same atomic
same-directory replace the audit rotation and conversion paths already use.

**The upgrade case, which is the part that is easy to get wrong.** DEF-068's own registry entry
names it: an existing `0644` file keeps its mode through an atomic replace on some paths and not
others. `replaceItemAt` preserves the original item's metadata by default, so an operator whose
policy file was created by an earlier build would keep `0644` forever. `.usingNewMetadataOnly`
is what makes the new mode win, and CASE-0191 is the case that would have caught its absence.

## DEF-075 — a control that scores a red it did not cause

`vacuity-check.py --seed-strengthen` prints `The gate bites` from `before=red after=red`. The
control exists to prove a census pass can go from clear to red under a strengthened constraint.
A run that starts red has established nothing about the seeding, and reporting it as a pass is
the control failing in the one direction a control must not.

The fix is a precondition: refuse unless `before` is clear, and name the state found.

**Where the fix goes, and why not the plugin cache.** `vacuity-check.py` lives only at
`~/.claude/plugins/cache/fledgeling-plugins/test-campaign/0.9.4/skills/test-campaign/scripts/`,
which this repo does not own and which is live for every project on this machine. The repo has
already decided this exact question once. `scripts/campaign/seed_unclass.py` says so in its own
docstring: *"It lives here rather than as a patch to `vacuity-check.py`, which sits in a plugin
cache this repo does not own — a fix there is reverted by the next plugin update with nothing
saying so."* That decision stands, so the refusal lands in `scripts/campaign/seed_strengthen.py`
beside its sibling, resolving the plugin module by newest installed version the way DEF-076's
fix taught `seed_unclass.py` to.

**The alternative, recorded rather than taken.** PRO-0091 fixed DEF-041 in the plugin's *source*
repository at `~/Dev/fledgeling-plugins` and mirrored the bytes into the cache, on the reasoning
that `campaign.py` is a project-agnostic auditor and a missing denominator is a bug in every
consumer. `--seed-strengthen` is the same class of tool, so that is the better long-term home
and it would fix the control for every project rather than for this one. It is not taken here
because it commits into a second, published repository, which is outside this item's worktree
and outside what an unattended run should decide. It is parked as an open decision below rather
than settled silently.

Nothing under `~/.claude/plugins` is modified by this item.

## DEF-043 — check before building

`Session.doctor` blocking a cooperative thread inside `SecStaticCodeCheckValidity` was recorded
as DEF-043, separately from DEF-044. PRO-0087 has since merged: `verdict(for:)` is `async`, a
caller that has to wait leaves a continuation and gives its thread back, and the verification
itself runs on a dedicated `Thread`.

DEF-043 has **no row in this repo's registry**. Its record is prose in a PRO-0083 document that
has not merged to `ai/wave-9`, so there is nothing here to flip to `fixed`. The disposition is
recorded as DEF-100 instead, which is the shape DEF-050 already uses for DEF-044.

**What was already proved, and what was not.** CASE-0115 discriminates whether waiters suspend
or block. CASE-0116 reads the root queue libdispatch reports for the verification itself, and
its own note records the limit: it measures the cache directly, and a saturation test was
drafted and dropped because it holds the process-wide pool. Neither runs through
`Session.doctor`. `concurrentSessionsVerifyOnce` does run through `Session.doctor`, and counts
verifications rather than reading where they ran. The gap is a synchronous wrapper introduced
between `SessionDoctor.swift:237` and the cache — which is precisely the substitution CASE-0116
was built after a reviewer made. CASE-0196 closes it by applying CASE-0116's instrument through
the production path.

**The rest of `doctor`.** Swept for other blocking calls, since the brief asks for a separate
finding if one survives. The path is `accessibilityProbe`, `screenRecordingProbe.state()`
(async and bounded), `secureInputProbe`, `healthSnapshot`, five `ToolProbe.refreshed()` calls,
`actuator.laneHealth` (async), `policyPosture()` and `SwitchStore.load`. The synchronous work is
`stat`, `readlink`, one property-list read and two small file reads; `ToolProbe.xcodeVersion`
parses a plist rather than running `xcodebuild`, and `DoctorSpawnFreeTests` already guards that
nothing on the path creates a process. No second blocking call was found, so no second defect is
raised.

## Acceptance

| # | Clause | Evidence |
|---|---|---|
| A1 | A fresh `policy.json` is `0600` on disk, read with `stat` rather than trusted from the call | CASE-0190 |
| A2 | An existing `0644` `policy.json` is `0600` after the next save | CASE-0191 |
| A3 | The mode is set rather than inherited: `save` under `umask(0)` still yields `0600` | CASE-0192 |
| A4 | The policy still round-trips through the new write path | CASE-0193 |
| A5 | Concurrent saves all complete, so the narrowing did not start refusing a race the old write allowed | CASE-0198 |
| A6 | Three sabotages watched: the pre-fix write, `.usingNewMetadataOnly` dropped, one fixed temporary name | `evidence/PRO-0095/def068-arming.txt` |
| A7 | `--seed-strengthen`'s replacement refuses a baseline that is not clear, naming the state | CASE-0194 |
| A8 | The refusal does not block a legitimate run: a clear baseline still reports the bite | CASE-0195 |
| A9 | The registry is restored byte-for-byte on both paths, verified by SHA-256 | CASE-0196 |
| A10 | The refusal is watched firing against the real registry as it stands | `evidence/PRO-0095/def075-refusal.txt` |
| A11 | Through `Session.doctor`, the verification runs off the cooperative pool | CASE-0197 |
| A12 | DEF-043's disposition recorded with evidence | DEF-100 |
| A13 | `./scripts/test.sh` run rather than cited, with suite counts before and after | `evidence/PRO-0095/gate-after.txt` |

## New registry rows

| Id | What |
|---|---|
| REQ-063 | The policy file is created `0600` at the write, whatever the umask, and an existing wider file is narrowed by the next save |
| REQ-064 | A seeded control refuses to score a red it did not cause: it establishes a clear baseline before mutating, and names the state it found when it refuses |
| DEF-100 | DEF-043's disposition — the doctor path no longer blocks a cooperative thread |

Cases used: CASE-0190..0198, nine of the ten allocated. CASE-0199 is unused.
Defects used: DEF-100 only, of DEF-100..104.

## What the build found that the plan did not predict

Two, both from the tests rather than from review, and both recorded because either would
have shipped.

**The narrowing nearly started refusing concurrent saves.** `Data.write(options: .atomic)`
uses a temporary of its own per call, so two sessions saving at once both succeeded and the
last one won. An explicit `open` with `O_EXCL` on one fixed temporary name turns that into a
thrown error, and two sessions in one agent share `operatorDirectory`, so the race is
reachable. The temporary is now uniquely named per call and CASE-0198 guards it: with the
fixed name put back, 11 of 12 concurrent saves throw.

**The first attempt at cleaning up stale temporaries deleted live ones.** Sweeping the
directory for `policy.json.writing*` on every write removes the temporaries of saves running
at that moment; CASE-0198 read 4 of 12 throwing on its first run. The sweep was reverted
rather than given an age test. What that leaves is litter after a crash mid-write: one small
file, itself `0600` inside the `0700` directory, so untidy rather than a second exposure.
Recorded in CASE-0198's note rather than fixed here.

## Open decision

**Whether `--seed-strengthen` is fixed for every project rather than for this one.** The
control shipped in test-campaign 0.9.4 still reports a bite from `before=red`, and this item
leaves it that way. Fixing it means a commit to `~/Dev/fledgeling-plugins`, whose source and
cache copies are byte-identical today (`573ecd5c`) and whose HEAD is level with `origin`. That
is PRO-0091's recorded route for a project-agnostic plugin tool, and it is a second repository
and a published one, so it is a scope call rather than a technical one. Left for a human.

## What this item does not do

It does not change what the policy file contains or who may write it, and it does not touch the
audit path, which already opens `0600` and is the reference the fix copies. It does not modify
anything under `~/.claude/plugins`. It does not add a saturation test for the cooperative pool:
CASE-0116's note records why one was dropped, and re-adding it would hold the process-wide pool
for seconds in a green run and feed DEF-051.
