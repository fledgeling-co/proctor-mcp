#!/usr/bin/env python3
"""Which durable boundaries a case actually cuts, against which the journey claims.

PRO-0162. A journey declares `boundariesCut` and a case declares a `journey`,
and nothing joins a cut to the thing that cuts it — so an asserted cut and a cut
with a passing effect-rung case behind it are the same five strings in the same
list. `boundaries 44/50 cut` is a count of assertions.

That is not a hypothetical. JRN-006's own note said no case witnessed the audit
trail's bytes on disk independently of the code that wrote them, while CASE-0061
had been doing exactly that since it was written. The case carried no journey,
the journey carried no case, and nothing reported the disagreement.

WHAT A CUT NEEDS, to be one. A passing case at or above the `outcome` rung,
attached to the journey, naming the boundary in its `cuts` field. Anything less
is the journey's own account of itself, which is the thing being checked.

This REPORTS rather than rewrites. Deriving the list and writing it would drop
the campaign's boundary count to whatever is currently evidenced and take the
critical-journey rule down with it in the same commit — two changes, one of them
unmeasured. The count moves when cases are written, which is the work.

    python3 scripts/campaign/journey_census.py [--gate] [--json OUT]

Exit codes
    0   the number of asserted-without-a-case cuts is at or below the ratchet
    1   it rose, or a case names a boundary that is not one of the five
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAMPAIGN = ROOT / "docs" / "test-campaign"
RATCHET = CAMPAIGN / "journey-cut-ratchet.json"

# The five durable boundaries. A cut names one of these or it names nothing.
BOUNDARIES = ["request-issued", "server-committed", "provider-effect",
              "client-persisted", "user-acknowledged"]
EFFECT_RUNGS = {"outcome", "metamorphic", "effect-witness", "raster-visual",
                "interactive-glass"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--campaign", default=str(CAMPAIGN))
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--set-ratchet", action="store_true", dest="set_ratchet")
    ap.add_argument("--json")
    a = ap.parse_args()

    campaign_dir = Path(a.campaign)
    inv = json.loads((campaign_dir / "inventory.json").read_text())
    raw = json.loads((campaign_dir / "cases.json").read_text())
    cases = raw if isinstance(raw, list) else raw.get("cases", [])

    evidenced: dict[str, dict[str, list[str]]] = {}
    bad_names = []
    for c in cases:
        cut = c.get("cuts")
        if not cut:
            continue
        if cut not in BOUNDARIES:
            bad_names.append({"case": c["id"], "cuts": cut})
            continue
        if c.get("status") != "pass" or c.get("oracle") not in EFFECT_RUNGS:
            continue
        jid = c.get("journey")
        if not jid:
            continue
        evidenced.setdefault(jid, {}).setdefault(cut, []).append(c["id"])

    rows, asserted_only, evidenced_total, asserted_total = [], [], 0, 0
    for j in inv.get("journey", []):
        claimed = list(j.get("boundariesCut") or [])
        have = evidenced.get(j["id"], {})
        asserted_total += len(claimed)
        evidenced_total += len([b for b in claimed if b in have])
        gap = [b for b in claimed if b not in have]
        extra = [b for b in have if b not in claimed]
        rows.append({"journey": j["id"], "critical": bool(j.get("critical")),
                     "claimed": claimed, "evidenced": sorted(have),
                     "assertedOnly": gap, "evidencedNotClaimed": extra})
        for b in gap:
            asserted_only.append({"journey": j["id"], "boundary": b})

    print(f"{len(rows)} journey(s) · {asserted_total} of {len(rows) * 5} boundaries claimed cut")
    print(f"  with a passing effect-rung case naming them   {evidenced_total}")
    print(f"  asserted, with no case behind them            {len(asserted_only)}")
    for r in rows:
        mark = "critical" if r["critical"] else "        "
        print(f"  {r['journey']} {mark} claimed {len(r['claimed'])}/5 · "
              f"evidenced {len(r['evidenced'])}"
              + (f" · {', '.join(r['evidenced'])}" if r["evidenced"] else ""))
        if r["evidencedNotClaimed"]:
            print(f"      a case cuts what the journey does not claim: "
                  f"{', '.join(r['evidencedNotClaimed'])}")

    if bad_names:
        print()
        print("A case names a boundary that is not one of the five:")
        for r in bad_names:
            print(f"  {r['case']}  {r['cuts']!r}")

    allowed = None
    if RATCHET.is_file():
        allowed = json.loads(RATCHET.read_text()).get("assertedOnly")
    if a.set_ratchet:
        RATCHET.write_text(json.dumps(
            {"assertedOnly": len(asserted_only),
             "note": ("Boundaries a journey claims cut with no passing effect-rung case naming "
                      "them. Lower it only by writing a case that cuts one, never to make a run "
                      "green. It starts high because nothing joined cuts to cases until now.")},
            indent=2) + "\n")
        print(f"\nratchet set to {len(asserted_only)}"
              + (f" (was {allowed})" if allowed is not None else ""))
        return 0

    if a.json:
        Path(a.json).write_text(json.dumps(
            {"journeys": rows, "assertedOnly": asserted_only, "badNames": bad_names,
             "evidenced": evidenced_total, "claimed": asserted_total}, indent=2) + "\n")

    print()
    if bad_names:
        print(f"FAIL  {len(bad_names)} case(s) name a boundary outside the five.")
        return 1
    if allowed is None:
        print(f"{len(asserted_only)} asserted-only cut(s) and no ratchet recorded.")
        return 1 if a.gate else 0
    print(f"ratchet: {allowed} asserted-only cut(s) allowed, {len(asserted_only)} measured")
    if len(asserted_only) > allowed:
        print(f"FAIL  it ROSE from {allowed} to {len(asserted_only)} — a journey claims a cut "
              f"that nothing evidences.")
        return 1 if a.gate else 0
    if len(asserted_only) < allowed:
        print(f"{allowed - len(asserted_only)} cut(s) gained a case since the ratchet was set — "
              f"lower it with --set-ratchet in the same commit.")
        return 1 if a.gate else 0
    print("held.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
