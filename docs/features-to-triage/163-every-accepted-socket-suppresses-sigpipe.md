---
generated-by: tailings
tailings-sources: [unaimed-site-read]
reckon-sources: [REQ-046]
status: to-triage
---
# Every accepted socket suppresses SIGPIPE, and a check says so

- origin: tailings pass 2026-08-26, unaimed site read · 2026-08-26
- audience: anyone whose process embeds ProctorReflector, and anyone running proctor-shim's TCP listener
- platforms: n/a
- proposed-by-ai: false

## What and why
DEF-338 established that a write to a peer that had closed raised SIGPIPE and terminated the
process at exit 141, and it was fixed by setting `SO_NOSIGPIPE`. The fix reached one of the four
places this package writes to a socket it accepted. `Server.swift:108` carries the rule the fix
rests on — an accepted descriptor does not inherit the option from its listener — and
`Server.swift` is the only file that applies it to both. `ProctorReflector/SocketServer.swift`,
`ProctorAgent/Unlock/UnlockBroker.swift` and `ProctorShim/RemoteServer.swift` each write to an
accepted client that carries no suppression, and `UnlockBroker` calls `send` with flags `0`
rather than `MSG_NOSIGNAL`. That is DEF-342.

The three sites are the work, and the reason this is a brief rather than only a defect is that
nothing would have caught the gap and nothing would catch the next one. A fix applied in one of
four places passed every gate in the repository. A check that walks every `socket()` and every
`accept()` in `Sources/` and asserts a suppression on each is a few lines, and it converts a
defect that was found by reading into one that cannot recur silently.

## Acceptance sketch
- Each of the three unsuppressed accepted descriptors carries a suppression, and `UnlockBroker`
  either suppresses or passes `MSG_NOSIGNAL`
- A test writes twice to a peer that has closed — the second write after the FIN has landed —
  and the process survives, on each of the four servers
- That test is watched to fail with the suppression removed, per server
- A check enumerates every `socket(AF_*)` and every `accept()` under `Sources/` and fails when
  one reaches a write path without a suppression
- The check is armed in both directions: it fires on a seeded unsuppressed socket and stays
  silent on the tree once the three are fixed

## Assumptions made writing this
- Assuming a per-socket `SO_NOSIGPIPE` rather than a process-wide `SIG_IGN`, because a library
  embedded in somebody else's application has no business changing a signal disposition its host
  may depend on — the reason recorded when DEF-338 was fixed
- Assuming the enumeration reads source rather than running, so it costs nothing on every gate
  run; a runtime probe would need four live servers
