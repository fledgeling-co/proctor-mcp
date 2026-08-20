# The ten external effects a capped gate output hid

**Wave 11, brief 7 of 7.** Reads `70` for the rung's contract. Sequence after PRO-0077 and
PRO-0078 have merged, so the four witnesses already built are the pattern to copy rather than a
thing to re-derive.

## How this brief came to exist, which is the finding

Briefs `70` and `71` between them named twelve requirements, because `campaign.py check` printed
twelve. The gate caps that list at twenty per pass and the effect-boundary section at twelve, and
the printed list was read as the population.

There are **22 external requirements**. PRO-0077 addressed four and PRO-0078 addressed eight, so
ten were never named by any item in the wave: REQ-023, 024, 027, 028, 029, 033, 034, 035, 037, 039.

That is the campaign's own first failure mode — covering a subset and reporting it as the whole —
arriving through the gate rather than through a surface map. It is worth recording plainly rather
than quietly fixing, because the fix is not "read more carefully": it is that a number taken from
a tool's display is not a denominator, and the denominator here was one `len()` away the whole
time. PRO-0077's runner caught it, from arithmetic rather than from the gate.

## The ten

| Req | Effect | What it claims | Provider |
|---|---|---|---|
| REQ-023 | `ipc` | `ProctorReflector` reads resolved constraints, colours and CALayer models | `Darwin.bind/listen/accept` in `ProctorReflector/SocketServer.swift` |
| REQ-024 | `subprocess` | web URLs route to Obscura or the cua driver | `Process()` in `Actuation/CuaClients.swift` |
| REQ-027 | `ipc` | the window stops claiming ready when the agent holds the socket and never answers | agent socket |
| REQ-028 | `device` | every overlay Proctor draws is excluded from screen capture unless lifted | `SCStream`/`SCShareableContent` |
| REQ-029 | `ipc` | an operator over SSH watches and halts a run on a Mac with no window server | agent socket |
| REQ-033 | `ipc` | a supervision client reads readiness, switches and history, not only run and queue | agent socket |
| REQ-034 | `ipc` | 21 verbs from the tool catalogue, six exit codes, generated completion | agent socket |
| REQ-035 | `ipc` | a CLI call is not a privilege bypass, and the trail records which front end called | `LOCAL_PEERPID getsockopt` in `SessionIdentity.swift` |
| REQ-037 | `ipc` | a session attaches to a macOS guest and executes its steps inside it | agent socket |
| REQ-039 | `subprocess` | the pool never evicts a guest a person started or another session holds | `Process()` in `Guest/GuestProvider.swift` |

## What is cheap here and what is not

**Six of the ten are the same socket, and PRO-0077 already built its witness.** REQ-027, 029, 033,
034 and 037 all rest on the agent's `AF_UNIX` socket, whose witness is CASE-0062: connections the
server answered, counted server-side, with peer identity read off each accepted fd. Each of the
five needs its own case rather than a shared one — they are different guarantees over one
provider, and a single case would let one guarantee's silence hide behind another's noise — but
each is that pattern with a different driver on the near side. Do not add an `onAccept` seam; the
grok lane settled that for CASE-0062 and the reason still holds.

**REQ-035 is the sharpest and should be done first.** It claims the audit trail records which
front end called, *read from the peer process rather than from the request*. A witness has to prove
the recorded caller is the real peer, which means driving it from two genuinely different front
ends and reading the trail off disk. It is the one requirement here where a wrong answer is a
security answer: the whole claim is that a CLI call cannot claim to be something else.

**REQ-023 is a second socket** — `ProctorReflector`'s own, not the agent's. Same shape, different
listener, and worth its own case for exactly that reason.

**REQ-024 and REQ-039 are subprocess**, so PRO-0077's sentinel pattern applies directly.

**REQ-028 is the one to be careful with.** It claims Proctor's overlays are excluded from capture,
and PRO-0078 found that `proctor_capture` reported `status: complete, trustworthy: true` over a
fully transparent frame of a Proctor-owned window. Those two facts are the same mechanism seen from
two sides: the exclusion works, and the capture path does not notice when exclusion is all it got.
Witness the exclusion — and do not let a transparent frame stand as evidence that anything was
drawn. A witness here must show a non-Proctor window captured with content AND the overlay absent
from it, or it proves nothing that a blank frame would not also prove.

`sharingType = .none` on the HUD and takeover overlay is correct and is not a defect to fix.
Evidence must not change because somebody was watching.

## The conversion contract

- Ten cases, one per requirement, each with a recorder, an effect class, a non-zero count and its
  own sabotage run. No shared case across two requirements.
- REQ-028's witness shows content in the frame as well as the overlay's absence.
- The census's own denominator recorded as `len()` of the external set rather than as whatever the
  gate printed, in `REPORT.md`, so this brief's cause cannot recur silently.
- `./scripts/test.sh` green, suite count before and after.

## What this brief does not do

It does not revisit REQ-007, which PRO-0078 recorded `inconclusive` on a real ceiling — `isAPerson`
requires `sourcePid == 0`, unforgeable from any process. A ceiling that was measured stays
measured.
