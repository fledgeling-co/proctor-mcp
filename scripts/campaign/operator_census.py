#!/usr/bin/env python3
"""Census every regular file under the operator's Proctor root. Read-only.

PRO-0099 gap-fix. The two census artifacts committed by the first pass were not a
pair from one run — they differed on `audit/audit.jsonl` while the README beside
them said the diff was empty. A census recorded only as a shell one-liner in a
README cannot be re-taken identically, so it is a script, and the pair either side
of a suite run comes from two invocations of this one.

    python3 scripts/campaign/operator_census.py before.tsv
    python3 scripts/campaign/operator_census.py after.tsv
    python3 scripts/campaign/operator_census.py --diff before.tsv after.tsv

Columns are `sha256 \\t size \\t mtime \\t path-relative-to-the-root`, sorted by
path, which is the format the first pass's artifacts already use.

It never creates, moves or removes anything under that root: REQ-055 forbids the
suite touching the operator's state, and an instrument that tidied up after it
would be the thing it is measuring.
"""
from __future__ import annotations

import hashlib
import os
import sys
from pathlib import Path

BUNDLE = "app.fledgeling.procter"


def root() -> Path:
    return Path.home() / "Library/Application Support" / BUNDLE


def census(base: Path) -> list[tuple[str, int, int, str]]:
    rows = []
    for dirpath, _, filenames in os.walk(base):
        for name in filenames:
            path = Path(dirpath) / name
            if not path.is_file() or path.is_symlink():
                continue
            try:
                data = path.read_bytes()
                stat = path.stat()
            except OSError:
                continue
            rows.append((hashlib.sha256(data).hexdigest(), stat.st_size,
                         int(stat.st_mtime), str(path.relative_to(base))))
    return sorted(rows, key=lambda r: r[3])


def read(path: Path) -> dict[str, tuple[str, int, int]]:
    out = {}
    for line in path.read_text().splitlines():
        digest, size, mtime, rel = line.split("\t", 3)
        out[rel] = (digest, int(size), int(mtime))
    return out


def main(argv: list[str]) -> int:
    if len(argv) == 4 and argv[1] == "--diff":
        before, after = read(Path(argv[2])), read(Path(argv[3]))
        names = sorted(set(before) | set(after))
        changed = [n for n in names if before.get(n) != after.get(n)]
        print(f"operator census: {len(changed)} changed / {len(before)} file(s) swept before, "
              f"{len(after)} after, under {root()}")
        for name in changed:
            print(f"  {name}: {before.get(name)} -> {after.get(name)}")
        return 1 if changed else 0
    if len(argv) != 2:
        print(__doc__)
        return 2
    base = root()
    if not base.is_dir():
        print(f"the operator's root is not there: {base}")
        return 2
    rows = census(base)
    Path(argv[1]).write_text(
        "".join(f"{d}\t{s}\t{m}\t{p}\n" for d, s, m, p in rows))
    print(f"operator census: {len(rows)} file(s) under {base} -> {argv[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
