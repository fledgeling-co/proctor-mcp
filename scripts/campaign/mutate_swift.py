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

A fourth verdict, TIMEOUT, and it is the one this file used to get wrong. A run
that reached the bound was scored KILLED, so a starved run reported a suite that
was catching faults it had never actually run against. PRO-0080's first
ProctorAgent sample carried two of those at exactly 600.0s under a load average
of 271: the reported rate was 79.2% and the honest one was 86.4%. A timeout is
now counted apart and left out of the survival-rate denominator, because it is
the absence of a measurement rather than a measurement, and the summary names
every scored mutant that came within 2% of the bound without reaching it.

A fifth, `inconclusive`, and it is the one that makes the other four mean
something. Every verdict here is a statement about a mutated tree, so the edit is
the measurement's first step and it used to go unwitnessed: `apply()` spliced by
byte offset and returned nothing, so a wrong-offset write was silent and the
harness graded pristine code without anything anywhere disagreeing. It now proves
the splice — the bytes at the recorded offsets must be the recorded `before`, and
the file re-read from disk must equal the spliced text exactly — and a mutant that
fails either is `inconclusive`, out of the survival-rate denominator with the
timeouts, because nothing was measured. DEF-207.

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


def apply(mutant: dict) -> tuple[bool, str]:
    """Splice the mutant in and prove it landed. (landed, why).

    DEF-207. THIS USED TO SPLICE BY BYTE OFFSET AND RETURN NOTHING, and that is
    the direction with no witness at all. An anchor-string mutator that aborts
    still reports INERT, so the log disagrees with the verdict; an unconditional
    offset splice writes regardless, so a wrong-offset write is silent and the
    harness grades pristine or wrongly-edited code with nothing anywhere
    contradicting it. A survivor then has two readings — the guard is decorative,
    or the mutation never happened — and the summary cannot tell them apart.

    Its sibling `mutation_seam_arm.py` already carried the check: assert the
    occurrence count, then re-read and require `after` present and `before` gone.
    The offset form of the same standard is stronger and is what runs here. The
    offsets came from `candidates()` reading this file, so between that read and
    this write the text may have moved:

      * before the write, the bytes at [start, end) must be exactly `before` —
        an offset that has drifted names something else and is refused;
      * after the write, the file re-read from disk must equal the spliced text
        exactly — not "contains `after`", which a file already holding that token
        elsewhere would satisfy while the splice went somewhere else entirely.

    A mutant that fails either is `inconclusive`, never a kill and never a
    survivor: nothing was measured, because the thing to measure was never made.
    """
    path = Path(mutant["file"])
    text = path.read_text()
    start, end = mutant["start"], mutant["end"]
    if not (0 <= start < end <= len(text)):
        return False, ("the recorded offsets %d-%d fall outside a file of %d characters"
                       % (start, end, len(text)))
    found = text[start:end]
    if found != mutant["before"]:
        return False, ("the text at offset %d-%d is %r, not the recorded %r — the file moved "
                       "under the offsets" % (start, end, found, mutant["before"]))
    expected = text[:start] + mutant["after"] + text[end:]
    _APPLIED.append(str(path))
    path.write_text(expected)
    reread = path.read_text()
    if reread != expected:
        return False, "the file re-read from disk is not the text that was written"
    return True, ("mutation landed at offset %d: %r -> %r, confirmed by re-reading the file"
                  % (start, mutant["before"], mutant["after"]))


def revert(mutant: dict) -> None:
    subprocess.run(["git", "checkout", "--", mutant["file"]], check=True,
                   capture_output=True)
    if mutant["file"] in _APPLIED:
        _APPLIED.remove(mutant["file"])


# How close to the bound an elapsed time has to be before the reader is told.
# 0.98 rather than equality because a run that is starved rather than failing does
# not always reach the bound exactly — PRO-0080's two both did, at 600.0s and
# 600.1s, but the next one need not.
NEAR_BOUND = 0.98


def score(passed: bool, why: str, elapsed: float, bound: int) -> tuple[str, bool]:
    """The verdict for one mutant, and whether it is close enough to the bound to
    be worth saying so.

    PRO-0092. THE RUNNER USED TO SCORE A TIMEOUT AS A KILL, and that is the
    direction that flatters the suite. Starvation can turn a survivor into a false
    kill; it can never turn a kill into a false survivor. Two of the five kills in
    the first ProctorAgent sample ran to exactly 600.0s under a load average that
    reached 271, and reading the summary alone there was no way to tell them from
    the three real ones — the honest rate was 86.4% and the reported one was 79.2%.

    A timeout is now its own verdict, counted apart and excluded from the
    survival-rate denominator, because it is the absence of a measurement rather
    than a measurement. `nearBound` marks a scored mutant that came close without
    reaching it, which is the shape a reader should look at twice.
    """
    if why == "build-failed":
        return "unbuildable", False
    if why == "timeout":
        return "TIMEOUT", True
    return ("SURVIVED" if passed else "killed"), elapsed >= bound * NEAR_BOUND


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
    killed = survived = unbuildable = timed_out = inconclusive = 0
    for i, m in enumerate(chosen, 1):
        short = Path(m["file"]).name
        landed, how = apply(m)
        if not landed:
            # The step could not be proved, so there is no outcome to grade. Not a
            # kill and not a survivor: `inconclusive`, naming why, and out of the
            # survival-rate denominator with the timeouts.
            restore_all()
            inconclusive += 1
            row = {**m, "verdict": "inconclusive", "why": "mutation-not-applied",
                   "mutationLanded": how, "seconds": 0.0, "nearBound": False,
                   "boundSeconds": args.timeout}
            results.append(row)
            print(f"[{i}/{len(chosen)}] {'inconclusive':<11} {short}:{m['line']} "
                  f"{m['before']} -> {m['after']}  — {how}", flush=True)
            Path(args.out).write_text(json.dumps(
                {"summary": {"partial": True, "run": i, "of": len(chosen),
                             "killed": killed, "survived": survived,
                             "unbuildable": unbuildable, "timedOut": timed_out,
                             "inconclusive": inconclusive},
                 "mutants": results}, indent=1) + "\n")
            continue
        started = time.time()
        passed, why = run_suite(args.timeout)
        revert(m)
        elapsed = round(time.time() - started, 1)
        verdict, near_bound = score(passed, why, elapsed, args.timeout)
        if verdict == "unbuildable":
            unbuildable += 1
        elif verdict == "TIMEOUT":
            timed_out += 1
        elif verdict == "SURVIVED":
            survived += 1
        else:
            killed += 1
        row = {**m, "verdict": verdict, "why": why, "mutationLanded": how,
               "seconds": elapsed, "nearBound": near_bound, "boundSeconds": args.timeout}
        results.append(row)
        near = f"  [at the {args.timeout}s bound]" if near_bound else ""
        print(f"[{i}/{len(chosen)}] {verdict:<11} {short}:{m['line']} "
              f"{m['before']} -> {m['after']}  ({elapsed}s){near}", flush=True)
        # Written every mutant rather than at the end, so a run that is killed
        # still reports what it scored. The first re-run was killed by a harness
        # timeout and left a zero-byte output file beside a mutated tree.
        Path(args.out).write_text(json.dumps(
            {"summary": {"partial": True, "run": i, "of": len(chosen),
                         "killed": killed, "survived": survived,
                         "unbuildable": unbuildable, "timedOut": timed_out,
                         "inconclusive": inconclusive},
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
        row = by_op.setdefault(key, {"killed": 0, "survived": 0, "unbuildable": 0,
                                     "timedOut": 0, "inconclusive": 0})
        row[{"killed": "killed", "SURVIVED": "survived",
             "unbuildable": "unbuildable", "TIMEOUT": "timedOut",
             "inconclusive": "inconclusive"}[r["verdict"]]] += 1

    still_dirty = "\n".join(
        line for line in subprocess.run(["git", "status", "--porcelain"],
                                        capture_output=True, text=True).stdout.splitlines()
        if line[3:].strip() != args.out).strip()
    scored = killed + survived
    summary = {
        "sites": len(pool), "run": len(chosen), "killed": killed, "survived": survived,
        "unbuildable": unbuildable, "timedOut": timed_out,
        "inconclusive": inconclusive, "scored": scored,
        "survivalRate": round(survived / scored, 4) if scored else None,
        "timeoutBoundSeconds": args.timeout,
        "nearBound": [f"{Path(r['file']).name}:{r['line']} {r['verdict']} at {r['seconds']}s"
                      for r in results if r["nearBound"]],
        "treeCleanAfter": not still_dirty,
        "targets": args.targets, "seed": args.seed, "byOperator": by_op,
        "baselineGreen": True,
    }
    Path(args.out).write_text(json.dumps({"summary": summary, "mutants": results},
                                         indent=1) + "\n")
    print()
    print(f"scored {scored} of {len(chosen)} run (of {len(pool)} sites) · "
          f"killed {killed} · SURVIVED {survived} · unbuildable {unbuildable} · "
          f"TIMEOUT {timed_out} · inconclusive {inconclusive}")
    if scored:
        print(f"survival rate {survived}/{scored} = {survived / scored:.1%} "
              f"— a survivor is a behaviour nothing is watching")
    if inconclusive:
        print(f"{inconclusive} mutant(s) could not be proved to have landed in the file and are "
              f"scored `inconclusive`, NOT in that denominator. The edit is the measurement's "
              f"first step, and a step that cannot be shown to have happened leaves no outcome "
              f"to grade — a survivor that was never applied reads exactly like a guard nothing "
              f"watches.")
        for r in results:
            if r["verdict"] == "inconclusive":
                print(f"  inconclusive: {Path(r['file']).name}:{r['line']} — {r['mutationLanded']}")
    if timed_out:
        print(f"{timed_out} mutant(s) reached the {args.timeout}s bound and are NOT in that "
              f"denominator. A timeout is the absence of a measurement, and scoring one as a "
              f"kill is the direction that flatters the suite.")
    near = [r for r in results if r["nearBound"] and r["verdict"] != "TIMEOUT"]
    for r in near:
        print(f"  near the bound: {Path(r['file']).name}:{r['line']} {r['verdict']} "
              f"at {r['seconds']}s of {args.timeout}s")
    print()
    for key in sorted(by_op, key=lambda k: -sum(by_op[k].values())):
        row = by_op[key]
        n = row["killed"] + row["survived"]
        rate = f"{row['survived'] / n:.0%}" if n else "n/a"
        print(f"  {key:<18} killed {row['killed']:>3}  survived {row['survived']:>3}  "
              f"unbuildable {row['unbuildable']:>3}  timeout {row['timedOut']:>3}  "
              f"inconclusive {row['inconclusive']:>3}  survival {rate}")
    print(f"tree clean after: {not still_dirty}")
    return 0 if not still_dirty else 3


if __name__ == "__main__":
    raise SystemExit(main())
