# Spec PRO-0171 — Every Socket Suppresses SIGPIPE, and a Census Says So

**Brief:** `docs/features-to-triage/163-every-accepted-socket-suppresses-sigpipe.md`
**Status:** Merged
**Created:** 2026-08-26
**Surfaces:** SURF-029
**Defects:** DEF-342, DEF-343

## Context & Purpose
DEF-338 fixed a SIGPIPE termination by setting `SO_NOSIGPIPE`, and justified it with a comment
asserting that an accepted descriptor does not inherit the option from its listener. That
assertion was never measured and is the reverse of Darwin's behaviour, which had two costs: one
socket server that suppressed on neither descriptor stayed reachable, and an audit reading the
tree against the comment counted three defective servers where there was one.

## Acceptance Criteria
1. `ProctorShim/RemoteServer.swift` suppresses SIGPIPE on its listener and on the descriptor it accepts.
2. The inheritance rule is measured across four cells — `AF_UNIX` and `AF_INET`, listener suppressed and bare — and the comment asserting the opposite states what was measured instead.
3. A probe reproduces the fault in a child process, so the child's termination is the observable rather than the test runner's.
4. The probe is run in both directions: terminated by signal 13 with a bare listener, exit 0 with an errno once the listener is suppressed.
5. A census enumerates every `socket()` and every `accept()` under `Sources/` and fails when one carries no suppression within a bounded number of code lines.
6. The census prints its denominator and is armed against the pre-fix tree rather than a fixture.

## Verify
- `swift test --filter AcceptedSocketSignalTests` — 6 tests, 8 cases, exit 0.
- `python3 scripts/campaign/socket_signal_census.py --gate` — exit 0, `PASS: all 9 descriptor(s)`.
- `python3 scripts/campaign/socket_signal_census.py --root <pre-fix tree> --gate` — exit 1, 4 bare.
- `python3 scripts/campaign/sigpipe_disposition_probe.py --family inet` — exit 141.
- `python3 scripts/campaign/sigpipe_disposition_probe.py --family inet --suppress` — exit 0.

## What this deliberately does not do
It does not remove the three redundant suppressions on the servers whose listeners already
carried the option. Inheritance is a platform behaviour rather than a promise — Linux has no
`SO_NOSIGPIPE` and wants `MSG_NOSIGNAL` per send — and the census cannot pair an `accept()`
with the `socket()` that produced its listener across a function boundary, so requiring the
option at both sites is what makes the check decidable.

It does not drive `proctor-shim`'s remote transport into the fault end to end. The probe builds
a listener the same way; nothing has run the real server into it.

**Moves:** none. This spec fixes a defect and adds a census; no warrant class figure moves on it.
