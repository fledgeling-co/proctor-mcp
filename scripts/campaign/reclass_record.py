#!/usr/bin/env python3
"""Record a class change in an audit worklist, and refuse a self-cleared gate.

A verification pass over this repository classified four claims as
`contradicted`, corrected the artifacts they lived in, and then reclassified the
same four rows as `substantiated` — which cleared its own gate. It caught that
and reverted it. Nothing in the tooling would have.

The classification file is the gate's input and the pass is its only writer, so
a pass that wants to finish clean can always finish clean. That is the same
shape the audit already names when a project does it to a test, and it matters
more here, because the auditor's output is what a reader trusts instead of
re-checking.

Two things are being kept apart, and only one of them is a conflict:

  correcting the artifact   the pass establishes a number and writes it down
  re-grading the claim      the pass decides the claim was fine after all

The first is the pass's job. The second, done by the same pass, over a row it
had already called blocking, is the auditor grading its own repair.

  reclass_record.py snapshot <worklist-dir>     # before any classifying
  reclass_record.py check    <worklist-dir> [--gate]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

BLOCKING = {"contradicted", "laundered"}
CLEAN = {"substantiated", "waived"}


def rows_of(worklist: Path) -> dict[str, str]:
    d = json.loads(worklist.read_text())
    rows = d["rows"] if isinstance(d, dict) else d
    return {r["id"]: (r.get("class") or "") for r in rows}


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("snapshot"); s.add_argument("dir", type=Path)
    c = sub.add_parser("check"); c.add_argument("dir", type=Path)
    c.add_argument("--gate", action="store_true")
    a = ap.parse_args()

    worklist = a.dir / "worklist.json"
    history = a.dir / "reclass-history.jsonl"
    if not worklist.is_file():
        print(f"no worklist at {worklist}", file=sys.stderr)
        return 2

    stamp = subprocess.run(["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"],
                           capture_output=True, text=True).stdout.strip()
    now = rows_of(worklist)

    if a.cmd == "snapshot":
        with history.open("a") as fh:
            fh.write(json.dumps({"at": stamp, "kind": "snapshot", "rows": now}) + "\n")
        print(f"snapshot: {len(now)} row(s) recorded at {stamp}")
        return 0

    if not history.is_file():
        print("no snapshot was taken, so no class change can be seen. A pass that never "
              "recorded its starting point cannot show that it did not move a row.")
        return 1 if a.gate else 0

    snaps = [json.loads(l) for l in history.read_text().splitlines() if l.strip()]
    first = next((s for s in snaps if s.get("kind") == "snapshot"), None)
    if first is None:
        print("no snapshot row in the history")
        return 1 if a.gate else 0

    moved, self_cleared = [], []
    for rid, klass in now.items():
        was = first["rows"].get(rid, "")
        if was == klass:
            continue
        moved.append({"id": rid, "was": was, "now": klass})
        if was in BLOCKING and klass in CLEAN:
            self_cleared.append({"id": rid, "was": was, "now": klass})

    print(f"{len(now)} row(s) · {len(moved)} class change(s) since the snapshot at "
          f"{first['at']}")
    for m in moved[:12]:
        mark = "  SELF-CLEARED" if m in self_cleared else ""
        print(f"  {m['id']}  {m['was'] or '(unset)'} -> {m['now']}{mark}")
    if len(moved) > 12:
        print(f"  … and {len(moved) - 12} more")

    print(f"\nnever blocking: {sum(1 for k in now.values() if k in CLEAN and first['rows'].get(k, '') not in BLOCKING)}"
          f" · stopped blocking: {len(self_cleared)}")

    with history.open("a") as fh:
        fh.write(json.dumps({"at": stamp, "kind": "check", "moved": moved,
                             "selfCleared": self_cleared}) + "\n")

    if a.gate and self_cleared:
        print(f"\nFAIL  {len(self_cleared)} row(s) moved from a blocking class to a clean one "
              f"within this pass: {', '.join(r['id'] for r in self_cleared)}.")
        print("      Correcting the artifact and re-grading the claim are two acts, and only "
              "the first belongs to the pass that found it. A class describes what the session "
              "said; a correction does not change what it said.")
        return 1
    if a.gate:
        print("\ngate: no row moved from a blocking class to a clean one within this pass.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
