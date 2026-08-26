#!/usr/bin/env python3
"""Every case's lane, derived by a written rule or left unassigned and named.

DEF-340. 106 of 518 cases carried no lane and `campaign.py` reported them as one
`unassigned` row — a fifth of the campaign sitting outside every lane ledger,
which is the failure a per-lane ledger exists to prevent.

The row was recorded rather than closed, for a reason worth keeping: only 9 of
the 106 name a lane readably in their own evidence, and assigning the other 97
from what a case looks like is how a lane hides. That objection is to INFERENCE.
It is not an objection to a RULE, and `plane_census.py` already settles the same
kind of question the same way: it places every case on a plane by rules written
down here rather than by reading each one.

THE RULES, AND WHY EACH IS A RULE RATHER THAN A GUESS.

    in-tree, hermetic  ->  headless
        These planes mean the collaborator was in this process or a stub of it.
        There is no display server, no second machine and no attached app: the
        case ran under `swift test` or a python instrument. That is what the
        headless lane IS, not what its cases tend to look like.

    live-glass         ->  macos-glass, unless evidence names a guest
        `plane_census` already treats a `-glass` lane suffix as a floor as well
        as a ceiling. The inverse holds: a case that reached a display server
        ran on a glass lane. Which one is readable — every one of the 16
        live-glass cases that already declares a lane declares `macos-glass`,
        and a guest run names the guest in its evidence.

    live-external      ->  not derived
        A subprocess, a simulator and a guest VM are all live-external and are
        different lanes. Nothing in the plane distinguishes them, so these are
        left unassigned and listed rather than placed.

    python3 scripts/campaign/lane_census.py [--write] [--gate] [--json OUT]

Exit codes
    0   every case carries a lane, or is listed as one the rules cannot place
    1   a case carries a lane no campaign.json declares, or --gate was asked for
        while cases the rules COULD place are still unassigned
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAMPAIGN = ROOT / "docs" / "test-campaign"

PLANE_LANE = {"in-tree": "headless", "hermetic": "headless"}
GUEST_HINTS = ("guest", "lume", "proctor-guest")


def named_in_evidence(case: dict, declared: set[str]) -> str | None:
    """A lane the case's own note or evidence names, which beats any rule.

    DEF-340 records that 9 of the 106 name a lane readably and that assigning
    the rest from what a case looks like is how a lane hides. The rules below
    are not that — but they are coarser than a case's own words, and the first
    run proved it: six cases whose notes say things like "first case the cli
    lane has ever carried" were placed on `headless` because their plane is
    hermetic. The evidence wins.
    """
    import re
    blob = (case.get("note") or "") + " " + " ".join(case.get("evidence") or [])
    # How a lane is SPELLED in prose is not how it is spelled in campaign.json.
    # CASE-0001's note says "real MCP stdio (mcp_drive.py initialize +
    # tools/list)" — unmistakably the mcp-stdio lane, and the hyphenated token
    # never appears, so the first version placed it on headless by plane and
    # left the declared lane carrying nothing. Each alternative below is quoted
    # from a case that was read.
    SPELLINGS = {
        "mcp-stdio": [r"\bMCP stdio\b", r"\bmcp[-_ ]stdio\b"],
        "cli": [r"\bcli\b"],
        "ios-sim": [r"\bios[-_ ]sim\b", r"\bsimulator\b"],
        "guest-glass": [r"\bguest[-_ ]glass\b"],
        "macos-glass": [r"\bmacos[-_ ]glass\b"],
        "headless": [r"\bheadless\b"],
        "macos": [r"\bmacos\b(?!-)"],
    }
    # Longest first, so `macos-glass` is not matched as `macos`.
    for lane in sorted(declared, key=len, reverse=True):
        for pattern in SPELLINGS.get(lane, [r"\b" + re.escape(lane) + r"\b(?!-)"]):
            if re.search(pattern, blob, re.I):
                return lane
    return None


def derive(case: dict) -> tuple[str | None, str]:
    plane = case.get("plane")
    if plane in PLANE_LANE:
        return PLANE_LANE[plane], f"plane {plane}: in this process, so no display and no peer"
    if plane == "live-glass":
        blob = json.dumps(case).lower()
        if any(h in blob for h in GUEST_HINTS):
            return "guest-glass", "plane live-glass and its evidence names a guest"
        return "macos-glass", ("plane live-glass and nothing names a guest; every live-glass "
                               "case that declares a lane declares macos-glass")
    return None, f"plane {plane!r} does not decide a lane — a subprocess, a simulator and a guest are all live-external"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--campaign", default=str(CAMPAIGN))
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args()

    campaign_dir = Path(a.campaign)
    declared = set(json.loads((campaign_dir / "campaign.json").read_text()).get("lanes") or [])
    cases_path = campaign_dir / "cases.json"
    cases = json.loads(cases_path.read_text())
    rows = cases if isinstance(cases, list) else cases["cases"]

    placed, unplaceable, undeclared, already = [], [], [], 0
    written = 0
    for c in rows:
        lane = c.get("lane")
        if lane:
            already += 1
            if lane not in declared:
                undeclared.append({"case": c["id"], "lane": lane})
            continue
        spoken = named_in_evidence(c, declared)
        if spoken:
            derived, why = spoken, f"its own note or evidence names the {spoken} lane"
        else:
            derived, why = derive(c)
        row = {"case": c["id"], "plane": c.get("plane"), "lane": derived, "why": why}
        if derived is None:
            unplaceable.append(row)
            continue
        placed.append(row)
        if a.write:
            c["lane"] = derived
            c["laneNote"] = f"Derived by lane_census.py — {why}."
            written += 1

    total = len(rows)
    print(f"{total} case(s) · {already} already carry a lane · {len(placed)} placed by rule · "
          f"{len(unplaceable)} the rules cannot place")
    for lane in sorted(declared):
        n = sum(1 for c in rows if c.get("lane") == lane)
        print(f"  {lane:<14} {n}")

    if unplaceable:
        print()
        print("Left unassigned, and listed rather than placed:")
        for r in unplaceable[:20]:
            print(f"  {r['case']}  {r['why']}")
        if len(unplaceable) > 20:
            print(f"  … and {len(unplaceable) - 20} more")
    if undeclared:
        print()
        print("A case carries a lane campaign.json does not declare:")
        for r in undeclared:
            print(f"  {r['case']}  {r['lane']}")

    if a.write and written:
        cases_path.write_text(json.dumps(cases, indent=2) + "\n")
        print()
        print(f"wrote {written} lane(s), each with the rule that placed it")

    if a.json:
        Path(a.json).write_text(json.dumps(
            {"total": total, "already": already, "placed": placed,
             "unplaceable": unplaceable, "undeclared": undeclared}, indent=2) + "\n")

    print()
    if undeclared:
        print(f"FAIL  {len(undeclared)} case(s) name a lane campaign.json does not declare.")
        return 1
    if placed and a.gate:
        print(f"FAIL  {len(placed)} case(s) the rules can place are still unassigned. "
              f"Run with --write.")
        return 1
    print(f"PASS: {already} of {total} case(s) carry a lane; {len(unplaceable)} are listed as "
          f"ones the rules cannot place, and none is silently unassigned.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
