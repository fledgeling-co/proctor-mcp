#!/usr/bin/env python3
"""Where this repository keeps its captures, and what is in there.

An external audit over this tree reported `R4: no capture directory found;
capture identity unchecked`. Nothing was wrong with the captures — the probe
looks for `evidence/`, `shots/`, `docs/evidence/` and three more conventional
names at the repository root, and this repository keeps them under
`docs/test-campaign/evidence/shots`. So a probe that would have found forty-six
images found none, and an unrunnable probe reported itself as unrun, which is
the correct behaviour and still leaves the question unanswered.

The fix is to stop making the location a guess. `captureRoots` in
`campaign.json` declares it, and this index makes the population explicit:
every image under every declared root, with its digest and size, and the
duplicate-digest groups named.

**What this does not do.** It does not decide what a picture depicts. That is
`shot_disposition.py`'s job, it was done by opening all thirty-five files and
looking at them, and a second opinion here would drift from it silently. This
index carries the pointer and the exact measurements; the reading stays where it
was made.

  capture_manifest.py [--campaign DIR] [--write] [--gate]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IMAGE = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".tiff")

# The names an external probe tries at the repository root. Recorded here so the
# report can say which of them exist, rather than only that this repo's own root
# does — the difference between "found nothing" and "looked somewhere else".
CONVENTIONAL = ("evidence", "docs/evidence", "shots", "docs/shots",
                "campaign", "docs/campaign")


def digest(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--campaign", type=Path, default=ROOT / "docs" / "test-campaign")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--gate", action="store_true")
    a = ap.parse_args()

    cfg_path = a.campaign / "campaign.json"
    cfg = json.loads(cfg_path.read_text())
    roots = cfg.get("captureRoots")
    if not roots:
        print(f"`captureRoots` is not declared in {cfg_path}. Without it the store's location "
              f"is a guess, which is the finding this index exists to close.", file=sys.stderr)
        return 2

    index_path = a.campaign / "capture-index.json"
    entries, missing_roots, by_hash = [], [], defaultdict(list)

    for rel in roots:
        root = ROOT / rel
        if not root.is_dir():
            missing_roots.append(rel)
            continue
        for f in sorted(root.rglob("*")):
            if not f.is_file() or f.suffix.lower() not in IMAGE:
                continue
            h = digest(f)
            r = str(f.relative_to(ROOT))
            by_hash[h].append(r)
            entries.append({"path": r, "sha256": h, "bytes": f.stat().st_size,
                            "root": rel})

    dupes = {h: p for h, p in by_hash.items() if len(p) > 1}

    # Which conventional names exist, so a reader can see why an external probe
    # looking for them came back empty rather than guessing at the reason.
    conventional_present = [c for c in CONVENTIONAL if (ROOT / c).is_dir()]

    index = {
        "note": ("Where this repository keeps its captures, declared so an audit does not have "
                 "to guess. What each picture DEPICTS is not decided here — see "
                 "scripts/campaign/shot_disposition.py, which was written by opening every "
                 "file and looking at it."),
        "declaredRoots": roots,
        "rootsMissing": missing_roots,
        "conventionalRootsPresentAtRepoRoot": conventional_present,
        "images": len(entries),
        "distinctImages": len(by_hash),
        "duplicateGroups": [{"sha256": h, "paths": p} for h, p in sorted(dupes.items())],
        "dispositionRecord": "scripts/campaign/shot_disposition.py",
        "entries": entries,
    }

    print(f"{len(entries)} image(s) under {len(roots) - len(missing_roots)} declared root(s), "
          f"{len(by_hash)} distinct")
    for rel in roots:
        n = sum(1 for e in entries if e["root"] == rel)
        print(f"  {rel:<44} {n:>4} image(s)"
              + ("   MISSING — not checked, rather than clean" if rel in missing_roots else ""))
    if not conventional_present:
        print(f"\nNone of the {len(CONVENTIONAL)} conventional root names exists here "
              f"({', '.join(CONVENTIONAL)}), which is why an audit looking for them found "
              f"no capture directory. `captureRoots` above is the answer to that.")
    if dupes:
        print(f"\n{len(dupes)} digest(s) held by more than one path — identity, not disposition; "
              f"whether a share is legitimate is capture-lineage.py's call:")
        for h, p in sorted(dupes.items())[:6]:
            print(f"  {h[:12]}  {len(p)} paths: {', '.join(x.split('/')[-1] for x in p[:4])}")

    if a.write:
        index_path.write_text(json.dumps(index, indent=2) + "\n")
        print(f"\nwrote {index_path}")

    if a.gate:
        if missing_roots:
            print(f"\nFAIL  {len(missing_roots)} declared capture root(s) do not exist: "
                  f"{', '.join(missing_roots)} — a probe over an absent directory is not "
                  f"checked, and reporting it clean is the failure this closes.")
            return 1
        if not index_path.is_file():
            print(f"\nFAIL  no index at {index_path}. Build it with --write; an absent index "
                  f"cannot say whether the directory moved under it.")
            return 1
        on_disk = {e["path"]: e["sha256"] for e in entries}
        stored = {e["path"]: e["sha256"] for e in json.loads(index_path.read_text())["entries"]}
        added = sorted(set(on_disk) - set(stored))
        gone = sorted(set(stored) - set(on_disk))
        moved = sorted(p for p in set(on_disk) & set(stored) if on_disk[p] != stored[p])
        if added or gone or moved:
            for p in added[:6]:
                print(f"FAIL  {p} is on disk and not in the index")
            for p in gone[:6]:
                print(f"FAIL  {p} is in the index and not on disk")
            for p in moved[:6]:
                print(f"FAIL  {p} changed bytes under an index written for the old ones")
            print(f"\n{len(added)} added · {len(gone)} gone · {len(moved)} changed. Re-run with "
                  f"--write once somebody has decided the new content is the standard — "
                  f"adopting it here would make the index agree with whatever is on disk.")
            return 1
        print(f"\ngate: {len(entries)} image(s) across {len(roots)} declared root(s), "
              f"all present and unchanged.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
