#!/usr/bin/env python3
"""Arm PRO-0092's nine killing tests against the mutants they were written for.

A test written to kill a mutant nobody watched fail is the defect this whole item
is about, so each new test here is watched going red under the exact mutation
that survived PRO-0080's sample — at the site the extraction moved it to, which
is where a mutation table would find it now.

TWO THINGS ARE CHECKED BEFORE A VERDICT IS READ, and the second is the one that
was missing elsewhere. On PRO-0101 three mutations came back NOT ARMED against
checks that were working, and all three were the mutation's fault: a partial line
replacement, two regexes emitting a doubled backslash, and a scaffold whose
newlines broke the verdict parser. So this asserts the `before` text occurs
exactly once, and then re-reads the file and asserts the `after` text is present
and the `before` text is gone. A mutation that fails to apply is indistinguishable
from a check that cannot fail.

The tree is restored with `git checkout --` after every case and verified clean at
the end, and an `atexit` hook plus signal handlers close the window in which a
killed run leaves a live mutation behind — the same three rules `mutate_swift.py`
carries, for the same reason.

Usage:
    scripts/campaign/mutation_seam_arm.py [--out <path>] [--only <function>]
"""

from __future__ import annotations

import argparse
import atexit
import json
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# (case, survivor, file, before, after, swift function name, why it matters)
CASES = [
    ("CASE-0457", "1 · AXEngineImpl.swift:33",
     "Sources/ProctorAgent/AX/AXEngineImpl.swift",
     "guard includeWindowless || app.isRegular else { return nil }",
     "guard includeWindowless && app.isRegular else { return nil }",
     "listAppsHonoursIncludeWindowless",
     "the includeWindowless flag inverts meaning"),
    ("CASE-0458", "2 · Dispatch.swift:381",
     "Sources/ProctorAgent/Dispatch.swift",
     'args.bool("includeTiles", false)',
     'args.bool("includeTiles", true)',
     "dispatchDefaultsAgreeWithTheCatalogue",
     "every stability run compares pixel tiles nobody asked for"),
    ("CASE-0459", "8 · Dispatch.swift:394",
     "Sources/ProctorAgent/Dispatch.swift",
     'args.bool("presentation", true)',
     'args.bool("presentation", false)',
     "dispatchDefaultsAgreeWithTheCatalogue",
     "inspect stops returning presentation values it publishes by default"),
    ("CASE-0460", "4 · Session.swift:92",
     "Sources/ProctorAgent/Session/Session.swift",
     "var includeInvisible: Bool = false",
     "var includeInvisible: Bool = true",
     "snapshotOptionDefaultsMatchTheSchema",
     "an unasked-for snapshot carries zero-area and offscreen nodes"),
    ("CASE-0461", "10 · CGWindowCorrelation.swift:59",
     "Sources/ProctorAgent/AX/CGWindowCorrelation.swift",
     "return matches.count == 1 ? matches[0].number : nil",
     "return matches.count == 1 ? matches[1].number : nil",
     "correlateReturnsTheMatchingWindowsNumber",
     "the single fitting window resolves to a number that is not its own"),
    ("CASE-0462", "7 · SessionKill.swift:26",
     "Sources/ProctorAgent/Session/SessionKill.swift",
     "!candidates.contains(where: { $0.pid == pid }) else { return candidates }",
     "!candidates.contains(where: { $0.pid != pid }) else { return candidates }",
     "barePidIsSynthesisedExactlyOnce",
     "a bare pid stops being selectable while any other process runs"),
    ("CASE-0463", "9 · RunHUDPanel.swift:653",
     "Sources/ProctorAgent/Overlay/RunHUDPanel.swift",
     "override var canBecomeMain: Bool { false }",
     "override var canBecomeMain: Bool { true }",
     "hudPanelTakesKeyAndRefusesMain",
     "the HUD takes the main window from the app under test"),
    ("CASE-0464", "11 · RunHUDContentView.swift:97",
     "Sources/ProctorAgent/Overlay/RunHUDContentView.swift",
     "ink3: hex(17, 18, 21, 0.36), ink4: hex(17, 18, 21, 0.16),",
     "ink3: hex(18, 18, 21, 0.36), ink4: hex(17, 18, 21, 0.16),",
     "lightPaletteTonesShareOneBase",
     "one ink tone drifts off the palette's single graphite"),
    ("CASE-0465", "12 · TakeoverOverlay.swift:363",
     "Sources/ProctorAgent/Overlay/TakeoverOverlay.swift",
     "type == .tapDisabledByTimeout || type == .tapDisabledByUserInput",
     "type != .tapDisabledByTimeout || type == .tapDisabledByUserInput",
     "tapDisableNoticesAreTheOnlyDisableNotices",
     "every keystroke reads as macOS switching the tap off"),
    ("CASE-0466", "13 · AuditKeyStore.swift:47",
     "Sources/ProctorAgent/Session/AuditKeyStore.swift",
     'directory.appendingPathComponent("audit.pub", isDirectory: false)',
     'directory.appendingPathComponent("audit.pub", isDirectory: true)',
     "publicKeyURLNamesAFileThatRoundTrips",
     "the cached public key's URL claims to be a directory"),
]

_APPLIED: list[str] = []


def restore_all() -> None:
    while _APPLIED:
        rel = _APPLIED.pop()
        subprocess.run(["git", "checkout", "--", rel], cwd=ROOT, capture_output=True)


def _on_signal(signum, _frame):
    restore_all()
    print(f"\ninterrupted by signal {signum} — working tree restored", flush=True)
    raise SystemExit(130)


def tree_dirty() -> str:
    out = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT,
                         capture_output=True, text=True).stdout
    return "\n".join(l for l in out.splitlines() if not l[3:].strip().startswith("docs/")).strip()


def apply(rel: str, before: str, after: str) -> tuple[bool, str]:
    """Apply the mutation and prove it landed. (landed, why)."""
    path = ROOT / rel
    text = path.read_text()
    occurrences = text.count(before)
    if occurrences != 1:
        return False, f"the pre-mutation text occurs {occurrences} times, not once"
    path.write_text(text.replace(before, after))
    _APPLIED.append(rel)
    # Re-read rather than trusting the write, which is where PRO-0101's three
    # false NOT ARMED verdicts came from.
    reread = path.read_text()
    if after not in reread:
        return False, "the mutated text is not in the file after writing it"
    if before in reread:
        return False, "the pre-mutation text is still in the file"
    return True, "mutation landed, confirmed by re-reading the file"


def run_filtered(function: str, timeout: int) -> tuple[int, str]:
    try:
        p = subprocess.run(["./scripts/test.sh", "--filter", function], cwd=ROOT,
                           capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "timed out"
    out = p.stdout + p.stderr
    verdict = ""
    for line in out.splitlines():
        if re.search(r"Test run with \d+ test", line):
            verdict = line.strip()
    return p.returncode, verdict


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="docs/test-campaign/evidence/PRO-0092/seam-arming.json")
    ap.add_argument("--only")
    ap.add_argument("--timeout", type=int, default=1200)
    args = ap.parse_args()

    atexit.register(restore_all)
    signal.signal(signal.SIGTERM, _on_signal)
    signal.signal(signal.SIGINT, _on_signal)

    dirty = tree_dirty()
    if dirty:
        print("REFUSING: the working tree is not clean outside docs/, and this edits it in place.")
        print(dirty[:400])
        return 2

    rows, failures = [], 0
    for case, survivor, rel, before, after, function, why in CASES:
        if args.only and args.only != function:
            continue
        landed, how = apply(rel, before, after)
        if not landed:
            print(f"[{case}] NOT ARMED — {how}", flush=True)
            rows.append({"case": case, "survivor": survivor, "file": rel,
                         "function": function, "armed": False, "reason": how})
            failures += 1
            restore_all()
            continue
        started = time.time()
        code, verdict = run_filtered(function, args.timeout)
        elapsed = round(time.time() - started, 1)
        subprocess.run(["git", "checkout", "--", rel], cwd=ROOT, check=True, capture_output=True)
        if rel in _APPLIED:
            _APPLIED.remove(rel)
        armed = code != 0
        rows.append({
            "case": case, "survivor": survivor, "file": rel, "function": function,
            "mutation": f"{before}  ->  {after}", "mutationLanded": how,
            "armed": armed, "exit": code, "verdict": verdict, "seconds": elapsed,
            "why": why,
        })
        state = "ARMED" if armed else "NOT ARMED"
        print(f"[{case}] {state:<9} {function} exit {code} · {verdict} ({elapsed}s)", flush=True)
        if not armed:
            failures += 1
        Path(ROOT / args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(ROOT / args.out).write_text(json.dumps(
            {"summary": {"partial": True, "run": len(rows), "of": len(CASES),
                         "notArmed": failures}, "cases": rows}, indent=1) + "\n")

    still = tree_dirty()
    summary = {"run": len(rows), "armed": len(rows) - failures, "notArmed": failures,
               "treeCleanAfter": not still}
    Path(ROOT / args.out).write_text(json.dumps({"summary": summary, "cases": rows}, indent=1) + "\n")
    print()
    print(f"armed {len(rows) - failures} of {len(rows)} · tree clean after: {not still}")
    return 0 if failures == 0 and not still else 1


if __name__ == "__main__":
    raise SystemExit(main())
