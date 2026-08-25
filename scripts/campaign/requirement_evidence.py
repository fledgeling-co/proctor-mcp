#!/usr/bin/env python3
"""Move a requirement's evidence word only where cases already carry it.

`evidence` is a word in a registry a person can edit, and one campaign moved
eight requirements from `unmeasured` to `observed` in a single session with no
case having run in between. reckon 1.7.0 added `backed_by` for exactly that: a
requirement leaves `unmeasured` on the cases that cite it, never on its own
account of itself.

This applies the same bar before the word is written rather than after, so the
registry and the reckoning cannot disagree:

  observed  ⟸  at least one PASSING case names this requirement in its `req`

Nothing else qualifies. A requirement with citing cases that all failed, or with
none at all, keeps whatever word it had and is reported. A `ceiling` or
`deferred` requirement is left alone whatever its cases say — a limit recorded
on purpose is not an observation, and `campaign.py`'s evidence vocabulary has no
word for it, so the honest place for it is `unmeasured` with the reason visible.

It also fills `surfaces` where the registry has none, from the surfaces those
same cases sit on. That field is what lets a brief citing a requirement reach a
case at all: reckon looks cases up by surface, so a requirement with no surface
is a dead end for every brief that names it.

  requirement_evidence.py <campaign-dir> [--write] [--gate]
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

# Classes whose whole point is that they are not observed. A ceiling records how
# far a disclosure can reach; a deferred item records a decision to wait.
NOT_OBSERVABLE = {"ceiling", "deferred"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("campaign", type=Path)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--gate", action="store_true")
    a = ap.parse_args()

    inv = json.loads((a.campaign / "inventory.json").read_text())
    raw = json.loads((a.campaign / "cases.json").read_text())
    cases = raw if isinstance(raw, list) else (raw.get("case") or raw.get("cases") or [])

    backing: dict[str, list[dict]] = defaultdict(list)
    for c in cases:
        if not str(c.get("status", "")).startswith("pass"):
            continue
        cited = c.get("req")
        for rid in ([cited] if isinstance(cited, str) else (cited or [])):
            if rid:
                backing[rid].append(c)

    promoted, refused, held, surfaced = [], [], [], []
    for r in inv.get("requirement", []):
        rid, ev = r["id"], (r.get("evidence") or "unknown").lower()
        cs = backing.get(rid, [])

        if not r.get("surfaces") and cs:
            surfs = sorted({c["surface"] for c in cs if c.get("surface")})
            if surfs:
                surfaced.append((rid, surfs))
                if a.write:
                    r["surfaces"] = surfs

        if ev == "observed":
            continue
        if (r.get("class") or "") in NOT_OBSERVABLE:
            held.append((rid, r.get("class"), len(cs)))
            continue
        if not cs:
            refused.append((rid, ev, "no passing case names it"))
            continue
        rungs = sorted({c.get("oracle") for c in cs})
        promoted.append((rid, ev, [c["id"] for c in cs][:5], rungs))
        if a.write:
            r["evidence"] = "observed"
            note = r.get("note") or ""
            stamp = ("observed on %d passing case(s) citing it: %s"
                     % (len(cs), ", ".join(sorted(c["id"] for c in cs)[:6])))
            r["note"] = (note + " · " + stamp).strip(" ·") if stamp not in note else note

    print(f"{len(promoted)} requirement(s) qualify for `observed` — a passing case names each")
    for rid, was, ids, rungs in promoted:
        print(f"  {rid}  {was:<9} -> observed   on {', '.join(ids)}  ({'|'.join(rungs)})")
    print(f"\n{len(held)} held back because their class is not an observable one:")
    for rid, cls, n in held:
        print(f"  {rid}  class={cls}  ({n} passing case(s), and the word still would not be "
              f"`observed` — a limit recorded on purpose is not an observation)")
    print(f"\n{len(refused)} refused — nothing passing names them:")
    for rid, ev, why in refused:
        print(f"  {rid}  evidence={ev}  {why}")
    print(f"\n{len(surfaced)} requirement(s) gain a surface derived from the cases that cite them")

    if a.write:
        (a.campaign / "inventory.json").write_text(json.dumps(inv, indent=2) + "\n")
        print("\nwritten.")
    else:
        print("\nDRY RUN — pass --write to apply.")

    if a.gate:
        # The gate is the invariant, not the promotion: no requirement may read
        # `observed` while nothing passing cites it.
        bad = [r["id"] for r in inv.get("requirement", [])
               if (r.get("evidence") or "").lower() == "observed" and not backing.get(r["id"])]
        if bad:
            print(f"\nFAIL  {len(bad)} requirement(s) read `observed` with no passing case "
                  f"citing them: {', '.join(bad[:8])}")
            return 1
        print("\ngate: every `observed` requirement is backed by a passing case that names it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
