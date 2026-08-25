#!/usr/bin/env python3
"""Evidence-plane census — say what each case checked its claim against.

The oracle rung says what a case checked. The plane says what it checked it
*against*, and the two are independent: a case can stand honestly at `outcome`,
asserting a real state change against a named observable, while the thing it
changed was a stub living in the same process.

`campaign.py check` prints `Planes: NOT DECLARED` until every passing case
names one, and an undeclared census is the empty-denominator failure rather
than a clean result. This script places every case by a written rule, so the
placement is auditable and a re-run is reproducible.

The four planes, weakest to strongest:

  in-tree        the collaborator lived in this test process
  hermetic       a real separate process, socket or file tree the fixture owns
  live-glass     a real GUI process attached to a window server
  live-external  a system outside this host's process tree (a guest VM)

Placement reads the evidence rather than the case's account of itself. An
artifact is opened and classed by what produced it: a Swift Testing run leaves
`Test run with N tests`, and a campaign instrument leaves anything else. That
distinction is the whole of why an artifact-cited case is not automatically
hermetic — a suite verdict written to a file is still an in-process assertion.

  plane_census.py <campaign-dir> [--write] [--gate] [--receipts <dir>]

`--write` stamps `plane` onto every case. `--gate` exits 1 when a passing case
carries none, or when a case's plane exceeds what its lane can reach. Neither
adopts a placement it did not just derive: `--write` recomputes from the rules
and overwrites, so an edited plane that the rules no longer support is reported
rather than preserved.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

PLANES = ("in-tree", "hermetic", "live-glass", "live-external")
RANK = {p: i for i, p in enumerate(PLANES)}

# What a lane can reach. A headless lane never attached to a window server, so a
# case on it cannot rest on glass however its evidence reads.
LANE_CEILING = {
    "headless": "hermetic",
    "macos": "live-glass",
    "macos-glass": "live-glass",
    "guest-glass": "live-external",
    None: "live-glass",
}

# A Swift Testing or XCTest run leaves one of these in its output. Anything else
# under an evidence directory was written by an instrument that ran as its own
# process against real files.
SWIFT_RUN = re.compile(r"Test run with \d+ tests|Executed \d+ tests|Test Suite '.*' (passed|failed)")

GLASS_HINT = re.compile(r"evidence/witness/|overlay-[a-z-]*\.json|/shots/|\.png$")


def strongest(a: str, b: str) -> str:
    return a if RANK[a] >= RANK[b] else b


def cap(plane: str, ceiling: str) -> str:
    return plane if RANK[plane] <= RANK[ceiling] else ceiling


def artifact_plane(path: str, root: Path) -> tuple[str, str]:
    """Class one evidence path, returning (plane, the reason it was placed)."""
    p = path.strip()
    if p.startswith("sabotage"):                      # "sabotage <path>" prose
        p = p.split(None, 1)[-1]
    if p.startswith("sabotage control"):
        p = p.split(None, 2)[-1]

    if GLASS_HINT.search(p):
        return "live-glass", "a capture or window witness off a display server"
    if p.startswith(("Tests/", "Sources/")):
        return "in-tree", "a source or test file in this package"
    if "scripts/" in p:
        return "hermetic", "a campaign instrument that runs as its own process"
    if p.startswith("~") or p.startswith("/Users") or p.startswith("/"):
        return "hermetic", "a real file tree outside this package"

    resolved = root / p
    if not resolved.exists():
        resolved = root.parent.parent / p            # repo-relative citation
    if resolved.is_file():
        try:
            head = resolved.read_text(errors="replace")[:8000]
        except OSError:
            head = ""
        if SWIFT_RUN.search(head):
            return "in-tree", "a recorded Swift test run, whose collaborators are in-process"
        return "hermetic", "an artifact written by a run outside the test process"
    return "in-tree", "no artifact on disk to place it any higher"


def place(case: dict, root: Path) -> tuple[str, str]:
    lane = case.get("lane")
    ceiling = LANE_CEILING.get(lane, "live-glass")
    oracle = case.get("oracle")

    if lane == "guest-glass":
        return "live-external", "the guest lane runs outside this host's process tree"
    if oracle in ("raster-visual", "interactive-glass"):
        return cap("live-glass", ceiling), f"the {oracle} rung owes a display server"
    if oracle == "source-analysis":
        return "in-tree", "the subject is source text; nothing ran outside this process"

    best, why = "in-tree", "no evidence placed it higher"
    for e in case.get("evidence") or []:
        pl, reason = artifact_plane(e, root)
        if RANK[pl] > RANK[best]:
            best, why = pl, reason
    capped = cap(best, ceiling)
    if capped != best:
        why = f"{why}, held at {capped} by the {lane} lane"
    return capped, why


def load(campaign: Path):
    cases = json.loads((campaign / "cases.json").read_text())
    if isinstance(cases, dict):
        cases = cases.get("case") or cases.get("cases") or []
    return cases


def digest(path: Path) -> str | None:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()[:16]
    except OSError:
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("campaign", type=Path)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--receipts", type=Path, default=None,
                    help="write one plane receipt per case, with evidence digests")
    a = ap.parse_args()

    campaign = a.campaign.resolve()
    root = campaign
    cases = load(campaign)

    placed, counts, reasons = {}, {p: 0 for p in PLANES}, {}
    for c in cases:
        pl, why = place(c, root)
        placed[c["id"]] = pl
        reasons[c["id"]] = why
        counts[pl] += 1

    passing = [c for c in cases if str(c.get("status", "")).startswith("pass")]
    pass_counts = {p: 0 for p in PLANES}
    for c in passing:
        pass_counts[placed[c["id"]]] += 1

    if a.write:
        raw = json.loads((campaign / "cases.json").read_text())
        seq = raw if isinstance(raw, list) else (raw.get("case") or raw.get("cases"))
        moved = 0
        for c in seq:
            new = placed[c["id"]]
            if c.get("plane") != new:
                moved += 1
            c["plane"] = new
        (campaign / "cases.json").write_text(json.dumps(raw, indent=2) + "\n")
        print(f"wrote plane on {len(seq)} case(s); {moved} changed")

    if a.receipts:
        a.receipts.mkdir(parents=True, exist_ok=True)
        for c in cases:
            ev = []
            for e in c.get("evidence") or []:
                p = (root / e)
                if not p.exists():
                    p = root.parent.parent / e
                ev.append({"path": e, "sha256_16": digest(p) if p.is_file() else None,
                           "present": p.is_file()})
            (a.receipts / f"{c['id']}.json").write_text(json.dumps({
                "case": c["id"], "requirement": c.get("req"), "lane": c.get("lane"),
                "oracle": c.get("oracle"), "plane": placed[c["id"]],
                "placedBecause": reasons[c["id"]], "evidence": ev,
            }, indent=2) + "\n")
        print(f"wrote {len(cases)} receipt(s) to {a.receipts}")

    print()
    print(f"plane census over {len(cases)} case(s), {len(passing)} passing")
    for p in PLANES:
        print(f"  {p:<14} {counts[p]:>4} declared · {pass_counts[p]:>4} passing")
    print()

    if a.gate:
        unplaced = [c["id"] for c in passing if not placed.get(c["id"])]
        over = [f"{c['id']} ({placed[c['id']]} on the {c.get('lane')} lane)"
                for c in cases
                if RANK[placed[c["id"]]] > RANK[LANE_CEILING.get(c.get("lane"), "live-glass")]]
        if unplaced or over:
            for x in unplaced:
                print(f"FAIL  {x} passes and names no plane")
            for x in over:
                print(f"FAIL  {x} rests higher than its lane reaches")
            return 1
        print("gate: every passing case names a plane its lane can reach.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
