#!/usr/bin/env python3
"""Write into a hung-up peer and let the default disposition decide the exit.

DEF-338 was measured as a process terminating at **exit 141** — 128 + SIGPIPE.
Reproducing that inside a test runner kills the runner, which is what happened
when this was first attempted in-process: `swift test` came back
`exited with unexpected signal code 13` and the four passing tests in the same
suite were reported as a failed run. Blocking the signal on the writing thread
with `pthread_sigmask` did not hold it either.

So the fault is measured in a child, where terminating is the observable rather
than the accident. The caller reads `-signal.SIGPIPE` back from `wait` and the
runner survives.

    python3 sigpipe_disposition_probe.py --family inet [--suppress]

Exit codes
    0    the writes returned errors and the process survived — the option held
    2    the peer or the listener could not be set up, or no write errored at
         all, so nothing was measured either way
    -13  (as `wait` reports it) the kernel raised SIGPIPE and the default
         disposition terminated this process. That is the fault.

`--suppress` sets SO_NOSIGPIPE on the LISTENER only, which is what three of
this package's four socket servers do. Measured on Darwin 25.6.0, an accepted
descriptor inherits it, so `--suppress` is expected to survive and the bare run
is expected to die. Run both: a probe that only ever dies proves nothing about
the option.
"""
from __future__ import annotations

import argparse
import errno
import os
import signal
import socket
import sys
import tempfile
import time

SO_NOSIGPIPE = 0x1022


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--family", choices=("unix", "inet"), default="inet")
    ap.add_argument("--suppress", action="store_true")
    # Every write is attempted, errors included. Stopping at the first error is
    # what made this probe non-deterministic on AF_INET: the first write after a
    # close can return ECONNRESET, which is an error return rather than a signal,
    # and the run then reported the fault as absent. Measured over six trials
    # each way — stopping at the first error gave SIGPIPE 4 times in 5, and
    # writing through gave it 6 times in 6. The rule behind it is the one
    # DEF-338 already recorded: one send into a closed peer gets an errno back,
    # and the signal needs a second write after the peer is known gone.
    ap.add_argument("--writes", type=int, default=60)
    a = ap.parse_args()

    # Python installs SIG_IGN for SIGPIPE at startup so that a broken pipe
    # surfaces as an exception. Put the C default back, because the default is
    # exactly what is under measurement.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

    try:
        if a.family == "unix":
            path = os.path.join(tempfile.mkdtemp(), "s")
            listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            if a.suppress:
                listener.setsockopt(socket.SOL_SOCKET, SO_NOSIGPIPE, 1)
            listener.bind(path)
            listener.listen(4)
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.connect(path)
        else:
            listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            if a.suppress:
                listener.setsockopt(socket.SOL_SOCKET, SO_NOSIGPIPE, 1)
            listener.bind(("127.0.0.1", 0))
            listener.listen(4)
            client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            client.connect(listener.getsockname())
        accepted, _ = listener.accept()
    except OSError as exc:
        print(f"setup failed: {exc}", file=sys.stderr)
        return 2

    print(f"family={a.family} listener_opt="
          f"{listener.getsockopt(socket.SOL_SOCKET, SO_NOSIGPIPE)} accepted_opt="
          f"{accepted.getsockopt(socket.SOL_SOCKET, SO_NOSIGPIPE)}")

    client.close()               # the peer hangs up
    # Let the FIN land before the first write. On AF_INET the first write is
    # what provokes the RST, and the write after that is the one the kernel can
    # answer for; without a settle the whole loop can complete into a buffer
    # that has not heard back yet, and the run measures nothing.
    time.sleep(0.1)
    payload = b"A" * 4096
    first: tuple[int, int] | None = None
    errors = 0
    for attempt in range(a.writes):
        try:
            accepted.send(payload)
        except OSError as exc:
            # EPIPE when the FIN was seen and this is a write after it;
            # ECONNRESET when the peer's RST is delivered as this write's error.
            # Both mean the peer is gone, which is why neither ends the loop:
            # only the write AFTER the connection is known dead raises the
            # signal, so returning on the first errno reports the fault absent
            # about one run in five.
            errors += 1
            if first is None:
                first = (attempt + 1, exc.errno)
        else:
            # A write that succeeded means the far end has not answered yet.
            # Pause so the next one is asked after the RST rather than beside it.
            time.sleep(0.02)
    if first is None:
        print(f"all {a.writes} writes returned with no error; nothing was measured")
        return 2
    name = errno.errorcode.get(first[1], str(first[1]))
    print(f"{name} on write {first[0]}, {errors} of {a.writes} writes errored; "
          f"the process survived")
    return 0


if __name__ == "__main__":
    sys.exit(main())
