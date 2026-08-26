---
generated-by: tailings
tailings-sources: [unaimed-site-read]
reckon-sources: [REQ-046]
status: triaged
---
# Every accepted socket suppresses SIGPIPE, and a check says so

- origin: tailings pass 2026-08-26, unaimed site read · 2026-08-26
- audience: anyone whose process embeds ProctorReflector, and anyone running proctor-shim's TCP listener
- platforms: n/a
- proposed-by-ai: false

## What and why
DEF-338 established that a write to a peer that had gone raised SIGPIPE and terminated the
process at exit 141, and it was fixed by setting `SO_NOSIGPIPE`. `Server.swift` justified the
fix with a comment asserting that an accepted descriptor does not inherit the option from its
listener. Nobody had measured that, and on Darwin 25.6.0 it is the reverse: an accepted
descriptor inherits the option on `AF_UNIX` and `AF_INET` alike, and inherits its absence too.

Two things follow. `ProctorShim/RemoteServer.swift` suppressed on neither its listener nor the
descriptor it accepted, and writes the HTTP reply down that descriptor, so a model on another
machine whose connection dies mid-reply terminated proctor-shim by signal. And an audit reading
the tree against the false comment counted three defective servers where there was one, because
a correct pattern read as evidence of a fault.

The work is the fix, the measurement that settles the rule, and a census that makes a fix
applied in one of four places visible — because that gap passed every gate in the repository.

## Acceptance sketch
- `ProctorShim/RemoteServer.swift` suppresses on both its listener and the descriptor it accepts
- The inheritance rule is measured across four cells — two families by suppressed and bare — and
  the comment that asserted the opposite is corrected to what was measured
- A probe writes into a hung-up peer in a child process and the child's ending is the result:
  terminated by signal 13 bare, exit 0 with an errno once the listener is suppressed
- A census enumerates every `socket()` and every `accept()` under `Sources/` and fails when one
  has no suppression within a window of code lines
- The census is armed against the real pre-fix tree rather than a fixture, and names the
  descriptors that were bare

## Assumptions made writing this
- Assuming a per-socket `SO_NOSIGPIPE` rather than a process-wide `SIG_IGN`, because a library
  embedded in somebody else's application has no business changing a signal disposition its host
  may depend on — the reason recorded when DEF-338 was fixed
- Assuming the enumeration reads source rather than running, so it costs nothing on every gate
  run; a runtime probe would need four live servers
