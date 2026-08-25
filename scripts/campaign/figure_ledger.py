#!/usr/bin/env python3
"""A specification names the figure it will move, and the merge is checked against it.

Four specifications were written to bring five warrant classes to full figure
sourcing. All four merged. The rollup still reports every one of the five short:
capture-trust 95.7%, evidence-integrity 91.1%, operator-state 94.5%,
registry-drift 97.0%, surface-conformance 84.0% — and the two classes that are
green were green before that work started.

So a wave's worth of effort landed and the number it existed for did not move,
and nobody noticed until a rollup ran several waves later. Nothing tied a
specification's merge to the figure it claimed it would shift, so the only
available reading of "merged" was "the rows say merged".

A spec may declare what it will move:

    **Moves:** warrant.surface-conformance from 84.0% to 100%

and this records the value when the spec is Ready, reads it again when the spec
is Merged, and reports a merge whose figure did not move.

**Why the blocking cases are named per class rather than counted.** Every one of
the 43 figures short across those five classes is a case standing at
`source-analysis` — a rung that reads a fact off the source and witnesses no
effect. Aggregated it looks like five separate shortfalls; named, it is one
population and one piece of work. A count would have hidden that.

  figure_ledger.py record   [--spec PRO-0163]   # stamp the current value
  figure_ledger.py check    [--gate]
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LEDGER = ROOT / "docs" / "test-campaign" / "figure-ledger.json"
MOVES = re.compile(r"^\*\*Moves:\*\*\s*(\S+)\s+from\s+([\d.]+)%?\s+to\s+([\d.]+)%?", re.M)


def warrant_figures() -> dict[str, float]:
    """Each warrant class's current figure-sourcing percentage, from the rollup."""
    out: dict[str, float] = {}
    path = ROOT / "docs" / "test-campaign" / "evidence" / "PRO-0137" / "warrant-tiers.json"
    if not path.is_file():
        return out
    d = json.loads(path.read_text())
    for row in d.get("proposals", []) + d.get("blocked", []):
        out[f"warrant.{row['class']}"] = round(100 * row["pct"], 1)
    return out


def spec_status() -> dict[str, str]:
    ledger = (ROOT / "docs" / "feature-specs" / "LEDGER.md").read_text()
    return {m.group(1): m.group(2).strip().split("`")[0].strip()
            for m in re.finditer(r"^\| (PRO-\d{4}) \|[^|]*\|[^|]*\| ([^|]+)\|", ledger, re.M)}


def declared_moves() -> dict[str, dict]:
    out: dict[str, dict] = {}
    for spec in sorted((ROOT / "docs" / "specs").glob("spec-PRO-*.md")):
        m = MOVES.search(spec.read_text())
        if m:
            out[spec.stem.replace("spec-", "")] = {
                "figure": m.group(1), "from": float(m.group(2)), "to": float(m.group(3))}
    return out


def load() -> dict:
    try:
        return json.loads(LEDGER.read_text())
    except (OSError, json.JSONDecodeError):
        return {"entries": []}


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("record"); r.add_argument("--spec")
    c = sub.add_parser("check"); c.add_argument("--gate", action="store_true")
    a = ap.parse_args()

    figures = warrant_figures()
    moves = declared_moves()
    status = spec_status()
    stamp = subprocess.run(["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"],
                           capture_output=True, text=True).stdout.strip()
    book = load()

    if a.cmd == "record":
        wanted = [a.spec] if a.spec else sorted(moves)
        for pid in wanted:
            mv = moves.get(pid)
            if not mv:
                print(f"{pid} declares no **Moves:** line, so there is nothing to record")
                continue
            now = figures.get(mv["figure"])
            book["entries"].append({"at": stamp, "spec": pid, "figure": mv["figure"],
                                    "value": now, "status": status.get(pid, "?")})
            print(f"recorded {pid}: {mv['figure']} = {now} while {status.get(pid, '?')}")
        LEDGER.write_text(json.dumps(book, indent=2) + "\n")
        return 0

    if not moves:
        print("no specification declares a **Moves:** line. Nothing here can check that a merge "
              "moved anything, which is the condition this exists to end rather than a pass.")
        return 1 if a.gate else 0

    stale = []
    print(f"{len(moves)} specification(s) declare a figure they will move\n")
    for pid, mv in sorted(moves.items()):
        seen = [e for e in book["entries"] if e["spec"] == pid]
        before = next((e["value"] for e in seen if e["status"] != "Merged"), None)
        now = figures.get(mv["figure"])
        st = status.get(pid, "?")
        print(f"  {pid}  {mv['figure']}  declared {mv['from']} -> {mv['to']}  "
              f"· status {st} · now {now}")
        if st != "Merged":
            continue
        if now is None:
            stale.append(f"{pid} merged and its figure {mv['figure']} cannot be read")
        elif before is not None and now <= before:
            stale.append(f"{pid} merged and {mv['figure']} did not move: {before} -> {now}")
        elif now < mv["to"]:
            print(f"      merged short of its target: {now} against {mv['to']}")

    if stale:
        print()
        for s in stale:
            print(f"FAIL  {s}")
        if a.gate:
            print("\nA merge that does not move the figure it named is the shape this exists to "
                  "catch: four specifications closed five classes on paper and moved none of them.")
            return 1
    elif a.gate:
        print("\ngate: every merged specification that named a figure moved it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
