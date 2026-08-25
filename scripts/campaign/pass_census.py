#!/usr/bin/env python3
"""Did every pass a config declares actually run, and over what?

`vacuity-check.py` has three passes. One of them — the cheapest, and the only one
that reads the test tree — reported `blind: NOT RUN — no corpus` for the entire
life of this campaign, because `testRoot` was never declared in `campaign.json`.
Its vocabulary had meanwhile been researched, measured against a 57-of-78 sample
and defended against an out-of-family reviewer. It sat beside a pass that was not
executing, and every recorded "vacuity 0 findings" was true of two passes out of
three.

The instrument was not lying. It printed NOT RUN whenever anybody asked it
directly. What was missing is anything reading that back — so a green summary and
a green summary with a third of its work skipped are the same line.

This reads each pass's own output and requires two things of every one: that it
ran, and that it says over how many things. `examined=41 findings=0` is a
result; `findings=0` is a claim.

  pass_census.py [--campaign DIR] [--json PATH] [--gate]
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Each pass, the line it prints, and the config field whose absence disables it.
# Naming the field is the part that matters: an operator told "blind did not run"
# still has to find out why, and the why is one missing key.
PASSES = {
    "unclassed": {"needs": None,
                  "why": "reads the requirement list, which is always present"},
    "uncensused": {"needs": "sourceRoot",
                   "why": "resolves each provider against the production tree"},
    "blind": {"needs": "testRoot",
              "why": "reads the test tree for a mutation with no read after it"},
}
NOT_RUN = re.compile(r"NOT RUN|NOT MEASURED|no corpus", re.I)
POPULATION = re.compile(r"examined=(\d+)")


def newest(tool: str) -> Path | None:
    cache = Path.home() / ".claude/plugins/cache/fledgeling-plugins/test-campaign"
    if not cache.is_dir():
        return None
    def key(d: Path) -> tuple:
        return tuple(int(x) if x.isdigit() else -1 for x in d.name.split("."))
    for d in sorted((x for x in cache.iterdir() if x.is_dir()), key=key, reverse=True):
        c = d / "skills/test-campaign/scripts" / tool
        if c.is_file():
            return c
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--campaign", type=Path, default=ROOT / "docs" / "test-campaign")
    ap.add_argument("--json", type=Path, default=None)
    ap.add_argument("--gate", action="store_true")
    a = ap.parse_args()

    tool = newest("vacuity-check.py")
    if tool is None:
        print("vacuity-check.py is not installed, so no pass can be read. An absent instrument "
              "is a lane failure, not a pass.", file=sys.stderr)
        return 2

    cfg = json.loads((a.campaign / "campaign.json").read_text())
    out = subprocess.run([sys.executable, str(tool), str(a.campaign)],
                         capture_output=True, text=True).stdout

    rows, silent, blind_to_population = [], [], []
    for name, meta in PASSES.items():
        line = next((l for l in out.splitlines() if l.startswith(f"{name}:")), "")
        ran = bool(line) and not NOT_RUN.search(line)
        m = POPULATION.search(line)
        population = int(m.group(1)) if m else None
        field = meta["needs"]
        declared = cfg.get(field) if field else "n/a"
        rows.append({"pass": name, "ran": ran, "population": population,
                     "needs": field, "declared": declared, "line": line.strip()})
        if not ran:
            silent.append(f"{name} did not run" + (
                f" — `{field}` is not declared in campaign.json, and it is what gives this pass "
                f"its corpus ({meta['why']})" if field and not declared else ""))
        elif population is None:
            blind_to_population.append(
                f"{name} ran and printed no population, so its finding count has no denominator")

    print(f"{len(rows)} declared pass(es) over {a.campaign}")
    for r in rows:
        mark = "ran " if r["ran"] else "DID NOT RUN"
        pop = f"examined {r['population']}" if r["population"] is not None else "NO DENOMINATOR"
        print(f"  {r['pass']:<12} {mark:<12} {pop:<18} needs={r['needs'] or '—'} "
              f"declared={r['declared']!r}")

    for s in silent + blind_to_population:
        print(f"\nFAIL  {s}")

    if a.json:
        a.json.write_text(json.dumps({"passes": rows, "silent": silent,
                                      "withoutPopulation": blind_to_population}, indent=2) + "\n")
        print(f"\nwrote {a.json}")

    if a.gate:
        if silent or blind_to_population:
            print("\nA pass that could not look and a pass that looked and found nothing produce "
                  "the same summary line unless something reads the difference back. This is "
                  "that something.")
            return 1
        print(f"\ngate: all {len(rows)} declared pass(es) ran, and each printed the population "
              f"it examined.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
