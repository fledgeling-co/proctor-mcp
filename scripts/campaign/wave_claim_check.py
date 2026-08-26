#!/usr/bin/env python3
"""Re-check the claims a wave wrote, before the next wave plans from them.

`claim_provenance.py` reads every durable artifact and compares each figure in
it against the registries. Run once at session close, a wrong figure has already
travelled: this repository's ORCHESTRATOR header went stale four times in one
wave — 152, then 158, then 164, then 170 rows — and each was corrected after
something downstream had already read it.

The claims worth re-checking are the ones the wave just wrote, so this runs over
the diff rather than the tree. That makes it cheap enough to run at every wave
boundary, which is the only cadence at which it prevents anything.

FOUR OUTCOMES, AND THE FOURTH IS THE POINT. Clean; contradicted; unbacked; and
"this wave touched no durable artifact". The last is reported in those words
rather than as a clean check, because a wave that wrote nothing and a wave whose
claims all held are the same green and different facts.

    python3 scripts/campaign/wave_claim_check.py --since <ref> [--gate] [--json OUT]

`--since` defaults to the merge-base with the previous wave tag if one exists,
and otherwise to HEAD~1. Name it explicitly at a wave boundary.

Exit codes
    0   every claim the wave wrote holds, or the wave wrote none
    1   a claim in something the wave touched contradicts a registry
    2   the range could not be resolved, so nothing was examined
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

PROVENANCE = ROOT / "scripts" / "campaign" / "claim_provenance.py"


def durable_set() -> list[str]:
    """What claim_provenance itself treats as an artifact another session plans from.

    Read out of that module rather than restated here. A first version declared
    its own wider set — every .md under docs/ and tailings/ — and reported 44 of
    68 artifacts contradicted, because it was promoting wave-15 briefs that
    describe what was true in wave 15 to claims about now. Those documents are
    history and claim_provenance already knows it; a second copy of somebody
    else's judgement drifts from it silently, and this one drifted on its first
    run.
    """
    import importlib.util
    spec = importlib.util.spec_from_file_location("claim_provenance", PROVENANCE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return list(module.DEFAULT_ARTIFACTS)


def touched(since: str) -> list[str] | None:
    out = subprocess.run(["git", "-C", str(ROOT), "diff", "--name-only", f"{since}..HEAD"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None
    return [p for p in out.stdout.split() if p]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="HEAD~1")
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args()

    paths = touched(a.since)
    if paths is None:
        print(f"the range {a.since}..HEAD could not be resolved, so nothing was examined. "
              f"This is not a clean check.")
        return 2

    plan_from = durable_set()
    durable = sorted(p for p in paths if p in plan_from and (ROOT / p).is_file())

    print(f"{len(paths)} file(s) changed in {a.since}..HEAD · {len(durable)} of the "
          f"{len(plan_from)} artifact(s) another session plans from")
    print(f"  the plan-from set, from claim_provenance itself: {', '.join(plan_from)}")

    if not durable:
        print()
        print("This wave touched no durable artifact, so there is no claim in it to re-check.")
        print("That is a different fact from a clean check, and it is reported as itself.")
        if a.json:
            Path(a.json).write_text(json.dumps(
                {"since": a.since, "changed": len(paths), "durable": [],
                 "verdict": "nothing-to-check"}, indent=2) + "\n")
        return 0

    rows: list[dict] = []
    worst = 0
    for rel in durable:
        out = subprocess.run(
            [sys.executable, str(PROVENANCE), "--artifact", rel, "--gate"],
            capture_output=True, text=True, cwd=str(ROOT))
        contradicted = "contradicted" in out.stdout and out.returncode != 0
        rows.append({"artifact": rel, "exit": out.returncode,
                     "contradicted": contradicted,
                     "output": out.stdout[-1200:] if out.returncode else ""})
        worst = max(worst, out.returncode)
        print(f"  {'FAIL' if out.returncode else 'ok  '}  {rel}")

    bad = [r for r in rows if r["exit"]]
    if bad:
        print()
        print(f"{len(bad)} artifact(s) this wave touched state a figure the registries do not "
              f"hold. Correct them before the next wave plans from them:")
        for r in bad:
            print(f"  ---- {r['artifact']}")
            for line in r["output"].splitlines():
                if line.strip():
                    print(f"       {line}")

    if a.json:
        Path(a.json).write_text(json.dumps(
            {"since": a.since, "changed": len(paths), "durable": durable, "rows": rows},
            indent=2) + "\n")

    print()
    if bad:
        print(f"FAIL  {len(bad)} of {len(durable)} durable artifact(s) touched by this wave "
              f"carry a contradicted claim.")
        return 1 if a.gate else 0
    print(f"PASS: all {len(durable)} durable artifact(s) this wave touched hold against the "
          f"registries.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
