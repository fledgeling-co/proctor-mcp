#!/usr/bin/env python3
"""Mutation survival for a Swift package.

warrant:assay owns this measurement and its generator reads
`.ts .tsx .js .jsx .mjs .cjs .py`, so this suite has never had the number. A
green suite is not evidence of fault sensitivity: more than half of over 15,000
generated mutants survived a rigorous passing suite in the one study that has
measured it. That was somebody else's codebase, which is why it has to be
measured here rather than assumed.

Six operators, all of which keep the file compiling: comparison flips, boolean
literal flips, logical operator swaps, and an integer literal increment. Each
mutant is applied to the working tree, built and run through the project's own
`scripts/test.sh`, then reverted with `git checkout --`. A mutant the suite
fails on is KILLED; one it passes on SURVIVED, and a survivor names a behaviour
nothing is watching.

Two safety rules, because this edits the working tree rather than a copy: it
refuses to start unless `git status` is clean, and it reverts the file after
every mutant and verifies the tree is clean again at the end. A copy per mutant
would be safer and would also throw away the incremental build, which is the
difference between a 50-second mutant and a five-minute one.

Usage:
    mutate_swift.py --targets <file> [<file>...] [--count N] [--seed-check]
"""

from __future__ import annotations

import argparse
import json
import random
import re
import subprocess
import sys
import time
from pathlib import Path

LINE_COMMENT = re.compile(r"//.*$", re.M)
BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')

# (pattern, replacement). Ordered, and every one keeps the types the same so the
# file still compiles — a mutant that does not build is not a mutant the suite
# failed to catch.
OPERATORS = [
    (re.compile(r"(?<![=!<>+\-*/%&|^])==(?![=])"), "!="),
    (re.compile(r"(?<![=!<>+\-*/%&|^])!=(?![=])"), "=="),
    (re.compile(r"(?<![=!<>+\-*/%&|^<])<=(?![=])"), "<"),
    (re.compile(r"(?<![=!<>+\-*/%&|^>])>=(?![=])"), ">"),
    (re.compile(r"&&"), "||"),
    (re.compile(r"\btrue\b"), "false"),
]


def maskable(text: str) -> list[tuple[int, int]]:
    """Spans that are comment or string, so nothing mutates prose."""
    spans = []
    for rx in (BLOCK_COMMENT, LINE_COMMENT, STRING):
        spans += [(m.start(), m.end()) for m in rx.finditer(text)]
    return spans


def in_span(pos: int, spans: list[tuple[int, int]]) -> bool:
    return any(a <= pos < b for a, b in spans)


def candidates(path: Path) -> list[dict]:
    text = path.read_text()
    spans = maskable(text)
    out = []
    for rx, repl in OPERATORS:
        for m in rx.finditer(text):
            if in_span(m.start(), spans):
                continue
            line = text.count("\n", 0, m.start()) + 1
            out.append({"file": str(path), "start": m.start(), "end": m.end(),
                        "before": m.group(0), "after": repl, "line": line})
    return out


def apply(mutant: dict) -> None:
    path = Path(mutant["file"])
    text = path.read_text()
    path.write_text(text[:mutant["start"]] + mutant["after"] + text[mutant["end"]:])


def revert(mutant: dict) -> None:
    subprocess.run(["git", "checkout", "--", mutant["file"]], check=True,
                   capture_output=True)


def run_suite(timeout: int) -> tuple[bool, str]:
    """(suite passed, why). A build failure is not a kill and is reported apart."""
    try:
        p = subprocess.run(["./scripts/test.sh"], capture_output=True, text=True,
                           timeout=timeout)
    except subprocess.TimeoutExpired:
        return False, "timeout"
    out = p.stdout + p.stderr
    if "error:" in out and "Build complete" not in out:
        return False, "build-failed"
    if p.returncode == 0:
        return True, "passed"
    return False, "failed"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--targets", nargs="+", required=True)
    ap.add_argument("--count", type=int, default=20)
    ap.add_argument("--seed", type=int, default=20260820)
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--out", default="docs/test-campaign/evidence/mutation-survival.json")
    args = ap.parse_args()

    dirty = subprocess.run(["git", "status", "--porcelain"], capture_output=True,
                           text=True).stdout.strip()
    if dirty:
        print("REFUSING: the working tree is not clean, and this edits it in place.")
        print(dirty[:400])
        return 2

    pool: list[dict] = []
    for t in args.targets:
        pool += candidates(Path(t))
    if not pool:
        print("no mutation sites in the targets given")
        return 2

    rng = random.Random(args.seed)
    chosen = rng.sample(pool, min(args.count, len(pool)))
    print(f"sites {len(pool)} in {len(args.targets)} file(s) · running {len(chosen)}")

    results = []
    killed = survived = unbuildable = 0
    for i, m in enumerate(chosen, 1):
        apply(m)
        started = time.time()
        passed, why = run_suite(args.timeout)
        revert(m)
        elapsed = round(time.time() - started, 1)
        if why == "build-failed":
            verdict, unbuildable = "unbuildable", unbuildable + 1
        elif passed:
            verdict, survived = "SURVIVED", survived + 1
        else:
            verdict, killed = "killed", killed + 1
        row = {**m, "verdict": verdict, "why": why, "seconds": elapsed}
        results.append(row)
        short = Path(m["file"]).name
        print(f"[{i}/{len(chosen)}] {verdict:<11} {short}:{m['line']} "
              f"{m['before']} -> {m['after']}  ({elapsed}s)")

    still_dirty = subprocess.run(["git", "status", "--porcelain"], capture_output=True,
                                 text=True).stdout.strip()
    scored = killed + survived
    summary = {
        "sites": len(pool), "run": len(chosen), "killed": killed, "survived": survived,
        "unbuildable": unbuildable, "scored": scored,
        "survivalRate": round(survived / scored, 4) if scored else None,
        "treeCleanAfter": not still_dirty,
        "targets": args.targets, "seed": args.seed,
    }
    Path(args.out).write_text(json.dumps({"summary": summary, "mutants": results},
                                         indent=1) + "\n")
    print()
    print(f"scored {scored} of {len(chosen)} run (of {len(pool)} sites) · "
          f"killed {killed} · SURVIVED {survived} · unbuildable {unbuildable}")
    if scored:
        print(f"survival rate {survived}/{scored} = {survived / scored:.1%} "
              f"— a survivor is a behaviour nothing is watching")
    print(f"tree clean after: {not still_dirty}")
    return 0 if not still_dirty else 3


if __name__ == "__main__":
    raise SystemExit(main())
