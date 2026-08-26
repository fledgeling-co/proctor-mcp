#!/usr/bin/env python3
"""The finish line for a long run, as an exit code.

A drained ledger is not a finished product. `ship-fleet`'s own record of this is
seven projects in one week that each reported their backlog implemented and
verified, and in all seven the honest answer to "does every feature work" was no.
They terminated on the condition they were given, and the condition was "the rows
say Merged".

So this checks four things, and re-anchors the reconciliation every time rather
than reading the last one — a reckoning against a stale campaign is a reckoning
about a codebase that no longer exists.

    1. no ledger row is in an open status
    2. reckon's `undecided` is empty
    3. every `broken` row is one this run has DECLARED, with its id in the goal brief
    4. every `unmeasured` row is likewise declared

THREE AND FOUR ARE NOT AN ESCAPE HATCH, AND THE DIFFERENCE MATTERS. A gate that
cannot pass is worse than no gate: REQ-025 is deferred against an upstream Apple
bug and REQ-072 is a ceiling somebody recorded on purpose, so a gate demanding
they move would grind until the stuck bound disarmed the run. What this refuses
instead is an exempt set that GROWS. A new broken row cannot be waved through by
the run that created it, because the id has to be written into a file a person
reads, and this gate names every id that is not there.

    python3 scripts/campaign/goal_reconciliation.py --brief docs/goals/goal-<slug>.md
                                                    [--json OUT] [--keep DIR]

Exit codes
    0   the finish line is met
    1   something remains; every remaining row is named
    2   the reconciliation could not be built, so nothing was checked
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECKON_GLOB = ".claude/plugins/cache/fledgeling-plugins/reckon/*/skills/reckon/scripts/reckon.py"


def newest_reckon() -> Path | None:
    """The installed reckon, newest version first.

    Resolved rather than pinned: a version string in a gate drifts silently on
    the next plugin upgrade, and the gate then measures a tool nobody installed.
    """
    # The version is parts[-5] — reckon.py, scripts, reckon, skills, <version>.
    # The first draft used parts[-4], which is the literal "skills" for every
    # candidate, so the sort was arbitrary and the gate ran reckon 1.0.0 against
    # a 1.7.0 registry: 136 undecided rows and 6 broken, against the 3 and 4 the
    # installed version reports. A gate reading an old tool is worse than a
    # missing one, because it answers.
    def version(p: Path) -> list[int]:
        return [int(x) if x.isdigit() else 0 for x in p.parts[-5].split(".")]

    found = sorted(Path.home().glob(RECKON_GLOB), key=version, reverse=True)
    return found[0] if found else None


DECLARE_BLOCK = re.compile(
    r"<!--\s*declared:begin\s*-->(.*?)<!--\s*declared:end\s*-->", re.S)


def declared(brief: Path) -> set[str]:
    """The ids inside the brief's declared block, and nowhere else.

    The brief is the place a person reads, which is the whole point: an
    exemption that is not visible to a reader is not an exemption, it is a hole.

    But it cannot be every id in the file. The worklist names the very defects
    the run has to close, so a whole-file scan would declare them by accident and
    the gate would stop requiring the work it exists to require — caught before
    arming, by writing the worklist and re-running. So the declaration is an
    explicit block, and an id outside it is not declared however often it appears.
    """
    if not brief.is_file():
        return set()
    block = DECLARE_BLOCK.search(brief.read_text())
    if not block:
        return set()
    return set(re.findall(r"\b((?:REQ|DEF|CASE|SURF|BRIEF)-\d+)\b", block.group(1)))


def ledger_open() -> tuple[int, str]:
    out = subprocess.run([sys.executable, str(ROOT / "scripts" / "campaign" / "ledger_gate.py")],
                         capture_output=True, text=True, cwd=str(ROOT))
    m = re.search(r"outstanding (\d+)", out.stdout)
    return (int(m.group(1)) if m else -1), out.stdout


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--brief", required=True)
    ap.add_argument("--json")
    ap.add_argument("--keep", help="write the reconciliation here instead of a temp dir")
    a = ap.parse_args()

    reckon = newest_reckon()
    if reckon is None:
        print("the installed reckon could not be found, so nothing was reconciled. "
              "An absent instrument is a lane failure, not a pass.")
        return 2

    print(f"reckon {reckon.parts[-5]} — resolved, not pinned")
    outstanding, ledger_out = ledger_open()
    if outstanding < 0:
        print("ledger_gate.py did not print an outstanding count, so the ledger was not read.")
        print(ledger_out[-500:])
        return 2

    work = Path(a.keep) if a.keep else Path(tempfile.mkdtemp(prefix="goal-reckon-"))
    if work.exists() and not a.keep:
        shutil.rmtree(work, ignore_errors=True)
    try:
        built = subprocess.run(
            [sys.executable, str(reckon), "build",
             "--briefs", "docs/features-to-triage",
             "--campaign", "docs/test-campaign", "--out", str(work)],
            capture_output=True, text=True, cwd=str(ROOT))
        ledger_json = work / "ledger.json"
        if not ledger_json.is_file():
            print("reckon build produced no ledger.json, so nothing was reconciled:")
            print((built.stdout + built.stderr)[-600:])
            return 2
        rows = json.loads(ledger_json.read_text())
        rows = rows["rows"] if isinstance(rows, dict) else rows

        gated = subprocess.run([sys.executable, str(reckon), "check", str(ledger_json)],
                               capture_output=True, text=True, cwd=str(ROOT))
    finally:
        if not a.keep:
            shutil.rmtree(work, ignore_errors=True)

    by_class: dict[str, list[dict]] = {}
    for r in rows:
        by_class.setdefault(r.get("class", "?"), []).append(r)

    known = declared(ROOT / a.brief)
    undecided = by_class.get("undecided", [])
    broken = by_class.get("broken", [])
    unmeasured = by_class.get("unmeasured", [])
    undeclared_broken = [r for r in broken if r["id"] not in known]
    undeclared_unmeasured = [r for r in unmeasured if r["id"] not in known]

    print(f"{len(rows)} reckon row(s) · ledger outstanding {outstanding} · "
          f"reckon check exit {gated.returncode}")
    print(f"  undecided   {len(undecided):>3}  must be 0")
    print(f"  broken      {len(broken):>3}  {len(undeclared_broken)} not declared in {a.brief}")
    print(f"  unmeasured  {len(unmeasured):>3}  {len(undeclared_unmeasured)} not declared in "
          f"{a.brief}")
    print(f"  declared ids, read from the brief's declared:begin block only: "
          f"{', '.join(sorted(known)) or '(none)'}")

    problems: list[str] = []
    if outstanding:
        problems.append(f"{outstanding} ledger row(s) are still in an open status")
    if gated.returncode:
        problems.append(f"reckon's own gate exits {gated.returncode} — the partition lost an "
                        f"item or placed one illegally, so its numbers cannot be trusted")
    for r in undecided:
        problems.append(f"undecided: {r['id']} — {(r.get('title') or '')[:70]}")
    for r in undeclared_broken:
        problems.append(f"broken and undeclared: {r['id']} — {(r.get('title') or '')[:70]}")
    for r in undeclared_unmeasured:
        problems.append(f"unmeasured and undeclared: {r['id']} — {(r.get('title') or '')[:70]}")

    if problems:
        print()
        for p in problems[:24]:
            print(f"  {p}")
        if len(problems) > 24:
            print(f"  … and {len(problems) - 24} more")

    if a.json:
        Path(a.json).write_text(json.dumps(
            {"rows": len(rows), "outstanding": outstanding,
             "reckonCheckExit": gated.returncode,
             "undecided": [r["id"] for r in undecided],
             "broken": [r["id"] for r in broken],
             "unmeasured": [r["id"] for r in unmeasured],
             "undeclaredBroken": [r["id"] for r in undeclared_broken],
             "undeclaredUnmeasured": [r["id"] for r in undeclared_unmeasured],
             "declared": sorted(known)}, indent=2) + "\n")

    print()
    if problems:
        print(f"FAIL  {len(problems)} thing(s) remain.")
        return 1
    print(f"PASS: the ledger has no open row, reckon holds no undecided row, and every broken "
          f"and unmeasured row is one the brief declares by id.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
