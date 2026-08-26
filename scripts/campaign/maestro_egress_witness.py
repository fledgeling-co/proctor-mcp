#!/usr/bin/env python3
"""What the Maestro lane still reaches, with the variable Proctor sets already set.

DEF-339. `maestro --version` — an invocation that prints a string and runs no
flow — opened TWO outbound TLS connections when this was first measured, one to
a Google Cloud address and one to AWS. `MAESTRO_CLI_NO_ANALYTICS=1` stops the
AWS one. The other happens anyway, and Proctor cannot stop it without rewriting
`~/.maestro/analytics.json`, which belongs to whoever set the machine up and
which PRO-0023 rules out touching.

So the row is `partially-fixed`, and what it owes is a REPRODUCTION for the half
that was not repaired — a measurement somebody can re-run rather than a sentence
recording what was once seen.

HOW IT MEASURES. `lsof -p <pid>` over the child's own pid while it runs, taking
established or in-progress outbound TCP. Not a packet capture: that needs root
here, and the question is only how many peers this process reaches, which the
process table answers. Both arms run, because a probe that only ever sees the
suppressed case cannot tell a working variable from a machine with no network.

WHAT IT SENDS. Exactly what the lane already sends on every invocation, which is
the subject. Nothing of this repository's is transmitted; `--version` runs no
flow and reads no file of ours.

    python3 scripts/campaign/maestro_egress_witness.py [--json OUT]

Exit codes
    0   measured — both arms ran and the suppressed arm reaches fewer peers
    1   the suppressed arm reaches as many peers as the bare one, so the
        variable Proctor sets is doing nothing and the disclosure is wrong
    2   maestro is not installed, or neither arm produced a reading, so nothing
        was measured either way
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PEER = re.compile(r"->(\d+\.\d+\.\d+\.\d+):(\d+)\s+\((ESTABLISHED|SYN_SENT)\)")


def peers_of(pid: int) -> set[tuple[str, str]]:
    # `-a` is load-bearing: lsof ORs its selections by default, so
    # `-p PID -iTCP` means "this process OR any TCP" and returns the whole
    # machine. Measured without it: 64 peers for `maestro --version`, including
    # this session's ssh, Mail's IMAP, a MongoDB cluster and the MCP router on
    # loopback. A count that large reads as a finding rather than as a bug in
    # the instrument, which is what makes it worth the comment.
    out = subprocess.run(["lsof", "-nP", "-a", "-p", str(pid), "-iTCP"],
                         capture_output=True, text=True)
    return {(m.group(1), m.group(2)) for m in PEER.finditer(out.stdout)}


def run_arm(binary: str, suppress: bool) -> dict:
    """Run `maestro --version` and watch its own outbound TCP while it lives."""
    env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin",
           "HOME": str(Path.home())}
    if suppress:
        env["MAESTRO_CLI_NO_ANALYTICS"] = "1"

    seen: set[tuple[str, str]] = set()
    proc = subprocess.Popen([binary, "--version"], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def watch() -> None:
        # Poll while the child lives. A connection opened and closed between two
        # polls is missed, which makes every count here a FLOOR rather than a
        # total — said plainly because an undercount that reads as a total is
        # the shape this campaign keeps finding.
        while proc.poll() is None:
            seen.update(peers_of(proc.pid))
            time.sleep(0.05)

    watcher = threading.Thread(target=watch, daemon=True)
    watcher.start()
    out, err = proc.communicate(timeout=120)
    watcher.join(timeout=2)
    return {"suppressed": suppress, "exit": proc.returncode,
            "peers": sorted(f"{h}:{p}" for h, p in seen),
            "version": (out.decode(errors="replace").strip().splitlines() or [""])[0]}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json")
    a = ap.parse_args()

    binary = shutil.which("maestro", path="/opt/homebrew/bin:/usr/local/bin:/usr/bin")
    if not binary:
        print("maestro is not installed on this machine, so nothing was measured. "
              "An absent tool is a lane failure, not a pass.")
        return 2

    bare = run_arm(binary, suppress=False)
    time.sleep(1.0)
    suppressed = run_arm(binary, suppress=True)

    print(f"maestro at {binary} — {bare['version'] or '(no version line)'}")
    for arm in (bare, suppressed):
        label = "MAESTRO_CLI_NO_ANALYTICS=1" if arm["suppressed"] else "bare"
        print(f"  {label:<28} exit {arm['exit']} · {len(arm['peers'])} outbound peer(s) "
              f"{arm['peers'] or '(none seen)'}")
    print()
    print("Each count is a FLOOR: the watcher polls at 50ms and a connection opened and closed "
          "between two polls is missed.")

    if a.json:
        Path(a.json).write_text(json.dumps({"binary": binary, "bare": bare,
                                            "suppressed": suppressed}, indent=2) + "\n")

    if not bare["peers"] and not suppressed["peers"]:
        print()
        print("Neither arm reached a peer. Either this machine has no network or the poll "
              "missed both, and in either case nothing was measured.")
        return 2

    print()
    if len(suppressed["peers"]) >= len(bare["peers"]) and bare["peers"]:
        print(f"FAIL  the suppressed arm reached {len(suppressed['peers'])} peer(s) against the "
              f"bare arm's {len(bare['peers'])}. The variable Proctor sets is not reducing what "
              f"the lane reaches, so the disclosure overstates what it does.")
        return 1

    remaining = len(suppressed["peers"])
    print(f"MEASURED: bare reaches {len(bare['peers'])}, suppressed reaches {remaining}. "
          f"The variable removes {len(bare['peers']) - remaining}.")
    if remaining:
        print(f"          {remaining} peer(s) remain with the variable set, which is DEF-339's "
              f"unrepaired half and the reason the lane is not network-isolated:")
        for p in suppressed["peers"]:
            print(f"            {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
