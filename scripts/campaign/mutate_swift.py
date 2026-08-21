#!/usr/bin/env python3
"""Mutation survival for a Swift package.

warrant:assay owns this measurement and its generator reads
`.ts .tsx .js .jsx .mjs .cjs .py`, so this suite has never had the number. A
green suite is not evidence of fault sensitivity: more than half of over 15,000
generated mutants survived a rigorous passing suite in the one study that has
measured it. That was somebody else's codebase, which is why it has to be
measured here rather than assumed.

Eleven operators, and they are meant to keep the file compiling: comparison
flips in both directions, boundary shifts, logical operator swaps both ways,
boolean literal flips both ways, and an integer literal increment. Each mutant
is applied to the working tree, built and run through the project's own
`scripts/test.sh`, then reverted with `git checkout --`. A mutant the suite
fails on is KILLED; one it passes on SURVIVED, and a survivor names a behaviour
nothing is watching. One that will not build is neither, and is counted apart:
a mutant the compiler rejected is not a fault the tests failed to catch.

The count is stated here because the first version of this file said six and
listed an integer literal increment it did not implement. A docstring that
describes a table it does not read is a second source, which is the defect this
repo's whole provenance thesis exists to prevent, arriving in the tool built to
find it.

**A baseline run comes first, and a red baseline stops the run.** Without it a
suite that was already failing reports every mutant as KILLED and returns a 0%
survival rate that means nothing — the one number in this file that looks best
when it is worthless. It also catches the subtler case that produced the rule:
this compiles the whole package on every mutant, so it picks up whatever else is
in the working directory, and a run in flight while somebody edits elsewhere is
measuring a tree nobody chose.

Three safety rules, because this edits the working tree rather than a copy. It
refuses to start unless `git status` is clean; it reverts the file after every
mutant and verifies the tree is clean again at the end; and it reverts on the
way out however it leaves, including SIGTERM and SIGINT.

The third exists because the second was not enough. A run killed by a harness
timeout died between applying a mutant and reverting it, and left the tree
carrying a live mutation with nothing saying so — a suite that then went red for
a reason nobody could see. `atexit` plus signal handlers close it, and stdout is
line-buffered so a killed run still leaves the mutants it had already scored.

A copy per mutant would avoid all of this and would also throw away the
incremental build, which is the difference between a 15-second mutant and a
five-minute one.

Usage:
    mutate_swift.py --targets <file> [<file>...] [--count N] [--seed-check]
"""

from __future__ import annotations

import argparse
import atexit
import json
import random
import re
import signal
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
    # The boundary in the other direction. Off-by-one at a bound is the fault
    # class a `<=`-only table cannot produce.
    (re.compile(r"(?<=\s)<(?=\s)"), "<="),
    (re.compile(r"(?<=\s)>(?=\s)"), ">="),
    (re.compile(r"&&"), "||"),
    (re.compile(r"\|\|"), "&&"),
    (re.compile(r"\btrue\b"), "false"),
    (re.compile(r"\bfalse\b"), "true"),
    # An integer literal, one higher. Underscore separators are part of the
    # token, so `86_400` mutates as a whole rather than the `86` inside it, and
    # a decimal point on either side excludes a float's halves.
    #
    # `$` is in the lookbehind because Swift's closure shorthand parameters are
    # spelled `$0`, `$1`, and the digit in one is not an integer literal. Mutant
    # 24 of the first ProctorAgent sample rewrote `{ bind(fd, $0, size) }` to
    # `bind(fd, $1, size)` — a closure that takes one parameter cannot name a
    # second, so the compiler must reject it. That cost a slot out of 24 against
    # a pool of 3,189 sites, and it did not even score as unbuildable: under load
    # the build ran past the 600s timeout and the runner scores a timeout as a
    # kill. Recorded as DEF-032. A property wrapper's projected value (`$name`)
    # is excluded by the same lookbehind and is not a literal either.
    (re.compile(r"(?<![\w.$])(\d[\d_]*)(?![\w.])"), None),
]

def bump(match: re.Match) -> str:
    """`N` -> `N + 1`, keeping any underscore grouping the source used."""
    raw = match.group(1)
    value = int(raw.replace("_", "")) + 1
    if "_" not in raw:
        return str(value)
    # Regroup in threes from the right, which is what this codebase writes.
    text = str(value)
    parts = []
    while len(text) > 3:
        parts.insert(0, text[-3:])
        text = text[:-3]
    parts.insert(0, text)
    return "_".join(parts)


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
            after = bump(m) if repl is None else repl
            if after == m.group(0):
                continue
            line = text.count("\n", 0, m.start()) + 1
            out.append({"file": str(path), "start": m.start(), "end": m.end(),
                        "before": m.group(0), "after": after, "line": line})
    return out


# What is currently mutated, so the exit hook knows what to put back. One entry
# at a time by construction, and a list rather than a scalar so a future
# multi-file mutant does not silently leak.
_APPLIED: list[str] = []


def restore_all() -> None:
    """Put every applied mutation back. Safe to call twice."""
    while _APPLIED:
        path = _APPLIED.pop()
        subprocess.run(["git", "checkout", "--", path], capture_output=True)


def _on_signal(signum, _frame):
    restore_all()
    print(f"\ninterrupted by signal {signum} — working tree restored", flush=True)
    raise SystemExit(130)


def apply(mutant: dict) -> None:
    path = Path(mutant["file"])
    text = path.read_text()
    _APPLIED.append(str(path))
    path.write_text(text[:mutant["start"]] + mutant["after"] + text[mutant["end"]:])


def revert(mutant: dict) -> None:
    subprocess.run(["git", "checkout", "--", mutant["file"]], check=True,
                   capture_output=True)
    if mutant["file"] in _APPLIED:
        _APPLIED.remove(mutant["file"])


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

    # Registered before the first mutation, so there is no window in which one is
    # applied and nothing is watching for the exit.
    atexit.register(restore_all)
    signal.signal(signal.SIGTERM, _on_signal)
    signal.signal(signal.SIGINT, _on_signal)

    dirty = subprocess.run(["git", "status", "--porcelain"], capture_output=True,
                           text=True).stdout.strip()
    if dirty:
        print("REFUSING: the working tree is not clean, and this edits it in place.")
        print(dirty[:400])
        return 2

    print("baseline: running the suite once before mutating anything…", flush=True)
    base_passed, base_why = run_suite(args.timeout)
    if not base_passed:
        print(f"REFUSING: the suite does not pass before any mutation ({base_why}).")
        print("Every mutant would report as killed and the survival rate would be 0% "
              "for the wrong reason.")
        return 2
    print("baseline: green", flush=True)

    pool: list[dict] = []
    for t in args.targets:
        pool += candidates(Path(t))
    if not pool:
        print("no mutation sites in the targets given")
        return 2

    rng = random.Random(args.seed)
    chosen = rng.sample(pool, min(args.count, len(pool)))
    print(f"sites {len(pool)} in {len(args.targets)} file(s) · running {len(chosen)}",
          flush=True)

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
              f"{m['before']} -> {m['after']}  ({elapsed}s)", flush=True)
        # Written every mutant rather than at the end, so a run that is killed
        # still reports what it scored. The first re-run was killed by a harness
        # timeout and left a zero-byte output file beside a mutated tree.
        Path(args.out).write_text(json.dumps(
            {"summary": {"partial": True, "run": i, "of": len(chosen),
                         "killed": killed, "survived": survived,
                         "unbuildable": unbuildable},
             "mutants": results}, indent=1) + "\n")

    # Its own artifact does not count as an unrestored mutation. Without this the
    # check reports "tree clean after: False" on every run that writes into the
    # repo, and a safety signal that cries wolf on every run is one nobody reads.
    # Per operator, because a headline rate over a pool that is 45% integer
    # literals says more about literal coverage than about the suite. A reader
    # can see which class the survivors came from.
    by_op: dict[str, dict[str, int]] = {}
    for r in results:
        key = ("int-literal" if r["before"].replace("_", "").isdigit()
               else f"{r['before']} -> {r['after']}")
        row = by_op.setdefault(key, {"killed": 0, "survived": 0, "unbuildable": 0})
        row[{"killed": "killed", "SURVIVED": "survived",
             "unbuildable": "unbuildable"}[r["verdict"]]] += 1

    still_dirty = "\n".join(
        line for line in subprocess.run(["git", "status", "--porcelain"],
                                        capture_output=True, text=True).stdout.splitlines()
        if line[3:].strip() != args.out).strip()
    scored = killed + survived
    summary = {
        "sites": len(pool), "run": len(chosen), "killed": killed, "survived": survived,
        "unbuildable": unbuildable, "scored": scored,
        "survivalRate": round(survived / scored, 4) if scored else None,
        "treeCleanAfter": not still_dirty,
        "targets": args.targets, "seed": args.seed, "byOperator": by_op,
        "baselineGreen": True,
    }
    Path(args.out).write_text(json.dumps({"summary": summary, "mutants": results},
                                         indent=1) + "\n")
    print()
    print(f"scored {scored} of {len(chosen)} run (of {len(pool)} sites) · "
          f"killed {killed} · SURVIVED {survived} · unbuildable {unbuildable}")
    if scored:
        print(f"survival rate {survived}/{scored} = {survived / scored:.1%} "
              f"— a survivor is a behaviour nothing is watching")
    print()
    for key in sorted(by_op, key=lambda k: -sum(by_op[k].values())):
        row = by_op[key]
        n = row["killed"] + row["survived"]
        rate = f"{row['survived'] / n:.0%}" if n else "n/a"
        print(f"  {key:<18} killed {row['killed']:>3}  survived {row['survived']:>3}  "
              f"unbuildable {row['unbuildable']:>3}  survival {rate}")
    print(f"tree clean after: {not still_dirty}")
    return 0 if not still_dirty else 3


if __name__ == "__main__":
    raise SystemExit(main())
