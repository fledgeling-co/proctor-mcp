#!/usr/bin/env python3
"""Prove the mutation runner reports a timeout where it used to report a kill.

A change to an instrument that cannot be shown to report differently has measured
nothing, so this drives the same forced timeout through the runner on disk and
through the runner as it was before the change, and reads both verdicts back.

Two passes, and the second is the one that matters:

1. The scoring decision alone. `score(passed, why, elapsed, bound)` is called with
   a timeout, a survivor, a kill and a build failure, and the old expression —
   reproduced verbatim from the pre-change file — is called with the same inputs.
   The contrast is the point: both say `killed` for a genuine failure and they
   disagree on the timeout.

2. The whole runner, end to end. `main()` is called with its suite runner replaced
   by one that returns green for the baseline and a timeout for the mutant, so a
   real mutation is applied to a real tracked file, reverted, and written into a
   real JSON summary. The pre-change module is driven the same way from the same
   fixture, and its summary says `killed` with a survival rate computed over a
   denominator that includes it.

The tree is restored by the runner's own `atexit` and signal handlers, and this
checks `git status` before and after rather than trusting them.

Usage:
    scripts/campaign/mutation_timeout_arm.py [--out <path>]
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "scripts/campaign/mutate_swift.py"

# The pre-change scoring expression, copied from `mutate_swift.py` at the commit
# before this one rather than paraphrased. If this stops matching the file git
# holds, the arming is comparing against something nobody shipped.
# The commit before `fix(PRO-0092): the mutation runner scores a timeout apart
# from a kill`. Pinned rather than named by branch: a branch that will one day
# contain the change cannot hold the state before it. DEF-242.
BASELINE_REF = "fc1b9a4~1"

OLD_SOURCE_MARKER = 'if why == "build-failed":\n            verdict, unbuildable = "unbuildable", unbuildable + 1'


def old_score(passed: bool, why: str) -> str:
    """What the runner did before PRO-0092, in its own shape."""
    if why == "build-failed":
        return "unbuildable"
    if passed:
        return "SURVIVED"
    return "killed"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def tree_dirty() -> str:
    out = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT,
                         capture_output=True, text=True).stdout
    return "\n".join(l for l in out.splitlines() if not l[3:].strip().startswith("docs/")).strip()


def drive(module, target: str, out_path: Path) -> dict:
    """Run `main()` with the suite runner replaced. Green baseline, then a timeout."""
    calls = {"n": 0}

    def fake_run_suite(_timeout: int):
        calls["n"] += 1
        return (True, "passed") if calls["n"] == 1 else (False, "timeout")

    module.run_suite = fake_run_suite
    argv = sys.argv
    sys.argv = ["mutate_swift.py", "--targets", target, "--count", "1",
                "--seed", "20260823", "--timeout", "600", "--out", str(out_path)]
    try:
        code = module.main()
    finally:
        sys.argv = argv
    return {"exit": code, "report": json.loads(out_path.read_text())}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="docs/test-campaign/evidence/PRO-0092/timeout-arming.json")
    ap.add_argument("--target", default="Sources/ProctorAgent/RunIdentity.swift")
    # DEF-242. The default was `main`, and `main` absorbed PRO-0092's fix the
    # moment it merged — so this gate has compared the repaired runner against
    # itself ever since, printing `before=TIMEOUT after=TIMEOUT` and exiting 1 on
    # a clean `main` tree. The failure was loud rather than silent, because
    # OLD_SOURCE_MARKER stopped matching too, and nobody read it: this gate was
    # not in the per-merge list. A baseline ref that moves is not a baseline. It
    # is pinned to the commit before the change it measures, which is the only
    # tree that can be the before-state.
    ap.add_argument("--baseline-ref", default=BASELINE_REF,
                    help="the ref holding the runner as it was before this change")
    args = ap.parse_args()

    # Resolved first, because it is a question about the repository's history
    # rather than about the working tree, and a gate that refuses for the wrong
    # reason sends the reader to the wrong place.
    shown = subprocess.run(
        ["git", "show", f"{args.baseline_ref}:scripts/campaign/mutate_swift.py"],
        cwd=ROOT, capture_output=True, text=True)
    if shown.returncode != 0 or not shown.stdout:
        print(f"REFUSING: {args.baseline_ref} does not resolve in this checkout "
              f"({shown.stderr.strip()[:160] or 'no output'}). This gate compares the runner "
              f"against the tree before the change, and a shallow clone does not carry it — "
              f"fetch that commit or pass --baseline-ref.")
        return 2

    dirty = tree_dirty()
    if dirty:
        print("REFUSING: the working tree is not clean outside docs/.")
        print(dirty[:400])
        return 2

    new = load(RUNNER, "mutate_swift_new")

    # Pass 1 — the decision alone.
    inputs = [
        ("a timeout", False, "timeout", 600.0),
        ("a genuine failure", False, "failed", 31.4),
        ("a survivor", True, "passed", 22.9),
        ("a build failure", False, "build-failed", 8.1),
        ("a kill that came close", False, "failed", 594.0),
    ]
    decisions = []
    for label, passed, why, elapsed in inputs:
        verdict, near = new.score(passed, why, elapsed, 600)
        decisions.append({"input": label, "why": why, "seconds": elapsed,
                          "before": old_score(passed, why), "after": verdict,
                          "nearBound": near})
        print(f"  {label:<22} before={old_score(passed, why):<11} after={verdict:<11} "
              f"nearBound={near}")

    timeout_row = decisions[0]
    decision_armed = timeout_row["before"] == "killed" and timeout_row["after"] == "TIMEOUT"
    failure_row = decisions[1]
    unchanged = failure_row["before"] == failure_row["after"] == "killed"

    # Pass 2 — the whole runner, both versions, from the same fixture.
    with tempfile.TemporaryDirectory() as tmp:
        old_path = Path(tmp) / "mutate_swift_old.py"
        # Resolved above, before the tree check. Out-of-family review, PRO-0106:
        # a pinned sha does not exist in a shallow clone, and `git show` failing
        # silently would leave an empty baseline that armed nothing while
        # reporting a comparison.
        old_source = shown.stdout
        marker_present = OLD_SOURCE_MARKER in old_source
        old_path.write_text(old_source)
        old = load(old_path, "mutate_swift_old")

        new_report = drive(new, args.target, Path(tmp) / "new.json")
        old_report = drive(old, args.target, Path(tmp) / "old.json")

    new_mutant = new_report["report"]["mutants"][0]
    old_mutant = old_report["report"]["mutants"][0]
    new_summary = new_report["report"]["summary"]
    old_summary = old_report["report"]["summary"]
    end_to_end_armed = (old_mutant["verdict"] == "killed"
                        and new_mutant["verdict"] == "TIMEOUT"
                        and new_summary.get("survivalRate") is None
                        and old_summary.get("survivalRate") == 0.0)

    print()
    print(f"  end to end · before: verdict={old_mutant['verdict']} "
          f"scored={old_summary['scored']} survivalRate={old_summary.get('survivalRate')}")
    print(f"  end to end · after:  verdict={new_mutant['verdict']} "
          f"scored={new_summary['scored']} timedOut={new_summary['timedOut']} "
          f"survivalRate={new_summary.get('survivalRate')}")

    still = tree_dirty()
    armed = decision_armed and unchanged and end_to_end_armed and marker_present and not still
    report = {
        "summary": {
            "armed": armed,
            "decisionArmed": decision_armed,
            "genuineFailureUnchanged": unchanged,
            "endToEndArmed": end_to_end_armed,
            "preChangeSourceMatched": marker_present,
            "baselineRef": args.baseline_ref,
            "treeCleanAfter": not still,
            "target": args.target,
        },
        "decisions": decisions,
        "endToEnd": {
            "before": {"verdict": old_mutant["verdict"], "seconds": old_mutant["seconds"],
                       "summary": old_summary},
            "after": {"verdict": new_mutant["verdict"], "seconds": new_mutant["seconds"],
                      "nearBound": new_mutant["nearBound"], "summary": new_summary},
        },
    }
    out = ROOT / args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=1) + "\n")
    print()
    print(f"armed: {armed} · tree clean after: {not still}")
    return 0 if armed else 1


if __name__ == "__main__":
    raise SystemExit(main())
