#!/usr/bin/env python3
"""Mutation survival, aggregated across runs, with the denominator on every rate.

`mutate_swift.py` writes one JSON per run and each is read on its own. Read that
way the picture is wrong in both directions: one run over ProctorCore reports
0% survival across 24 mutants and reads as a suite that bites everywhere, while
a run over ProctorAgent reports 79% over its own 24 and reads as a suite that
bites nowhere. Neither is a fact about the package, because neither names how
many sites it sampled out of how many exist.

So this aggregates them, and prints three numbers rather than one rate:

  scored     mutants that ran and reached a verdict
  sites      mutation sites the sampler found in the same targets
  sampled    scored ÷ sites — the fraction of the space anybody looked at

A survival rate over 24 of 3,189 sites is a measurement of 0.75% of the module.
Reporting it as "79% survival" without the second figure is the failure this
whole campaign is built against, one layer in: two right numbers that disagree
cost more to reconcile than either cost to produce.

Surviving mutants are listed with their file, line, and the enclosing
declaration read back out of the source — a survivor with a byte offset and no
name sends its reader to open the file, which is the whole cost of the report.

  mutation_report.py [--evidence DIR] [--json PATH] [--gate] [--set-ratchet N]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RATCHET = ROOT / "docs" / "test-campaign" / "mutation-ratchet.json"

# A survivor's enclosing declaration, searched upward from its line. `func` and
# the type keywords are what a reader needs; a survivor inside a computed
# property resolves to that property's `var`.
DECL = re.compile(
    r"^\s*(?:@\w+\s+)*(?:public|internal|private|fileprivate|open|package)?\s*"
    r"(?:final\s+|static\s+|class\s+|mutating\s+|nonisolated\s+|override\s+)*"
    r"\b(class|struct|enum|protocol|actor|extension|func|var|let|init)\b"
    r"(?:\s+([A-Za-z_]\w*))?")

SURVIVED = {"survived", "SURVIVED"}


def enclosing(path: Path, line: int) -> str:
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return "?"
    for i in range(min(line, len(lines)) - 1, -1, -1):
        m = DECL.match(lines[i])
        if m and m.group(2):
            return f"{m.group(1)} {m.group(2)}"
    return "(top level)"


def module_of(rel: str) -> str:
    parts = Path(rel).parts
    return parts[1] if len(parts) > 1 and parts[0] == "Sources" else (parts[0] if parts else "?")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--evidence", type=Path,
                    default=ROOT / "docs" / "test-campaign" / "evidence")
    ap.add_argument("--json", type=Path, default=None)
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--set-ratchet", type=int, default=None)
    a = ap.parse_args()

    runs = []
    for f in sorted(a.evidence.glob("mutation*.json")) + sorted(a.evidence.glob("*mutation*.json")):
        if f in [r["file"] for r in runs]:
            continue
        try:
            d = json.loads(f.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(d, dict) and "mutants" in d:
            runs.append({"file": f, "summary": d.get("summary") or {}, "mutants": d["mutants"]})
    if not runs:
        print(f"no mutation run found under {a.evidence}. An absent measurement is not a "
              f"clean one, so nothing is reported.", file=sys.stderr)
        return 2

    per_module: dict[str, dict] = defaultdict(
        lambda: {"scored": 0, "killed": 0, "survived": 0, "unbuildable": 0, "sites": 0,
                 "files": set(), "runs": set()})
    survivors = []
    seen: set[tuple] = set()

    for run in runs:
        name = run["file"].name
        # A run's own site count covers its whole target list, so it is credited
        # to each module those targets touch rather than to the package as one
        # blur. A run with no site count contributes none, and the report says
        # which — an absent denominator is a hole, not a zero.
        targets = run["summary"].get("targets") or []
        sites = run["summary"].get("sites")
        mods_in_run = {module_of(t) for t in targets} or set()
        for m in mods_in_run:
            per_module[m]["runs"].add(name)
        # The site count belongs to the RUN's target list, not to the module.
        # Summing it per module produced `88 scored / 52 sites` for ProctorCore
        # — more mutants than sites — because three runs covered different files
        # and only one of them counted its sites. A denominator that can be
        # smaller than its numerator is worse than none, so sampling is reported
        # per run below and the module table carries kill rates only.
        run["sites"] = sites if isinstance(sites, int) else None
        run["module"] = next(iter(mods_in_run)) if len(mods_in_run) == 1 else "several"

        for mut in run["mutants"]:
            rel = mut.get("file") or "?"
            key = (rel, mut.get("start"), mut.get("after"))
            if key in seen:
                continue
            seen.add(key)
            m = per_module[module_of(rel)]
            m["files"].add(rel)
            verdict = str(mut.get("verdict") or "")
            if verdict.lower() == "unbuildable":
                m["unbuildable"] += 1
                continue
            m["scored"] += 1
            if verdict in SURVIVED:
                m["survived"] += 1
                survivors.append({
                    "module": module_of(rel), "file": rel, "line": mut.get("line"),
                    "in": enclosing(ROOT / rel, int(mut.get("line") or 1)),
                    "was": mut.get("before"), "became": mut.get("after"), "run": name})
            else:
                m["killed"] += 1

    total_scored = sum(m["scored"] for m in per_module.values())
    total_killed = sum(m["killed"] for m in per_module.values())
    total_surv = sum(m["survived"] for m in per_module.values())
    total_sites = sum(r["sites"] for r in runs if r.get("sites"))
    counted_runs = [r for r in runs if r.get("sites")]

    print(f"{len(runs)} mutation run(s) aggregated, {len(seen)} distinct mutant(s)\n")
    print(f"{'module':<18}{'killed':>8}{'survived':>10}{'scored':>8}{'kill rate':>14}"
          f"   files touched")
    for mod in sorted(per_module):
        m = per_module[mod]
        rate = (f"{m['killed']}/{m['scored']} ({100.0 * m['killed'] / m['scored']:.0f}%)"
                if m["scored"] else "0/0")
        print(f"{mod:<18}{m['killed']:>8}{m['survived']:>10}{m['scored']:>8}{rate:>14}"
              f"   {len(m['files'])}")
    print(f"\n{'TOTAL':<18}{total_killed:>8}{total_surv:>10}{total_scored:>8}"
          f"{f'{total_killed}/{total_scored}':>14}")

    print("\nsampling, per run — the site count belongs to a run's own target list, and "
          "summing it across runs that overlap gives a denominator smaller than its numerator:")
    for r in runs:
        scored_here = sum(1 for m in r["mutants"]
                          if str(m.get("verdict") or "").lower() != "unbuildable")
        if r.get("sites"):
            print(f"  {r['file'].name:<30} {scored_here:>4} of {r['sites']:>5} site(s) "
                  f"({100.0 * scored_here / r['sites']:.2f}%) over {len(r['summary'].get('targets') or [])} target(s)")
        else:
            print(f"  {r['file'].name:<30} {scored_here:>4} scored, NO SITE COUNT — this run's "
                  f"rate has no denominator behind it")
    if counted_runs:
        print(f"\nAcross the {len(counted_runs)} run(s) that counted their sites, "
              f"{sum(sum(1 for m in r['mutants'] if str(m.get('verdict') or '').lower() != 'unbuildable') for r in counted_runs)}"
              f" of {total_sites} site(s) were run — "
              f"{100.0 * sum(sum(1 for m in r['mutants'] if str(m.get('verdict') or '').lower() != 'unbuildable') for r in counted_runs) / total_sites:.1f}%. "
              f"Every kill rate above is a rate among the scored and says nothing about the rest.")
    else:
        print("\nNo run carried a site count, so no rate here has a denominator behind it.")

    if survivors:
        print(f"\n{len(survivors)} surviving mutant(s), each an assertion nobody wrote:")
        for s in survivors:
            print(f"  {s['file']}:{s['line']}  in {s['in']}"
                  f"   {s['was']!r} -> {s['became']!r}   [{s['run']}]")
        hot = defaultdict(int)
        for s in survivors:
            hot[(s["file"], s["in"])] += 1
        worst = sorted(hot.items(), key=lambda kv: -kv[1])[:5]
        if worst and worst[0][1] > 1:
            print("\nwhere they cluster — a declaration with several survivors is one "
                  "untested branch, not several:")
            for (f, decl), n in worst:
                if n > 1:
                    print(f"  {n:>3}  {decl}  in {f}")

    if a.json:
        a.json.write_text(json.dumps({
            "runs": [r["file"].name for r in runs],
            "modules": {k: {kk: (sorted(vv) if isinstance(vv, set) else vv)
                            for kk, vv in v.items()} for k, v in per_module.items()},
            "totals": {"killed": total_killed, "survived": total_surv,
                       "scored": total_scored, "sites": total_sites},
            "survivors": survivors}, indent=2) + "\n")
        print(f"\nwrote {a.json}")

    if a.set_ratchet is not None:
        RATCHET.write_text(json.dumps({"survivors": a.set_ratchet}, indent=2) + "\n")
        print(f"\nratchet set to {a.set_ratchet}")
        return 0

    if a.gate:
        try:
            bar = json.loads(RATCHET.read_text())["survivors"]
        except (OSError, json.JSONDecodeError, KeyError):
            print("\nno ratchet on disk. Set one with --set-ratchet <n>.")
            return 1
        print(f"\nratchet: {bar} surviving mutant(s) allowed")
        if total_surv > bar:
            print(f"FAIL  survivors rose from {bar} to {total_surv}")
            return 1
        if total_surv < bar:
            print(f"survivors FELL from {bar} to {total_surv} — lower the ratchet in the "
                  f"same commit.")
            return 0
        print("held.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
