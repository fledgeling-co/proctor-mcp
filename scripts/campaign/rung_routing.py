#!/usr/bin/env python3
"""Route every case below the effect rung: raisable, or permanently structural.

497 cases pass and 438 are checked. The gap is 62, and 43 of those stand at
`source-analysis` — a rung that reads a fact off the source and witnesses no
effect. Under *unchecked is failed* they are failures, and the same 43 are what
blocks all five short warrant classes, so aggregated they read as five separate
shortfalls and named they are one population.

They are not one KIND of thing, though, and that is what this decides. A case
asserting *no code path constructs a shutdown argument* has no runtime
observable: the absence of a path cannot be witnessed by running anything, and
the analyzer is the only instrument that can settle it. A case asserting *every
user-facing string comes from one catalogue* has one — the strings a running app
renders — and the analyzer is standing in for a reading nobody has taken.

The first is permanently structural and should say so in terms that stay true.
The second is raisable and should be raised. Marking either as the other is the
failure: calling a raisable case structural raises the score and lowers what the
suite knows, and calling a structural case raisable leaves a row open forever.

**Nothing here changes a case's rung.** It records the routing decision and its
reason, so the work is a list somebody can execute and the count of each kind is
published. Raising a case is a case's own work, and doing it from a router would
be this file grading its own homework.

  rung_routing.py <campaign-dir> [--write] [--gate] [--json PATH]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

EFFECT_RUNGS = {"outcome", "metamorphic", "effect-witness",
                "raster-visual", "interactive-glass"}

# A claim about the ABSENCE of something in the source. No run can witness an
# absence: you can watch a thing happen, and you cannot watch it not happen
# anywhere. The analyzer is the only instrument that settles these, and they are
# structural by construction rather than by anybody's judgement.
ABSENCE = re.compile(
    r"\bno (?:code path|call site|other|such|line|site|test|case|surface|file)\b|"
    r"\bnever (?:constructs?|calls?|writes?|reaches?|appears?)\b|"
    r"\bnothing (?:constructs?|calls?|writes?|reaches?)\b|"
    r"\bexactly one\b|\bonly one\b|\bno .{0,24} exists\b|"
    # An explicit negative about what the source does. Four cases here assert a
    # thing is NOT done — "1.2 is NOT raised" — and that is an absence claim in
    # the same way "no code path" is, written the other way round.
    r"\bis NOT\b|\bare NOT\b|\bdoes not (?:construct|call|write|reach|raise)\b|"
    # A census over source lines is a measurement OF the source. It reports how
    # many lines were read, and running the product changes none of them.
    r"\bread off the tree\b|\blines? of \w+\.swift\b|\bexamined between them\b", re.I)

# A claim about what a RUNNING thing shows or does. These have an observable and
# the analyzer is standing in for a reading nobody took.
OBSERVABLE = re.compile(
    r"\buser-facing string|\brenders?\b|\bdraws?\b|\bdisplay(?:s|ed)?\b|"
    r"\bon screen\b|\bthe window\b|\bthe panel\b|\bthe menu\b|\breports?\b|"
    r"\breturns?\b|\banswers?\b|"
    # Two shapes read off the undecided rows rather than guessed. A case saying a
    # glass lane could find the thing has named its own observable and the lane
    # that would read it. A case establishing that the code the tests drive is
    # the code that RUNS is a wiring claim whose observable is the production
    # path's own verdict.
    r"\bglass lane can find\b|\bthe code that runs\b|\bthe production (?:verdict|path)\b",
    re.I)


def route(case: dict) -> tuple[str, str]:
    text = " ".join(filter(None, [
        case.get("note") or "",
        json.dumps(case.get("source") or {}),
        case.get("armedBy") or "",
    ]))
    if ABSENCE.search(text):
        return ("structural",
                "the claim is about the ABSENCE of something in the source, and no run can "
                "witness an absence — the analyzer is the only instrument that settles it")
    if OBSERVABLE.search(text):
        return ("raisable",
                "the claim names something a running build shows or returns, so an observable "
                "exists and the analyzer is standing in for a reading nobody has taken")
    return ("undecided",
            "neither an absence nor a named observable could be read off this row; a person "
            "has to look, and this tool will not guess which it is")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("campaign", type=Path)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--json", type=Path, default=None)
    a = ap.parse_args()

    raw = json.loads((a.campaign / "cases.json").read_text())
    seq = raw if isinstance(raw, list) else (raw.get("case") or raw.get("cases") or [])

    below = [c for c in seq
             if str(c.get("status", "")).startswith("pass")
             and c.get("oracle") not in EFFECT_RUNGS]
    unarmed = [c for c in seq
               if str(c.get("status", "")).startswith("pass") and not c.get("armed")]

    rows = []
    for c in below:
        verdict, why = route(c)
        rows.append({"case": c["id"], "surface": c.get("surface"), "req": c.get("req"),
                     "oracle": c.get("oracle"), "routed": verdict, "why": why})

    counts = Counter(r["routed"] for r in rows)
    print(f"{len(seq)} case(s) · {len(below)} below the effect rung · {len(unarmed)} unarmed")
    for k in ("raisable", "structural", "undecided"):
        print(f"  {k:<12} {counts.get(k, 0):>4}")
    print()
    for k in ("raisable", "undecided"):
        sel = [r for r in rows if r["routed"] == k]
        if not sel:
            continue
        print(f"{k} ({len(sel)}):")
        for r in sel[:12]:
            print(f"  {r['case']}  {r['surface']}  {r['req']}")
        if len(sel) > 12:
            print(f"  … and {len(sel) - 12} more")
        print()

    if a.write:
        for c in seq:
            m = next((r for r in rows if r["case"] == c["id"]), None)
            if m:
                c["rungRouting"] = {"verdict": m["routed"], "why": m["why"]}
        (a.campaign / "cases.json").write_text(json.dumps(raw, indent=2) + "\n")
        print(f"wrote a routing verdict onto {len(rows)} case(s)")

    if a.json:
        a.json.write_text(json.dumps({"belowEffectRung": len(below), "unarmed": len(unarmed),
                                      "counts": dict(counts), "rows": rows}, indent=2) + "\n")
        print(f"wrote {a.json}")

    if a.gate:
        # The gate is on the UNDECIDED count, not on the raisable one. A raisable
        # case is a piece of work with a name; an undecided one is a row nobody
        # has looked at, and it is the only class here that can hide.
        if counts.get("undecided"):
            print(f"\nFAIL  {counts['undecided']} case(s) below the effect rung could not be "
                  f"routed. A row nobody has classed is the one that stays open forever.")
            return 1
        print(f"\ngate: every case below the effect rung is routed — "
              f"{counts.get('raisable', 0)} raisable, {counts.get('structural', 0)} structural.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
