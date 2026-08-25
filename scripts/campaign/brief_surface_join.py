#!/usr/bin/env python3
"""Complete the brief→registry join with the surface the registry already names.

`reckon.py` reads a brief's cited ids, then looks each one up in a table keyed
by **surface**. A brief citing `REQ-004` therefore reaches no case at all, its
strongest oracle reads as `none`, and it lands in `undecided` with the reason
"below the outcome floor for retiring intent" — which is a fact about the
lookup rather than about the work.

111 of this repository's 113 undecided briefs are that shape.

The missing hop already exists in the registry: every requirement declares the
surfaces it lives on. So this transcribes `inventory.json`'s own
`requirement.surfaces` into the brief's sources, and records where each added id
came from.

**Why this is a transcription and not a document edited to satisfy a tool.**
reckon's own guidance warns that a citation written during a reckoning is the
weakest kind there is, and it is right. The guard here is that nothing is
invented: an id is added only when the registry already states the relation,
the frontmatter records the derivation and the requirement it came from, and
the rung a brief is then judged on is still read off real cases that really
passed. A brief whose surfaces carry no passing case at `outcome` stays exactly
where it was. Run with `--dry-run` first; the report says how many rows move and
that number belongs in the commit message.

  brief_surface_join.py [--briefs DIR] [--campaign DIR] [--dry-run|--write]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FM = re.compile(r"\A---\n(.*?)\n---\n", re.S)
SOURCES = re.compile(r"^(reckon-sources:\s*)\[([^\]]*)\]\s*$", re.M)


def requirement_surfaces(campaign: Path) -> dict[str, list[str]]:
    inv = json.loads((campaign / "inventory.json").read_text())
    return {r["id"]: [s for s in (r.get("surfaces") or [])]
            for r in inv.get("requirement", []) if r.get("surfaces")}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--briefs", type=Path, default=ROOT / "docs" / "features-to-triage")
    ap.add_argument("--campaign", type=Path, default=ROOT / "docs" / "test-campaign")
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    req_surf = requirement_surfaces(a.campaign)
    moved, untouched, no_hop = 0, 0, []

    for f in sorted(a.briefs.rglob("*.md")):
        text = f.read_text()
        m = FM.match(text)
        if not m:
            untouched += 1
            continue
        s = SOURCES.search(m.group(1))
        if not s:
            untouched += 1
            continue
        ids = [x.strip() for x in s.group(2).split(",") if x.strip()]
        reqs = [i for i in ids if i.startswith("REQ-")]
        if not reqs:
            untouched += 1
            continue
        add: dict[str, str] = {}
        for r in reqs:
            for surf in req_surf.get(r, []):
                if surf not in ids and surf not in add:
                    add[surf] = r
        if not add:
            no_hop.append((f.name, reqs))
            continue

        new_ids = ids + sorted(add)
        line = f"{s.group(1)}[{', '.join(new_ids)}]"
        prov = ("reckon-surfaces-derived: "
                + "; ".join(f"{k} from {v}.surfaces" for k, v in sorted(add.items())))
        block = m.group(1)
        block = SOURCES.sub(line, block, count=1)
        if "reckon-surfaces-derived:" in block:
            block = re.sub(r"^reckon-surfaces-derived:.*$", prov, block, flags=re.M)
        else:
            block = block + "\n" + prov
        moved += 1
        if a.write:
            f.write_text(f"---\n{block}\n---\n" + text[m.end():])

    print(f"{moved} brief(s) gain a surface the registry already names for a requirement "
          f"they already cite")
    print(f"{untouched} carry no reckon-sources frontmatter, or cite no requirement")
    if no_hop:
        print(f"{len(no_hop)} cite a requirement that declares no surface — the hop does not "
              f"exist in the registry, so nothing was invented for them:")
        for name, reqs in no_hop[:8]:
            print(f"  {name}  ({', '.join(reqs[:4])})")
    print("\nDRY RUN — pass --write to apply." if not a.write else "\nwritten.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
