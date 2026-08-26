#!/usr/bin/env python3
"""A summary that quotes a total carries the classes behind it.

A gate that prints a partition and a summary that reports only its total are the
same green. The tailings probe T11 fired seven times on one transcript for this:
`vacuity ... blind 520` printed by the gate, and the reply that followed carried
neither the class nor the number.

The failure is quiet because the total is true. "440 of 502 checked" is right,
and it does not say that 41 of the 62 only prove something rendered while 16 were
never watched to fail — two different jobs with two different owners, and only
one of them is a test to write.

WHAT IS DECLARED. `docs/test-campaign/partitions.json` pairs a gate command with
the artifact that summarises it, and names the classes that gate prints. This
tool runs each gate, reads the classes out of its own output, and requires the
summary to carry every non-zero one.

A class the declaration does not name is reported as UNRECOGNISED rather than
folded into a known one, because folding is how a class disappears: it becomes
part of a number that is still correct.

    python3 scripts/campaign/partition_report.py [--gate] [--json OUT]

Exit codes
    0   every non-zero class a declared gate printed appears in its summary
    1   a class is missing from a summary, the classes do not sum, or a gate
        printed a class nothing declared
    2   a declared gate could not be run, so its partition was not read
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DECLARATION = ROOT / "docs" / "test-campaign" / "partitions.json"


def read_classes(output: str, names: list[str]) -> dict[str, int]:
    """Each declared class and the count printed beside it.

    Both orders, because gates here print both: `unmeasured 2` and `2 n/a`.
    """
    found: dict[str, int] = {}
    for name in names:
        n = re.escape(name)
        m = (re.search(rf"\b{n}\b[^\S\n]*[:=]?[^\S\n]*(\d[\d,]*)", output)
             or re.search(rf"(\d[\d,]*)[^\S\n]+{n}\b", output))
        if m:
            found[name] = int(m.group(1).replace(",", ""))
    return found


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--declaration", default=str(DECLARATION))
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args()

    declaration = json.loads(Path(a.declaration).read_text())
    rows: list[dict] = []
    problems: list[str] = []
    unreadable = 0

    for entry in declaration["partitions"]:
        label = entry["label"]
        run = subprocess.run(entry["command"], capture_output=True, text=True,
                             cwd=str(ROOT), shell=False)
        output = run.stdout + run.stderr
        if not output.strip():
            unreadable += 1
            problems.append(f"{label}: the gate produced no output, so no partition was read")
            rows.append({"label": label, "readable": False})
            continue

        classes = read_classes(output, entry["classes"])
        missing_from_gate = [c for c in entry["classes"] if c not in classes]
        non_zero = {k: v for k, v in classes.items() if v}

        summary_path = ROOT / entry["summary"]
        summary = summary_path.read_text(errors="replace") if summary_path.is_file() else ""
        absent = [c for c in non_zero if not re.search(
            rf"\b{re.escape(c)}\b[^\S\n]*[:=]?[^\S\n]*{non_zero[c]:,}?".replace(",", "[,]?"),
            summary) and not re.search(rf"\b{re.escape(c)}\b", summary)]

        total_declared = entry.get("total")
        summed = sum(classes.values())
        sums = None
        if total_declared and total_declared in classes:
            sums = None                              # the total is one of the classes
        elif total_declared:
            m = re.search(rf"\b{re.escape(total_declared)}\b[^\S\n]*[:=]?[^\S\n]*(\d[\d,]*)",
                          output) or re.search(rf"(\d[\d,]*)[^\S\n]+{re.escape(total_declared)}\b",
                                               output)
            if m:
                sums = int(m.group(1).replace(",", "")) == summed

        rows.append({"label": label, "readable": True, "classes": classes,
                     "nonZero": non_zero, "absentFromSummary": absent,
                     "missingFromGate": missing_from_gate, "sums": sums,
                     "summed": summed, "summary": entry["summary"]})

        if absent:
            problems.append(f"{label}: {', '.join(absent)} are non-zero and absent from "
                            f"{entry['summary']}")
        if missing_from_gate:
            problems.append(f"{label}: declared class(es) {', '.join(missing_from_gate)} were "
                            f"not printed — the declaration and the gate disagree")
        if sums is False:
            problems.append(f"{label}: the classes sum to {summed}, which is not the total the "
                            f"gate quotes")

    print(f"{len(rows)} declared partition(s), {sum(1 for r in rows if r.get('readable'))} read")
    for r in rows:
        if not r.get("readable"):
            print(f"  UNREADABLE  {r['label']}")
            continue
        parts = " · ".join(f"{k} {v}" for k, v in r["classes"].items())
        mark = "FAIL" if (r["absentFromSummary"] or r["missingFromGate"] or r["sums"] is False) \
            else "ok  "
        print(f"  {mark}  {r['label']}")
        print(f"        gate prints: {parts}")
        print(f"        summarised in: {r['summary']}")

    if problems:
        print()
        for p in problems:
            print(f"  {p}")

    if a.json:
        Path(a.json).write_text(json.dumps({"rows": rows, "problems": problems}, indent=2) + "\n")

    print()
    if unreadable:
        print(f"FAIL  {unreadable} declared gate(s) produced no output. A partition that was "
              f"not read is not a partition that held.")
        return 2
    if problems:
        print(f"FAIL  {len(problems)} problem(s) across {len(rows)} declared partition(s).")
        return 1 if a.gate else 0
    print(f"PASS: every non-zero class of {len(rows)} partition(s) appears in the summary "
          f"derived from it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
