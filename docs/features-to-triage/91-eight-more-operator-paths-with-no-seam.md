---
sources: [REQ-085, REQ-086, DEF-042, DEF-142, DEF-164]
---
# Eight more operator paths with no seam

**Wave 15, brief 1.** The class behind DEF-042, DEF-142 and DEF-164, swept rather than met a fourth
time by accident.

## Why this is a sweep and not a fourth fix

Three defects in this campaign are one shape: **a static that computes a path under the operator's
Application Support directory, with no injection seam, so the suite writes there.** They were found
three different ways and none of them was by looking:

- **DEF-042** (`PolicyStore`) came from a brief that happened to ask about test seams.
- **DEF-142** (the capture path) came from narrowing REQ-055's sentence to match its witness, which
  made the witness able to bite.
- **DEF-164** (`FlowStore`) came from that narrowed claim continuing to bite on the next run.

A fourth would be found the same way — by accident, later, after it had been writing for weeks. The
capture path had been writing four PNGs per run since PRO-0089 and the flow store two files per run,
and both were invisible until something else forced a look.

## The measurement

`grep -rn "Application Support" Sources/` names **eleven files**. Three carry the
`AuditLog.isTestProcess` interlock; **eight do not**:

| File | What the path is for |
|---|---|
| `ProctorCore/SwitchStore.swift` | `…/settings` — **operator settings, written** |
| `ProctorAgent/Session/SessionMaestro.swift` | `…/maestro` |
| `ProctorAgent/Session/SessionIOSProcess.swift` | `…/captures` |
| `ProctorCore/GuestInventory.swift` | `…/guests/<handle>`, and the agent socket |
| `ProctorCore/Wire.swift` | the agent socket |
| `ProctorReflector/ProctorReflector.swift` | the app-support root |
| `ProctorCore/TUISurface.swift` | a displayed path |
| `ProctorCore/ToolCatalogue.swift` | prose in a tool description |

**`SwitchStore` is the sharp one.** It writes the operator's settings, which is the same kind of
state `PolicyStore`'s defect was about — a suite run that changes what the agent is allowed to do,
silently, on the machine of whoever ran it.

## What to do, and what not to

**Class every one of the eight before changing any.** The last two are almost certainly not defects:
a path in a tool's prose describes where a file lives, and a displayed path is a string a person
reads. A socket path is connected to rather than written, so it belongs in a third class again. Say
which class each falls in and why, and convert only the writers.

**Do not add the interlock everywhere as a precaution.** `AuditLog.isTestProcess` exists so a test
process diverts; adding it to a read path buys nothing and adds a branch that production takes on
every call. The three existing interlocks are the pattern for a **writer**, and
`PolicyStore.live` / `FlowStore.directory` are the shape to copy: `guard AuditLog.isTestProcess else
{ return operatorDirectory }`, with `operatorDirectory` a verbatim move of the pre-change body so
production behaviour is unchanged by construction.

**Prove production is unchanged the way DEF-164 was proved.** Its verifier forced the else branch
with a `guard false` sabotage and read the resolved path back character for character against the
pre-change literal. That is stronger than reading the diff, and it is the standard here.

**Prove the diversion positively, not just the absence.** DEF-164's verifier took sha256, mtime and
size of every operator file before and after, ran three full suites and nine filtered ones, found
them byte-identical, **and** showed the same filenames appearing under `proctor-test-flows-*` in
`/tmp`. Absence of the write here and presence of it there. A witness that only shows absence cannot
tell a diverted write from a write that never happened.

**Then close the class rather than the instances.** A test that fails when a new static computes an
operator path without a seam is worth more than eight fixes, because the ninth is what this brief is
about. `scripts/campaign/` is where it belongs, beside `defect_gate.py`.

## The stray files already written

Four zoom PNGs and two flow files are in the operator's directories from earlier runs. They stay.
Deleting them is the act REQ-055 forbids, and the two previous items recorded that reasoning rather
than tidying. If this sweep finds more already written, record them the same way and do not remove
them.

## The conversion contract

- All eight classed as writer, reader, socket or prose, with the reason recorded per file.
- Every writer carries the interlock, with production behaviour proved unchanged by forcing the else
  branch and comparing the resolved path to the pre-change literal.
- A witness per converted writer showing both the absence under the operator's root and the presence
  under the diverted root.
- A check that refuses a new un-seamed operator-path writer, armed against one.
- `./scripts/test.sh` green with the suite count before and after, and `defect_gate.py` exit 0 in
  both modes.

## What this brief does not do

It does not delete anything under the operator's directories, it does not change what any of these
paths resolve to in production, and it does not touch the socket paths' behaviour.
