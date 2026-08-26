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
    0    every write returned, or returned EPIPE — the process survived
    2    the peer or the listener could not be set up; nothing was measured
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
import struct
import sys
import tempfile

SO_NOSIGPIPE = 0x1022


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--family", choices=("unix", "inet"), default="inet")
    ap.add_argument("--suppress", action="store_true")
    ap.add_argument("--writes", type=int, default=40)
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
            # A TCP close() sends FIN, and the server may keep writing into the
            # loopback buffer for a long time before anything comes back. SO_LINGER
            # at zero makes close() send RST instead, which is what a peer that
            # died rather than hung up looks like — and it is the condition under
            # which the next write fails rather than the fortieth. Measured: with
            # a plain close, forty 4 KiB writes all returned on AF_INET.
            client.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER,
                              struct.pack("ii", 1, 0))
            client.connect(listener.getsockname())
        accepted, _ = listener.accept()
    except OSError as exc:
        print(f"setup failed: {exc}", file=sys.stderr)
        return 2

    print(f"family={a.family} listener_opt="
          f"{listener.getsockopt(socket.SOL_SOCKET, SO_NOSIGPIPE)} accepted_opt="
          f"{accepted.getsockopt(socket.SOL_SOCKET, SO_NOSIGPIPE)}")

    client.close()               # the peer hangs up
    payload = b"A" * 4096
    for attempt in range(a.writes):
        try:
            accepted.send(payload)   # the write after the FIN is the one that fails
        except OSError as exc:
            # EPIPE when the FIN was seen and the write is the one after it;
            # ECONNRESET when the peer's RST arrived first. Both are "an error
            # return rather than a signal", which is the whole claim — and on
            # AF_INET which one you get is a race with the RST, so a test that
            # demands EPIPE specifically is flaky. Measured: 4 EPIPE and 1
            # ECONNRESET over five consecutive runs.
            name = errno.errorcode.get(exc.errno, str(exc.errno))
            print(f"{name} on write {attempt + 1}; the process survived")
            return 0
    print(f"all {a.writes} writes returned; the process survived")
    return 0


if __name__ == "__main__":
    sys.exit(main())
