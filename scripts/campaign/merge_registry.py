#!/usr/bin/env python3
"""Merge a multi-key JSON registry without dropping a key nobody was arguing about.

Reconciling `inventory.json` at the PRO-0081 merge, a hand-merge took ours as the
base document and merged only the two keys the conflict was about — `defect` and
`requirement`. `flow` was neither merged nor noticed, so FLOW-010 and its `shot`
left the published set, a judged capture stopped being published, and `judged`
fell 6 to 5 against a ratchet of 6. `capture-lineage.py --gate` exited 2 and named
it. Recorded as DEF-058.

The lesson is mechanical rather than a resolution to be more careful, so it is a
script: **a registry merge sweeps every key in the union of both documents**, and
asserts uniqueness per key on the way out.

WHAT THIS REFUSES TO DO, because each is how the original loss happened:

  - It never drops a row. Every row under every key of either document appears in
    the output. With no `--ancestor` a row present on one side only is an ADDITION
    on that side, never a deletion on the other — the safe direction, and the one
    the hand-merge inverted.
  - It never silently resolves a real conflict. Two rows sharing an id with
    different content stop the merge and are named. Picking ours is what turned a
    dropped key into a green merge.
  - It never reformats a key it did not touch. Rows are emitted in base order,
    then theirs-only rows appended in theirs order, so a diff of the result shows
    the additions and nothing else.

Ordering note: `--ancestor` turns a one-sided absence back into a deletion, which
is what you want when a merge genuinely removes a row. Without it, deletion is
unrepresentable — deliberately, since an unrepresentable deletion cannot be an
accidental one.

Usage:
    merge_registry.py --base ours.json --theirs theirs.json --out merged.json
    merge_registry.py --base ours.json --theirs theirs.json --ancestor base.json --out merged.json
    merge_registry.py --base ours.json --theirs theirs.json --verify merged.json

`--verify` is the gate half: it reads a merge somebody else performed and exits 1
naming every row of either input that the result does not carry. That is the check
that would have caught DEF-058 before the ratchet did.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# The field that identifies a row. Every key in these registries uses `id`; a
# registry that does not is refused rather than merged on position, because two
# lists merged on position is the other way to lose a row.
ID = "id"


def load(path: Path) -> dict[str, list[dict]]:
    doc = json.loads(path.read_text())
    if not isinstance(doc, dict):
        sys.exit(f"{path}: expected an object of key -> list of rows.")
    for key, rows in doc.items():
        if not isinstance(rows, list):
            sys.exit(f"{path}: key '{key}' is not a list.")
        for row in rows:
            if not isinstance(row, dict) or ID not in row:
                sys.exit(f"{path}: a row under '{key}' has no '{ID}' field, so it "
                         f"cannot be merged by identity.")
    return doc


def index(rows: list[dict]) -> dict[str, dict]:
    return {r[ID]: r for r in rows}


def assert_unique(doc: dict[str, list[dict]], label: str) -> None:
    """One uniqueness assertion per key, and it names the key rather than the file."""
    for key, rows in doc.items():
        seen: dict[str, int] = {}
        for r in rows:
            seen[r[ID]] = seen.get(r[ID], 0) + 1
        dupes = sorted(i for i, n in seen.items() if n > 1)
        if dupes:
            sys.exit(f"{label}: key '{key}' repeats {', '.join(dupes)}. A registry "
                     f"with two rows under one id has already lost one of them.")


def merge(base: dict[str, list[dict]],
          theirs: dict[str, list[dict]],
          ancestor: dict[str, list[dict]] | None
          ) -> tuple[dict[str, list[dict]], list[str], list[str]]:
    """Sweep the union of keys. Returns the merged document and a per-key report."""
    conflicts: list[str] = []
    report: list[str] = []
    merged: dict[str, list[dict]] = {}

    # The union, in a stable order: base's keys first in their own order, then any
    # key only theirs has. A key present only in theirs is the DEF-058 shape.
    keys = list(base.keys()) + [k for k in theirs if k not in base]

    for key in keys:
        base_rows = base.get(key, [])
        their_rows = theirs.get(key, [])
        anc = index(ancestor.get(key, [])) if ancestor is not None else None
        b, t = index(base_rows), index(their_rows)

        out: list[dict] = []
        for row in base_rows:
            rid = row[ID]
            if rid in t and t[rid] != row:
                if anc is not None and anc.get(rid) == row:
                    out.append(t[rid])      # only theirs changed it
                    continue
                if anc is not None and anc.get(rid) == t[rid]:
                    out.append(row)         # only ours changed it
                    continue
                conflicts.append(f"{key}/{rid}: present on both sides with different "
                                 f"content and no ancestor resolving it")
                out.append(row)
                continue
            out.append(row)

        added = [row for row in their_rows if row[ID] not in b]
        if anc is not None:
            # With an ancestor, a row theirs lacks that the ancestor had is a real
            # deletion; drop it and say so rather than resurrecting it.
            deleted = [r for r in out if r[ID] in anc and r[ID] not in t]
            if deleted:
                gone = {r[ID] for r in deleted}
                report.append(f"{key}: {len(deleted)} row(s) deleted by theirs "
                              f"({', '.join(sorted(gone))})")
                out = [r for r in out if r[ID] not in gone]
        out.extend(added)
        merged[key] = out
        report.append(f"{key}: base {len(base_rows)} + theirs-only {len(added)} "
                      f"= {len(out)}")

    return merged, conflicts, report


def missing_rows(base: dict[str, list[dict]],
                 theirs: dict[str, list[dict]],
                 result: dict[str, list[dict]]) -> list[str]:
    """Every row of either input the result does not carry, named by key and id."""
    lost: list[str] = []
    for key in list(base.keys()) + [k for k in theirs if k not in base]:
        have = {r[ID] for r in result.get(key, [])}
        for side, doc in (("ours", base), ("theirs", theirs)):
            for row in doc.get(key, []):
                if row[ID] not in have:
                    lost.append(f"{key}/{row[ID]} (from {side})")
    return lost


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", required=True, type=Path, help="ours")
    ap.add_argument("--theirs", required=True, type=Path)
    ap.add_argument("--ancestor", type=Path,
                    help="the merge base; without it a one-sided absence is an "
                         "addition, never a deletion")
    ap.add_argument("--out", type=Path, help="write the merged registry here")
    ap.add_argument("--verify", type=Path,
                    help="read a merge somebody else performed and name every row "
                         "it dropped")
    a = ap.parse_args()

    base, theirs = load(a.base), load(a.theirs)
    assert_unique(base, str(a.base))
    assert_unique(theirs, str(a.theirs))
    ancestor = load(a.ancestor) if a.ancestor else None

    if a.verify:
        result = load(a.verify)
        assert_unique(result, str(a.verify))
        lost = missing_rows(base, theirs, result)
        keys = set(base) | set(theirs)
        absent_keys = sorted(k for k in keys if k not in result)
        for k in absent_keys:
            print(f"  key '{k}' is absent from the merge entirely")
        for row in lost:
            print(f"  dropped: {row}")
        if lost or absent_keys:
            print(f"FAIL: {len(lost)} row(s) and {len(absent_keys)} key(s) present in "
                  f"an input and absent from {a.verify}. A registry merge sweeps "
                  f"every key.")
            return 1
        print(f"OK: every row under every one of {len(keys)} key(s) survives the merge "
              f"({sum(len(v) for v in result.values())} rows).")
        return 0

    merged, conflicts, report = merge(base, theirs, ancestor)
    for line in report:
        print(f"  {line}")
    if conflicts:
        for c in conflicts:
            print(f"  CONFLICT {c}")
        print(f"FAIL: {len(conflicts)} conflict(s). Resolve each by hand and re-run; "
              f"taking one side silently is how DEF-058 happened.")
        return 2
    assert_unique(merged, "merged")
    lost = missing_rows(base, theirs, merged)
    if lost and ancestor is None:
        for row in lost:
            print(f"  dropped: {row}")
        print("FAIL: the merge lost rows. This is a bug in this script.")
        return 3

    if a.out:
        a.out.write_text(json.dumps(merged, indent=2, ensure_ascii=False) + "\n")
        print(f"wrote {a.out}")
    else:
        print(json.dumps(merged, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
