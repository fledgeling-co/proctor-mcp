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

THE VERDICT IS READ FROM THE OUTPUT RATHER THAN FROM THE EXIT CODE, which is
DEF-208. The rule used to be `armed = code != 0`, and a non-zero exit is not a
test result: a process dying in setup, a `--filter` matching nothing, and a check
firing all produce one. CASE-0461's trapping mutant gave signal 5, **zero verdict
lines** and the suite's own `FAIL: no swift-testing verdict line`, and it scored
ARMED for a reason the rule could not see. It is armed — the log shows the named
test running when the process died — so the repair is to make the rule able to
tell, not to weaken the verdict. A trapping mutant now needs a
`Test "<display>" started.` line with no completion beside it, and that display
string is read out of the Swift source rather than hand-copied here. Anything
that satisfies neither route is `inconclusive` naming why, and exits 3 rather
than 1 so a thing nobody measured is not filed with a thing that failed.

The tree is restored with `git checkout --` after every case and verified clean at
the end, and an `atexit` hook plus signal handlers close the window in which a
killed run leaves a live mutation behind — the same three rules `mutate_swift.py`
carries, for the same reason.

Usage:
    scripts/campaign/mutation_seam_arm.py [--out <path>] [--only <function>]

Exit 0 every case armed · 1 a case did not arm, or the tree is dirty afterwards ·
3 nothing failed and something could not be measured.
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
    ("CASE-0470", "2 · Dispatch.swift:381, at runtime",
     "Sources/ProctorAgent/Dispatch.swift",
     'includeTiles = args.bool("includeTiles", false)',
     'includeTiles = args.bool("includeTiles", true)',
     "decodedArgumentsResolveToThePublishedDefaults",
     "the same survivor asked of the decoder rather than of the source"),
    ("CASE-0471", "8 · Dispatch.swift:394, at runtime",
     "Sources/ProctorAgent/Dispatch.swift",
     "presentation = args.bool(\"presentation\", true)",
     "presentation = args.bool(\"presentation\", false)",
     "decodedArgumentsResolveToThePublishedDefaults",
     "the same survivor asked of the decoder rather than of the source"),
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


# swift-testing's own lines. The verdict line is the report; the started/finished
# lines are the only thing in the output that says which test was running, and
# they carry the @Test display string rather than the Swift function name.
VERDICT_RE = re.compile(r"Test run with \d+ test")
STARTED_RE = re.compile(r'Test "((?:[^"\\]|\\.)*)" started\.')
FINISHED_RE = re.compile(r'Test "((?:[^"\\]|\\.)*)" (?:passed|failed|skipped)')
TEST_ATTR_RE = re.compile(r'@Test\(\s*"((?:[^"\\]|\\.)*)"')


def display_name(function: str, tests_root: Path | None = None) -> tuple[str | None, str]:
    """The @Test display string for a Swift test function, read from the source.

    Derived rather than hand-copied, so the table below cannot drift out of step
    with the tests it names. Returns (display, why) and the display is None when
    the source cannot settle it — which makes the arming `inconclusive` rather
    than letting an unresolvable name quietly weaken the check that uses it.

    `tests_root` exists so the ambiguity refusal has a fixture. No function under
    this repository's Tests/ resolves two ways, so against the real tree that
    branch cannot be watched to fire, and a check nobody has seen fire is the
    defect this item is about.
    """
    hits: list[tuple[str, str]] = []
    decl = re.compile(r"func\s+" + re.escape(function) + r"\s*\(")
    for path in sorted((tests_root or ROOT / "Tests").rglob("*.swift")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for m in decl.finditer(text):
            head = text[max(0, m.start() - 800):m.start()]
            at = head.rfind("@Test")
            if at < 0:
                continue
            attr = TEST_ATTR_RE.match(head[at:])
            hits.append((attr.group(1) if attr else function + "()", str(path)))
    names = {h[0] for h in hits}
    if not hits:
        return None, "no @Test function named %s under %s" % (
            function, tests_root or ROOT / "Tests")
    if len(names) != 1:
        return None, ("%s resolves to %d different @Test display names (%s), so no started line "
                      "can be attributed to it" % (function, len(names), ", ".join(sorted(names))))
    return hits[0][0], "read from %s" % hits[0][1]


def run_filtered(function: str, timeout: int) -> dict:
    """Run the filtered suite and report what the output actually says.

    The exit code alone cannot separate a check firing from a process dying in
    setup, so this returns the verdict line, every test that swift-testing said
    started, and every one it said finished. DEF-208.
    """
    try:
        p = subprocess.run(["./scripts/test.sh", "--filter", function], cwd=ROOT,
                           capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"exit": 124, "verdict": "", "started": [], "finished": [],
                "timedOut": True, "tail": ""}
    out = p.stdout + p.stderr
    verdict = ""
    for line in out.splitlines():
        if VERDICT_RE.search(line):
            verdict = line.strip()
    return {"exit": p.returncode, "verdict": verdict,
            "started": STARTED_RE.findall(out), "finished": FINISHED_RE.findall(out),
            "timedOut": False, "tail": out[-1200:]}


def score_arming(display: str | None, why_display: str, r: dict, timeout: int) -> tuple[str, object, str]:
    """(state, armed, why) for one filtered run. DEF-208.

    THE RULE USED TO BE `armed = code != 0`, and a non-zero exit is not a test
    result. CASE-0461's trapping mutant gave signal 5, **zero verdict lines** and
    the suite's own `FAIL: no swift-testing verdict line`, and it was scored ARMED
    — correctly, but for a reason the rule could not see. A process that dies in
    setup, a --filter that matched nothing, and a check that fired all leave a
    non-zero exit, so the rule was reading three different events as one.

    A trap is still an arming when the log shows the named test was running as it
    died, which is the distinction the brief's own sentence turns on. So the
    evidence, not the exit code, decides:

      * a verdict line and a non-zero exit  — ARMED, the suite reported
      * a verdict line and exit 0           — NOT ARMED, the check did not fire
      * no verdict line, the named test started and never finished, non-zero exit
                                            — ARMED by trap, and it says so
      * anything else                       — `inconclusive`, naming why

    `inconclusive` is never a pass and never a fail: nothing was measured, because
    the process that would have measured it did not report.
    """
    if r["timedOut"]:
        return ("INCONCLUSIVE", None,
                "the filtered run reached the %ds bound without reporting — a starved run is "
                "the absence of a measurement, not a test that failed" % timeout)
    if r["verdict"]:
        if r["exit"] != 0:
            return "ARMED", True, "the suite reported a verdict line and exited %d" % r["exit"]
        return ("NOT ARMED", False,
                "the suite reported a verdict line and exited 0 — the check did not fire under "
                "this mutation")
    if display is None:
        return ("INCONCLUSIVE", None,
                "no swift-testing verdict line, and the test's display name could not be "
                "resolved to attribute the run: %s" % why_display)
    started, finished = set(r["started"]), set(r["finished"])
    if display in started and display not in finished and r["exit"] != 0:
        return ("ARMED", True,
                'no verdict line, and the log shows the named test was running when the process '
                'died: `Test "%s" started.` with no completion line and exit %d. A trap inside '
                'the mutated code is the check firing; a death before that line is not.'
                % (display, r["exit"]))
    if display in started and r["exit"] == 0:
        return ("INCONCLUSIVE", None,
                'the named test started and the process exited 0 with no verdict line — nothing '
                'in the output says whether the check ran to a result')
    return ("INCONCLUSIVE", None,
            'no swift-testing verdict line and nothing in the output shows `%s` running '
            '(%d test(s) started, %d finished, exit %d). A process that died in setup, and a '
            '--filter that matched no tests, are not tests that failed.'
            % (display, len(r["started"]), len(r["finished"]), r["exit"]))


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

    rows, failures, unresolved = [], 0, 0
    for case, survivor, rel, before, after, function, why in CASES:
        if args.only and args.only != function:
            continue
        landed, how = apply(rel, before, after)
        if not landed:
            # The mutation is the arming's own step, and a step that did not
            # happen leaves nothing to grade — the same rule the run below is
            # scored by, applied one level up.
            print(f"[{case}] INCONCLUSIVE — {how}", flush=True)
            rows.append({"case": case, "survivor": survivor, "file": rel,
                         "function": function, "state": "INCONCLUSIVE", "armed": None,
                         "reason": how})
            unresolved += 1
            restore_all()
            continue
        display, why_display = display_name(function)
        started = time.time()
        r = run_filtered(function, args.timeout)
        elapsed = round(time.time() - started, 1)
        subprocess.run(["git", "checkout", "--", rel], cwd=ROOT, check=True, capture_output=True)
        if rel in _APPLIED:
            _APPLIED.remove(rel)
        state, armed, reason = score_arming(display, why_display, r, args.timeout)
        rows.append({
            "case": case, "survivor": survivor, "file": rel, "function": function,
            "displayName": display, "displayNameFrom": why_display,
            "mutation": f"{before}  ->  {after}", "mutationLanded": how,
            "state": state, "armed": armed, "reason": reason,
            "exit": r["exit"], "verdict": r["verdict"],
            "testsStarted": r["started"], "testsFinished": r["finished"],
            "seconds": elapsed, "why": why,
        })
        print(f"[{case}] {state:<12} {function} exit {r['exit']} · "
              f"{r['verdict'] or reason} ({elapsed}s)", flush=True)
        if state == "NOT ARMED":
            failures += 1
        elif state == "INCONCLUSIVE":
            unresolved += 1
        Path(ROOT / args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(ROOT / args.out).write_text(json.dumps(
            {"summary": {"partial": True, "run": len(rows), "of": len(CASES),
                         "notArmed": failures, "inconclusive": unresolved},
             "cases": rows}, indent=1) + "\n")

    still = tree_dirty()
    armed_n = len(rows) - failures - unresolved
    summary = {"run": len(rows), "armed": armed_n, "notArmed": failures,
               "inconclusive": unresolved, "treeCleanAfter": not still,
               "armedByTrap": [r["case"] for r in rows
                               if r.get("state") == "ARMED" and not r.get("verdict")]}
    Path(ROOT / args.out).write_text(json.dumps({"summary": summary, "cases": rows}, indent=1) + "\n")
    print()
    print(f"armed {armed_n} of {len(rows)} · not armed {failures} · "
          f"inconclusive {unresolved} · tree clean after: {not still}")
    for r in rows:
        if r.get("state") == "INCONCLUSIVE":
            print(f"  inconclusive: {r['case']} — {r['reason']}")
    if failures or still:
        return 1
    # Distinct from 1 on purpose: an inconclusive arming is neither a pass nor a
    # failure, and an exit code that says `1` for both makes the two unreadable
    # from outside.
    return 3 if unresolved else 0


if __name__ == "__main__":
    raise SystemExit(main())
