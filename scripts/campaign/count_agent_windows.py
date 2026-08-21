#!/usr/bin/env python3
"""Count the windows a process actually owns in a witness_probe `windows` capture.

PRO-0088. CASE-0032 says "all three overlays". Three is the number the case was
written with, and a claim about a population has to be measured over the
population rather than repeated. This reads a probe artifact, groups its rows by
owning pid, and reports len() per pid together with how many of those rows report
sharingState 0.

    count_agent_windows.py <probe.json> [<probe.json> ...]

Prints one JSON object to stdout and writes nothing.
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict


def summarise(path: str) -> dict:
    doc = json.load(open(path))
    rows = doc["rows"]
    by_pid: dict[int, list] = defaultdict(list)
    for row in rows:
        by_pid[row["ownerPID"]].append(row)

    owners = {}
    for pid, owned in sorted(by_pid.items()):
        excluded = [r for r in owned if r["sharingState"] == 0]
        leaking = [r for r in owned if r["sharingState"] != 0]
        owners[str(pid)] = {
            "ownerName": owned[0]["ownerName"],
            "windowsOwned": len(owned),
            "excluded": len(excluded),
            "notExcluded": len(leaking),
            "windows": [
                {
                    "windowNumber": r["windowNumber"],
                    "layer": r["layer"],
                    "sharingState": r["sharingState"],
                    "size": f'{int(r["bounds"]["Width"])}x{int(r["bounds"]["Height"])}',
                    "name": r["name"],
                }
                for r in sorted(owned, key=lambda r: r["windowNumber"])
            ],
        }

    return {
        "artifact": path,
        "at": doc.get("at"),
        "probePid": doc.get("probePid"),
        "needle": doc.get("needle"),
        "rowsTotal": len(rows),
        "owners": owners,
    }


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    print(json.dumps([summarise(p) for p in sys.argv[1:]], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
