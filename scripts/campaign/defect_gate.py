#!/usr/bin/env python3
"""Two checks that make registry drift structural rather than remembered.

`inventory.json` reported 23 open defects while most of them were fixed and
merged. Reading each one against the tree found two separate mechanisms, and
this file holds one check for each.

**`claims`** — an item that says it fixes a defect should not be able to merge
while that defect still reads `open`. The claim is not a thing to remember: it
is written down, in the item's own spec, on the `**Defects:**` line and in the
`## Defects` table. So the check reads the spec, expands the ranges, and refuses
when a claimed defect is still open in the registry. REQ-067.

**`dropped`** — the drift the reconciliation actually found. Eleven values were
set by a merged item and are not at HEAD: five defect flips and REQ-024's
`vacuous` from PRO-0091, CASE-0032's evidence and note from PRO-0088,
CASE-0059's capture block, CASE-0063's witness block and DEF-024's whole row
from PRO-0078. `merge_registry.py` resolves a same-id conflict by keeping ours,
which is right for a hand merge and wrong for a merge nobody read afterwards.

The test for "was this value dropped, or legitimately changed" is the parent.
A commit that sets `x` where its parent held `y`, against a HEAD that holds `y`,
is a value the history set and the tree lost. A commit that sets `x` where its
parent also held `x` establishes nothing. That distinction is the whole check,
and it is why a legitimate later correction does not register as a drop.

    python3 scripts/campaign/defect_gate.py claims docs/specs/spec-PRO-0088.md docs/test-campaign
    python3 scripts/campaign/defect_gate.py dropped docs/test-campaign

Both exit 1 on a finding and 0 on none. `scripts/campaign/test_instruments.py`
arms both in each direction, so a check that cannot fire is distinguishable from
a check that found nothing.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

# The fields worth watching. A registry carries prose that is edited freely;
# these are the ones a reader draws a conclusion from.
WATCHED = ("status", "evidence", "oracle", "effect", "source", "witness", "capture")


# ---------------------------------------------------------------- claims


def claimed_defects(spec: Path) -> list[str]:
    """Every defect id an item's spec claims, from both places it states them.

    The header line reads `**Defects:** DEF-095..DEF-099` — a range, sometimes
    several, sometimes a comma list. The `## Defects` table names them one per
    row. Both are read because an item that overran its allocation records the
    extra in the table and not in the header, which is the shape PRO-0081 took.
    """
    text = spec.read_text()
    found: set[str] = set()

    header = re.search(r"^\*\*.*?Defects:\*\*(.*)$", text, re.MULTILINE)
    if header:
        for lo, hi in re.findall(r"DEF-(\d+)\s*\.\.\s*(?:DEF-)?(\d+)", header.group(1)):
            for n in range(int(lo), int(hi) + 1):
                found.add(f"DEF-{n:03d}")
        line = re.sub(r"DEF-\d+\s*\.\.\s*(?:DEF-)?\d+", "", header.group(1))
        found.update(re.findall(r"DEF-\d+", line))

    recorded: set[str] = set()
    table = re.search(r"^## Defects\s*$(.*?)(?=^## |\Z)", text, re.MULTILINE | re.DOTALL)
    if table:
        for row in table.group(1).splitlines():
            m = re.match(r"\s*\|\s*(DEF-\d+)\s*\|", row)
            if not m:
                continue
            # An item records defects it FOUND as well as ones it fixed, and the
            # two are different claims. PRO-0088's table held DEF-099, which it
            # found and deliberately left open; reading that as a fix claim
            # would make the gate refuse an item for being honest. So a row
            # marked `(recorded)` is a finding the item is not claiming to have
            # closed, and the check says how many it set aside.
            if re.search(r"\((?:recorded|not fixed)\)", row, re.IGNORECASE):
                recorded.add(m.group(1))
            else:
                found.add(m.group(1))

    return sorted(found - recorded), sorted(recorded)


def check_claims(spec: Path, registry: Path) -> int:
    inventory = json.loads((registry / "inventory.json").read_text())
    status = {d["id"]: d.get("status") for d in inventory.get("defect", [])}

    claims, recorded = claimed_defects(spec)
    if not claims and not recorded:
        print(f"REFUSING: {spec} names no defects, so this check measured nothing.")
        print("  An item with no defect claims does not need this gate; one whose")
        print("  claims could not be parsed does, and the two look identical from here.")
        return 1

    still_open = [d for d in claims if status.get(d) == "open"]
    # A `(recorded)` defect is not checked for being closed, but it must exist:
    # a finding an item states and never writes down is the drift one layer up.
    missing = [d for d in claims + recorded if d not in status]

    print(f"{spec.name}: claims {len(claims)} defect(s) — {', '.join(claims) or 'none'}")
    print(f"  registry: {registry}/inventory.json, {len(status)} defect record(s)")
    if recorded:
        print(f"  recorded rather than claimed, and not checked here: {', '.join(recorded)}")

    for d in missing:
        print(f"  UNKNOWN  {d} is claimed and has no row in the registry")
    for d in still_open:
        title = next((x.get("title", "") for x in inventory["defect"] if x["id"] == d), "")
        print(f"  OPEN     {d} still reads `open` — {title[:90]}")

    if still_open or missing:
        print()
        print(f"FAIL: {len(still_open) + len(missing)} claimed defect(s) the registry does not")
        print("      agree are closed. Flip the record with the evidence that closed it, or")
        print("      drop the claim from the spec. A merge that leaves them apart is how the")
        print("      registry came to report 23 open defects over a tree that had fixed most.")
        return 1

    print("\nPASS: every claimed defect reads `fixed`.")
    return 0


# --------------------------------------------------------------- dropped


def _git(*args: str) -> str:
    out = subprocess.run(["git", *args], capture_output=True, text=True)
    return out.stdout if out.returncode == 0 else ""


def _load(rev: str, path: str):
    out = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True, text=True)
    if out.returncode:
        return None
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        return None


def _index(doc) -> dict:
    """Every id-bearing record in a registry, whatever list it lives under."""
    if doc is None:
        return {}
    if isinstance(doc, list):
        return {r["id"]: r for r in doc if isinstance(r, dict) and "id" in r}
    out = {}
    for value in doc.values():
        if isinstance(value, list):
            for r in value:
                if isinstance(r, dict) and "id" in r:
                    out[r["id"]] = r
    return out


def check_dropped(registry: Path, repo: Path | None = None) -> int:
    repo = repo or Path.cwd()
    rel = []
    for name in ("inventory.json", "cases.json"):
        p = registry / name
        rel.append(str(p.relative_to(repo)) if p.is_absolute() else str(p))

    findings: list[str] = []
    examined = 0
    for path in rel:
        head = _index(_load("HEAD", path))
        if not head:
            print(f"  skipping {path}: no record at HEAD")
            continue
        # Newest first, and the first commit that mentions an id/field is the
        # one that decides it. Anything older has been superseded, so reading it
        # would report a merge's own value as "dropped" the moment somebody
        # restored what the merge lost — which is the shape the fixture in
        # test_instruments.py caught.
        commits = _git("rev-list", "--no-merges", "HEAD", "--", path).split()
        seen: set[tuple[str, str]] = set()
        for commit in commits:
            doc = _index(_load(commit, path))
            if not doc:
                continue
            parent = _git("rev-parse", f"{commit}^").strip()
            pdoc = _index(_load(parent, path)) if parent else {}
            for rid, record in doc.items():
                if rid not in head:
                    if (rid, "*") not in seen:
                        seen.add((rid, "*"))
                        findings.append(
                            f"{rid}: whole row present at {commit[:8]} and absent at HEAD")
                    continue
                for field in WATCHED:
                    if field not in record or (rid, field) in seen:
                        continue
                    examined += 1
                    seen.add((rid, field))
                    was = json.dumps(record[field], sort_keys=True)
                    now = json.dumps(head[rid].get(field), sort_keys=True)
                    before = json.dumps(pdoc.get(rid, {}).get(field), sort_keys=True)
                    # Set here, lost since, and HEAD holds what the parent held.
                    if was != now and now == before and before != was:
                        findings.append(
                            f"{rid}.{field}: set at {commit[:8]} and reverted to the value its "
                            f"parent held\n      lost: {was[:160]}\n      HEAD: {now[:160]}")

    print(f"registry drift: {len(rel)} file(s), {examined} id/field pair(s) examined")
    for f in findings:
        print(f"  DROPPED  {f}")
    if findings:
        print()
        print(f"FAIL: {len(findings)} value(s) an ancestor commit set and this tree no longer")
        print("      carries. Restore each from the commit that set it, or record why the")
        print("      later value is the right one. A merge keeping ours over a registry it")
        print("      did not read is how eleven of these were lost across four merges.")
        return 1
    print("\nPASS: every watched value an ancestor set is still here.")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2
    mode = argv[1]
    if mode == "claims":
        if len(argv) != 4:
            print("usage: defect_gate.py claims <spec.md> <registry-dir>")
            return 2
        return check_claims(Path(argv[2]), Path(argv[3]))
    if mode == "dropped":
        if len(argv) != 3:
            print("usage: defect_gate.py dropped <registry-dir>")
            return 2
        return check_dropped(Path(argv[2]))
    print(f"unknown mode {mode!r}; expected `claims` or `dropped`")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
